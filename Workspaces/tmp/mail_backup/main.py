import asyncio
import json
from pathlib import Path
from playwright.async_api import async_playwright

OUTLOOK_URL = "https://outlook.office.com/mail/"

BASE_DIR = Path.home() / "Workspaces/tmp/mail_backup/2025"
SAVE_DIR = BASE_DIR / "downloaded"
FAILED_LOG = BASE_DIR / "failed_ids.json"

SAVE_DIR.mkdir(parents=True, exist_ok=True)
FAILED_LOG.touch(exist_ok=True)

USER_DATA_DIR = str(Path.home() / "Workspaces/tmp/playwright_profile")


def load_failed_ids():
    try:
        with open(FAILED_LOG, "r") as f:
            data = json.load(f)
            if isinstance(data, list):
                return data
    except:
        pass
    return []


def save_failed_id(msg_id):
    failed_ids = load_failed_ids()
    failed_ids.append(msg_id)
    with open(FAILED_LOG, "w") as f:
        json.dump(failed_ids, f, indent=2, ensure_ascii=False)


async def find_anywhere(page, selector, timeout=800):
    # 페이지 + 모든 프레임에서 selector 탐색
    frames = [page] + page.frames
    for f in frames:
        try:
            el = await f.wait_for_selector(selector, timeout=timeout)
            if el:
                return el
        except:
            pass

    # 팝오버는 종종 frame 없이 page에서 잡힘
    try:
        return await page.wait_for_selector(selector, timeout=timeout)
    except:
        return None


async def get_message_list(page):
    # Outlook 새 UI 기준
    return page.locator('div[role="listbox"][aria-label="메시지 목록"]')


async def get_visible_mail_items(page):
    return page.locator('div[role="option"]')


async def download_eml(page, msg_id):
    try:
        # 1) 상위 메뉴 "다운로드"
        dl_menu = await find_anywhere(
            page,
            'span.fui-MenuItem__content:has-text("다운로드")',
            timeout=1000
        )
        if not dl_menu:
            print(f"   ❌ 다운로드 메뉴 없음 (id={msg_id})")
            save_failed_id(msg_id)
            return False

        await dl_menu.hover()
        await page.wait_for_timeout(120)

        # 2) 하위 메뉴 "EML" 나타남
        eml_menu = await find_anywhere(
            page,
            'span.fui-MenuItem__content:has-text("EML")',
            timeout=1200
        )
        if not eml_menu:
            print(f"   ❌ EML 하위 메뉴 없음 (id={msg_id})")
            save_failed_id(msg_id)
            return False

        # 3) 다운로드 이벤트
        async with page.expect_download() as dl_info:
            await eml_menu.click()

        dl = await dl_info.value
        save_path = SAVE_DIR / dl.suggested_filename
        await dl.save_as(str(save_path))

        print(f"   ✔ 저장됨 {save_path}")
        return True

    except Exception as e:
        print(f"   ❌ 다운로드 실패(id={msg_id}): {e}")
        save_failed_id(msg_id)
        return False


async def main(retry_mode=False):
    async with async_playwright() as p:

        context = await p.chromium.launch_persistent_context(
            user_data_dir=USER_DATA_DIR,
            headless=False,
            accept_downloads=True
        )

        page = await context.new_page()
        await page.goto(OUTLOOK_URL)

        if not retry_mode:
            print("\n👉 2025 폴더로 이동한 뒤 Enter")
            input()

        message_list = await get_message_list(page)

        failed_ids = load_failed_ids() if retry_mode else []

        print("\n📥 다운로드 시작 (retry_mode=%s)..." % retry_mode)
        processed = 0
        seen_ids = set()

        while True:
            items = await get_visible_mail_items(page)
            count = await items.count()

            if count == 0:
                break

            for i in range(count):
                item = items.nth(i)

                msg_id = await item.get_attribute("id")
                if msg_id is None:
                    continue

                if msg_id in seen_ids:
                    continue
                seen_ids.add(msg_id)

                # 재시도 모드면 실패 목록만 처리
                if retry_mode and msg_id not in failed_ids:
                    continue

                # 우클릭
                try:
                    await item.click(button="right")
                except:
                    save_failed_id(msg_id)
                    continue

                await page.wait_for_timeout(80)
                await download_eml(page, msg_id)
                processed += 1

            # 스크롤 (속도 최적화)
            await message_list.evaluate("(el)=>el.scrollTop += el.clientHeight")
            await page.wait_for_timeout(400)

        print("\n📦 다운로드 완료")
        print(f"총 처리: {processed}개")
        print(f"실패 로그: {FAILED_LOG}")


if __name__ == "__main__":
    # retry_mode=False → 처음 다운로드
    # retry_mode=True → failed_ids.json 기준 재다운로드
    asyncio.run(main(retry_mode=False))
