import asyncio
from pathlib import Path
from playwright.async_api import async_playwright, TimeoutError

OUTLOOK_URL = "https://outlook.office.com/mail/"
SAVE_DIR = Path.home() / "Workspaces/tmp/mail_backup/2025"
SAVE_DIR.mkdir(parents=True, exist_ok=True)

USER_DATA_DIR = str(Path.home() / "Workspaces/tmp/playwright_profile")

EXPECTED_TOTAL = 1933


# menu click with timeout
async def try_click(locator, timeout=500):
    try:
        await locator.click(timeout=timeout)
        return True
    except Exception as e:
        return False


async def get_message_list_pane(page):
    selectors = [
        'div[role="listbox"][aria-label="메시지 목록"]',
        'div[role="listbox"][aria-label="Message list"]'
    ]
    for sel in selectors:
        try:
            await page.wait_for_selector(sel, timeout=5000)
            return page.locator(sel)
        except:
            pass
    raise Exception("Message list pane not found (role=listbox).")


async def download_eml(page, item):
    """
    메일 아이템을 우클릭하여 컨텍스트 메뉴를 열고 EML 다운로드
    """
    try:
        # 1. 우클릭으로 컨텍스트 메뉴 열기
        await item.click(button="right")
        await page.wait_for_timeout(300)
        
        # 2. 메뉴 확인
        menu = page.locator("[role='menu']")
        try:
            await menu.wait_for(state="visible", timeout=1000)
        except:
            print("  ⚠ 메뉴가 나타나지 않음")
            return False
        
        # 3. "다운로드" 버튼 클릭
        download_btn = menu.get_by_text("다운로드")
        if not await try_click(download_btn, timeout=500):
            print("  ❌ '다운로드' 버튼 클릭 실패")
            await page.keyboard.press("Escape")
            return False
        
        await page.wait_for_timeout(200)
        
        # 4. "EML로 다운로드" 클릭 및 다운로드 대기
        async with page.expect_download(timeout=3000) as download_info:
            eml_btn = menu.get_by_text("EML로 다운로드")
            if not await try_click(eml_btn, timeout=500):
                print("  ❌ 'EML로 다운로드' 버튼 클릭 실패")
                await page.keyboard.press("Escape")
                return False
        
        download = await download_info.value
        save_path = SAVE_DIR / download.suggested_filename
        await download.save_as(str(save_path))
        
        print(f"✔ 저장: {save_path.name}")
        return True
        
    except TimeoutError:
        print("  ⏱ 다운로드 타임아웃")
        await page.keyboard.press("Escape")
        return False
    except Exception as e:
        print(f"  ❌ 다운로드 오류: {e}")
        await page.keyboard.press("Escape")
        return False


async def main():
    async with async_playwright() as p:
        context = await p.chromium.launch_persistent_context(
            user_data_dir=USER_DATA_DIR,
            headless=False,
            accept_downloads=True
        )
        page = await context.new_page()
        await page.goto(OUTLOOK_URL)

        print("\n" + "="*70)
        print("📧 Outlook 메일 자동 다운로드")
        print("="*70)
        print("\n👉 2025 폴더로 이동한 후 Enter를 눌러주세요")
        print("   (메일 목록이 보이는 상태에서 시작)\n")
        input()

        # 메시지 목록 찾기
        try:
            message_list = await get_message_list_pane(page)
            print("✓ 메시지 목록을 찾았습니다\n")
        except Exception as e:
            print(f"❌ 오류: {e}")
            return

        processed = 0
        last_count = -1
        no_new = 0

        print("📥 다운로드 시작...\n")
        print(f"{'Progress':<12} {'Loaded':<10} {'Downloaded':<12} {'Status'}")
        print("-" * 70)

        while processed < EXPECTED_TOTAL:
            # 현재 로드된 메일 아이템 수 확인
            mail_items = page.locator('div[role="option"]')
            count = await mail_items.count()

            # 새로운 메일이 로드되지 않으면 카운트 증가
            if count == last_count:
                no_new += 1
            else:
                no_new = 0

            last_count = count

            # 5번 연속 새 메일 없으면 종료
            if no_new > 5:
                print("\n📌 더 이상 로드되는 메일이 없습니다.")
                break

            # 진행 상황 출력
            progress = f"{processed}/{EXPECTED_TOTAL}"
            print(f"{progress:<12} {count:<10} {processed:<12}", end="\r")

            # 현재 로드된 메일들 처리
            for i in range(processed, count):
                try:
                    item = mail_items.nth(i)

                    # 메일 다운로드 시도
                    success = await download_eml(page, item)
                    
                    if success:
                        processed += 1
                        progress = f"{processed}/{EXPECTED_TOTAL}"
                        percentage = (processed / EXPECTED_TOTAL) * 100
                        print(f"{progress:<12} {count:<10} {processed:<12} ✓ [{percentage:.1f}%]")
                    else:
                        print(f"{'Skip':<12} {count:<10} {processed:<12} ⚠ Index {i} 실패")
                    
                    # 다음 메일 처리 전 짧은 대기
                    await page.wait_for_timeout(100)

                except Exception as e:
                    print(f"{'Error':<12} {count:<10} {processed:<12} ❌ Index {i}: {e}")

            # 스크롤하여 더 많은 메일 로드
            await message_list.evaluate("(el) => el.scrollTop += el.clientHeight * 0.95")
            await page.wait_for_timeout(500)

        print("\n" + "="*70)
        print("🎉 작업 완료!")
        print(f"📊 총 다운로드: {processed}/{EXPECTED_TOTAL} ({processed/EXPECTED_TOTAL*100:.1f}%)")
        print(f"📁 저장 위치: {SAVE_DIR}")
        print("="*70 + "\n")

        print("브라우저를 종료하려면 Enter를 누르세요...")
        input()


if __name__ == "__main__":
    asyncio.run(main())