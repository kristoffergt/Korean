#!/usr/bin/env python3
"""
Walks today's postings on the login-gated Yonsei GSIS CDC Job/Internship
Board one by one -- each posting's own detail page, not just the board's
list view -- and writes the full text of each into a local JSON file.
Nothing is written to Supabase or anywhere outside your own Mac.

Reuses the exact same login approach as yonsei_jobboard_sync.py: Chrome's
own saved-password autofill in a dedicated, isolated Chrome profile. This
script never sees, reads, or handles a Yonsei password anywhere -- see that
script's docstring for the full explanation and one-time setup, which is
shared between the two (same profile directory, same login page).

How it walks postings: starting from the most recent posting (the top item
on the board's list page), it reads each detail page's own "Next" link,
which shows the next posting's title AND date. If that date is still
today, it follows it and keeps going; the first time it sees a date
earlier than today, it stops. No need to know how many postings there are
in advance, and no separate list-page scraping needed once it's started.

NOTE: unlike yonsei_jobboard_sync.py's board-list parsing, the detail-page
text extraction here has NOT been verified against a real saved page (it's
login-gated, so there was nothing to test against ahead of time). It's a
best-effort read of the visible layout (Title/Type/Deadline/Date/Read
metadata, then free-text content, then a Prev/Next row). If the first real
run doesn't find postings or the "Next" link correctly, run once with
YONSEI_HEADLESS=false to see what's actually on the page and adjust the
DESCRIPTION/NEXT parsing below -- same debugging approach as the autofill
issue you hit earlier.

Output: writes to
  /Users/kristoffertiedemann/Desktop/Personal/Job Related/Claude Jobbing/cdc_jobs_<today>.json
as a JSON array of {title, type_industry, deadline, date_posted, url, description}.

Run manually:
  python3 yonsei_jobboard_detail_fetch.py
"""

import os
import re
import sys
import json
import ssl
import datetime

from urllib.parse import urljoin
from playwright.sync_api import sync_playwright

try:
    import certifi  # noqa: F401 -- not used for HTTP here, kept for parity with the sync script's env
except ImportError:
    pass

LOGIN_URL = "https://gsis1.yonsei.ac.kr/cdc/member.asp?mid=n00_02"
BOARD_LIST_URL = "https://gsis1.yonsei.ac.kr/cdc/board.asp?mid=n02_01&act=list&cmid=n02_01&page=1"

OUTPUT_DIR = "/Users/kristoffertiedemann/Desktop/Personal/Job Related/Claude Jobbing"

CHROME_PROFILE_DIR = os.environ.get(
    "YONSEI_CHROME_PROFILE_DIR",
    os.path.expanduser("~/.yonsei-jobboard-chrome-profile"),
)
HEADLESS = os.environ.get("YONSEI_HEADLESS", "true").strip().lower() != "false"
MAX_POSTINGS = int(os.environ.get("YONSEI_DETAIL_MAX", "60"))  # safety cap, not a normal stopping point


def log(msg: str) -> None:
    print(f"[yonsei_jobboard_detail_fetch] {msg}", flush=True)


def is_logged_in(page) -> bool:
    return page.locator('a[title="Logout"]').count() > 0


def login(context) -> "object":
    page = context.new_page()
    log("opening login page...")
    page.goto(LOGIN_URL, wait_until="networkidle")

    if is_logged_in(page):
        log("already logged in (session still valid)")
        return page

    page.wait_for_timeout(1500)
    id_filled = bool(page.locator("#id").input_value().strip())
    pw_filled = bool(page.locator("#pw").input_value().strip())

    if id_filled and pw_filled:
        log("autofill populated the login form, submitting...")
        submit = page.locator('div.login_submit input[type="image"]')
        if submit.count() == 0:
            raise RuntimeError("login submit button not found -- page layout may have changed.")
        submit.first.click()
        page.wait_for_load_state("networkidle")
    elif HEADLESS:
        raise RuntimeError(
            "no saved password in this profile yet, and running headless. "
            "Run yonsei_jobboard_sync.py's one-time setup first (same shared profile)."
        )
    else:
        log("No saved password yet -- please log in yourself in the window that opened.")
        page.wait_for_function(
            "document.querySelector('a[title=\"Logout\"]') !== null", timeout=180000,
        )

    if not is_logged_in(page):
        raise RuntimeError("login does not appear to have succeeded (no Logout link found).")
    log("login succeeded")
    return page


