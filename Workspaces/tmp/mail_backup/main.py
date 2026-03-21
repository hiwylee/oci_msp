import asyncio
import json
from pathlib import Path
import email
import shutil
from email.utils import parsedate_to_datetime
from playwright.async_api import async_playwright

# ============================================================
# 설정
# ============================================================

OUTLOOK_URL = "https://outlook.office.com/mail/"

BASE_DIR = Path.home() / "Workspaces/tmp/mail_backup/2025"
SAVE_DIR = BASE_DIR / "downloaded"
FAILED_LOG = BASE_DIR / "failed_ids.json"

SAVE_DIR.mkdir(parents=True, exist_ok=True)
FAILED_LOG.touch(exist_ok=True)

USER_DATA_DIR = str(Path.home() / "Workspaces/tmp/playwright_profile")


# ============================================================
# 실패 ID 저장/로드
# ============================================================

def load_failed_ids():
    try:
        with open(FAILED_LOG, "r") as f:
            data = json.load(f)
            return data if isinstance(data, list) else []
    except:
        return []


def save_failed_id(msg_id):
    failed_ids = load_failed_ids()
    if msg_id not in failed_ids:
        failed_ids.append(msg_id)
        with open(FAILED_LOG, "w") as f:
            json.dump(failed_ids, f, indent=2, ensure_ascii=False)


# ============================================================
# Frame/Popover 어디서든 selector 탐색
# ============================================================

async def find_anywhere(page, selector, timeout=800):
    frames = [page] + page.frames
    for f in frames:
        try:
            el = await f.wait_for_selector(selector, timeout=timeout)
            if el:
                return el
        except:
            pass

    try:
        return await page.wait_for_selector(selector, timeout=timeout)
    except:
        return None


# ============================================================
# Outlook 메시지 목록/항목
# ============================================================

async def get_message_list(page):
    return page.locator('div[role="listbox"][aria-label="메시지 목록"]')


async def get_visible_mail_items(page):
    return page.locator('div[role="option"]')


# ============================================================
# EML 다운로드
# ============================================================

async def download_eml(page, msg_id):
    try:
        # 상위 "다운로드"
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

        # "EML로 다운로드"
        eml_menu = await find_anywhere(
            page,
            'span.fui-MenuItem__content:has-text("EML")',
            timeout=1500
        )
        if not eml_menu:
            print(f"   ❌ EML 메뉴 없음 (id={msg_id})")
            save_failed_id(msg_id)
            return False

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


# ============================================================
# 다운로드 완료 후 날짜별 분류
# ============================================================

def organize_downloaded_by_date():
    print("\n🗂  다운로드 파일 날짜별 정리 시작…")

    for eml_file in SAVE_DIR.glob("*.eml"):
        try:
            with open(eml_file, "r", encoding="utf-8", errors="ignore") as f:
                msg = email.message_from_file(f)

            date_header = msg.get("Date")
            if not date_header:
                print(f"   ❓ 날짜 없음 → skip {eml_file.name}")
                continue

            dt = parsedate_to_datetime(date_header)
            folder_name = dt.strftime("%Y-%m-%d")

            target_folder = SAVE_DIR / folder_name
            target_folder.mkdir(exist_ok=True)

            shutil.move(str(eml_file), str(target_folder / eml_file.name))

            print(f"   ✔ {eml_file.name} → {folder_name}/")

        except Exception as e:
            print(f"   ❌ 정리 실패: {eml_file.name} ({e})")

    print("🎉 날짜별 정리 완료!\n")


# ============================================================
# MAIN (다운로드 + 재시도모드 지원)
# ============================================================

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
            print("\n👉 아웃룩에서 2025 폴더로 이동한 뒤 Enter")
            input()

        message_list = await get_message_list(page)
        failed_ids = load_failed_ids() if retry_mode else []

        print("\n📥 다운로드 시작 (retry_mode=%s)..." % retry_mode)

        processed = 0
        seen_ids = set()
        scroll_loop = 0

        while True:
            items = await get_visible_mail_items(page)
            count = await items.count()

            if count == 0:
                scroll_loop += 1
                if scroll_loop > 10:
                    break
                await message_list.evaluate("(el)=>el.scrollTop += 500")
                await page.wait_for_timeout(400)
                continue

            scroll_loop = 0

            for i in range(count):
                try:
                    item = items.nth(i)
                    msg_id = await item.evaluate("el => el.getAttribute('id')", timeout=500)

                    if not msg_id:
                        continue

                    if msg_id in seen_ids:
                        continue
                    seen_ids.add(msg_id)

                except Exception:
                    continue

                if retry_mode and msg_id not in failed_ids:
                    continue

                try:
                    await item.click(button="right", timeout=500)
                except:
                    save_failed_id(msg_id)
                    continue

                await page.wait_for_timeout(80)

                await download_eml(page, msg_id)
                processed += 1

            await message_list.evaluate("(el)=>el.scrollTop += el.clientHeight")
            await page.wait_for_timeout(400)

        print("\n📦 다운로드 완료")
        print(f"총 처리: {processed}개")
        print(f"실패 로그: {FAILED_LOG}")


# ============================================================
# 실행
# ============================================================

if __name__ == "__main__":
    asyncio.run(main(retry_mode=False))
    organize_downloaded_by_date()