# Parses the board's own English date format, e.g. "Aug 20, 2026".
def parse_board_date(text: str):
    text = text.strip()
    for fmt in ("%b %d, %Y", "%B %d, %Y"):
        try:
            return datetime.datetime.strptime(text, fmt).date()
        except ValueError:
            continue
    return None


def extract_trailing_date(line: str):
    m = re.search(r"\(([^)]+)\)\s*$", line.strip())
    return parse_board_date(m.group(1)) if m else None


def find_value_after_label(lines, label):
    for i, l in enumerate(lines):
        if l == label and i + 1 < len(lines):
            return lines[i + 1]
    return None


def parse_detail_page(page) -> dict:
    text = page.locator("body").inner_text()
    lines = [l.strip() for l in text.split("\n") if l.strip()]

    title = find_value_after_label(lines, "Title")
    type_industry = find_value_after_label(lines, "Type")
    deadline = find_value_after_label(lines, "Deadline")
    date_posted = find_value_after_label(lines, "Date")

    read_idx = next((i for i, l in enumerate(lines) if l == "Read"), None)
    next_idx = next((i for i, l in enumerate(lines) if l == "Next"), None)
    desc_start = (read_idx + 2) if read_idx is not None else 0
    desc_end = next_idx if next_idx is not None else len(lines)
    description = "\n".join(lines[max(desc_start, 0):desc_end]).strip()

    return {
        "title": title,
        "type_industry": type_industry,
        "deadline": deadline,
        "date_posted": date_posted,
        "url": page.url,
        "description": description,
    }


def find_next(page):
    """Returns (next_url, next_date) for the posting linked from the
    detail page's own "Next" row, or (None, None) if there isn't one."""
    next_label = page.locator("text=Next").first
    if next_label.count() == 0:
        return None, None
    next_link = next_label.locator("xpath=following::a[1]")
    if next_link.count() == 0:
        return None, None
    href = next_link.get_attribute("href")
    if not href:
        return None, None
    next_url = urljoin(page.url, href)

    text = page.locator("body").inner_text()
    lines = [l.strip() for l in text.split("\n") if l.strip()]
    next_idx = next((i for i, l in enumerate(lines) if l == "Next"), None)
    next_date = None
    if next_idx is not None and next_idx + 1 < len(lines):
        next_date = extract_trailing_date(lines[next_idx + 1])
    return next_url, next_date


def main() -> int:
    today = datetime.date.today()
    log(f"today (local date) is {today.isoformat()}")

    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(
            CHROME_PROFILE_DIR,
            channel="chrome",
            headless=HEADLESS,
        )
        try:
            page = login(context)

            log("opening job board list, page 1...")
            page.goto(BOARD_LIST_URL, wait_until="networkidle")
            first_link = page.locator('a[href*="idx="]').first
            if first_link.count() == 0:
                log("ERROR: no postings found on the list page -- page layout may have changed.")
                return 1
            first_link.click()
            page.wait_for_load_state("networkidle")

            results = []
            for i in range(MAX_POSTINGS):
                record = parse_detail_page(page)
                log(f"[{i+1}] {record['title']!r} -- {record['date_posted']} -- {len(record['description'])} chars")
                results.append(record)

                next_url, next_date = find_next(page)
                if next_url is None:
                    log("no Next link found -- stopping (reached the end of the board, or parsing failed).")
                    break
                if next_date is None:
                    log("couldn't parse the Next posting's date -- stopping to be safe rather than loop forever.")
                    break
                if next_date != today:
                    log(f"Next posting is dated {next_date.isoformat()} (not today) -- stopping.")
                    break

                page.goto(next_url, wait_until="networkidle")
            else:
                log(f"hit the {MAX_POSTINGS}-posting safety cap -- stopping.")

        finally:
            context.close()

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    out_path = os.path.join(OUTPUT_DIR, f"cdc_jobs_{today.isoformat()}.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    log(f"wrote {len(results)} posting(s) to {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
