#!/usr/bin/env python3
"""
Syncs the login-gated Yonsei GSIS CDC Job/Internship Board into the
Productivity Tracker app.

This script never sees, reads, or handles a Yonsei password anywhere.
Chrome's own saved-password autofill is what actually fills in the
credentials -- the script only ever looks at page state (is a "Logout" link
present -> login succeeded) and page content (the job board's HTML), never
at form field values themselves except to check they're non-empty.

It uses a Chrome profile stored in a directory of its own
(CHROME_PROFILE_DIR below), completely separate from Chrome's normal
multi-profile folder (~/Library/Application Support/Google/Chrome). This
matters because Chrome's "only one process per profile" lock applies to that
whole shared folder, not per-profile -- so a profile living inside it would
still collide with your regular, everyday Chrome any time it happens to be
open. A fully separate directory has no such lock to collide with, so this
can run headless without ever touching or being blocked by your normal
browsing.

This is NOT scheduled by anything on this machine (no launchd/cron job) --
it's triggered on demand from the Productivity Tracker site itself, via a
yonseijobsync:// link that a tiny local launcher app
(~/Applications/YonseiJobSync.app) hands off to this script. That link
appears both as a manual "Update now" button and an automatic once-per-day
trigger, both gated client-side to a specific account.

One-time setup:
  1. pip install playwright
     playwright install chrome
  2. Run once with a visible window so you can log in yourself:
       YONSEI_HEADLESS=false python3 yonsei_jobboard_sync.py
     A blank new Chrome profile opens (nothing saved yet), goes to the login
     page, and waits. Log in yourself, normally, by typing your ID/password
     -- Chrome will offer to save the password; click Save. The script
     detects your successful login and continues on its own from there.
  3. That's it. Every run after this one has the password saved in this
     profile, so it autofills and the whole thing runs headless with no
     window and no interaction needed.

Run manually:
  python3 yonsei_jobboard_sync.py
"""

import os
import ssl
import sys
import json
import urllib.request

from playwright.sync_api import sync_playwright

# The python.org macOS installer (as opposed to Homebrew/system Python)
# doesn't wire up root certificates by default, which makes urllib's HTTPS
# verification fail with CERTIFICATE_VERIFY_FAILED. Using certifi's bundle
# explicitly sidesteps that regardless of how Python was installed, instead
# of relying on someone remembering to run "Install Certificates.command".
try:
    import certifi
    SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    SSL_CONTEXT = None

LOGIN_URL = "https://gsis1.yonsei.ac.kr/cdc/member.asp?mid=n00_02"
BOARD_PAGE_URL = "https://gsis1.yonsei.ac.kr/cdc/board.asp?mid=n02_01&act=list&cmid=n02_01&page={page}"
BOARD_PAGES = 5  # 10 listings/page -- pulls the 50 most recent
INGEST_URL = "https://kbqwitmxpmkueryjsyip.supabase.co/functions/v1/ingest-yonsei-jobboard"

# Same anon key already embedded (public, safe to be so) in index.html.
SUPABASE_ANON_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImticXdpdG14cG1rdWVyeWpzeWlwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU1NzIxNjUsImV4cCI6MjEwMTE0ODE2NX0."
    "hOuxXxjfPemuSpthbMAD7tz30oxBkI3CyyZ8fwgwZTc"
)


def load_dotenv(path: str) -> None:
    """Minimal .env loader (no external dependency) -- reads KEY=VALUE lines
    from a gitignored local file and sets them into os.environ if not
    already set there. The ingest secret must never be hardcoded in this
    script, since this scripts/ folder is part of a public git repo -- it
    only ever lives in this untracked file (see .env.example) or in your
    shell environment."""
    if not os.path.isfile(path):
        return
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            os.environ.setdefault(key.strip(), value.strip())


load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))

INGEST_SECRET = os.environ.get("YONSEI_INGEST_SECRET")

# A dedicated, self-contained profile directory -- deliberately NOT inside
# Chrome's normal ~/Library/Application Support/Google/Chrome tree (see the
# module docstring for why). Safe to leave outside the git repo too, since
# it'll contain cookies/cache once used.
CHROME_PROFILE_DIR = os.environ.get(
    "YONSEI_CHROME_PROFILE_DIR",
    os.path.expanduser("~/.yonsei-jobboard-chrome-profile"),
)
# Headless by default (no visible window). The one-time setup run needs
# YONSEI_HEADLESS=false so you can actually see and use the login page.
HEADLESS = os.environ.get("YONSEI_HEADLESS", "true").strip().lower() != "false"


def log(msg: str) -> None:
    print(f"[yonsei_jobboard_sync] {msg}", flush=True)


def post_html_to_ingest(html: str) -> int:
    body = json.dumps({"html": html}).encode("utf-8")
    req = urllib.request.Request(
        INGEST_URL,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "apikey": SUPABASE_ANON_KEY,
            "X-Ingest-Secret": INGEST_SECRET,
        },
    )
    with urllib.request.urlopen(req, timeout=30, context=SSL_CONTEXT) as resp:
        result = json.loads(resp.read().decode("utf-8"))
    if not result.get("ok"):
        raise RuntimeError(f"ingest endpoint reported failure: {result}")
    count = result.get("count", 0)
    log(f"ingested {count} listing(s)")
    return count


def is_logged_in(page) -> bool:
    return page.locator('a[title="Logout"]').count() > 0


def main() -> int:
    if not INGEST_SECRET:
        log("ERROR: YONSEI_INGEST_SECRET is not set.")
        log("Copy .env.example to .env in this folder and fill in the real secret,")
        log("or export YONSEI_INGEST_SECRET in your shell before running this script.")
        return 1

    first_run = not os.path.isdir(CHROME_PROFILE_DIR)

    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(
            CHROME_PROFILE_DIR,
            channel="chrome",
            headless=HEADLESS,
        )
        try:
            page = context.new_page()
            log("opening login page...")
            page.goto(LOGIN_URL, wait_until="networkidle")

            if is_logged_in(page):
                log("already logged in (session still valid)")
            else:
                page.wait_for_timeout(1500)
                id_filled = bool(page.locator("#id").input_value().strip())
                pw_filled = bool(page.locator("#pw").input_value().strip())

                if id_filled and pw_filled:
                    log("autofill populated the login form, submitting...")
                    submit = page.locator('div.login_submit input[type="image"]')
                    if submit.count() == 0:
                        log("ERROR: login submit button not found -- page layout may have changed.")
                        return 1
                    submit.first.click()
                    page.wait_for_load_state("networkidle")
                elif HEADLESS:
                    log("ERROR: no saved password in this profile yet, and running headless.")
                    log("Run once with YONSEI_HEADLESS=false to log in and let Chrome save the password.")
                    return 1
                else:
                    log("No saved password yet -- please log in yourself in the window that opened.")
                    log("Waiting up to 3 minutes for you to log in...")
                    try:
                        page.wait_for_function(
                            "document.querySelector('a[title=\"Logout\"]') !== null",
                            timeout=180000,
                        )
                    except Exception:
                        log("ERROR: didn't detect a successful login within 3 minutes. Try again.")
                        return 1

                if not is_logged_in(page):
                    log("ERROR: login does not appear to have succeeded (no Logout link found).")
                    return 1
                log("login succeeded" + (" -- password now saved for future headless runs" if first_run else ""))

            total = 0
            for page_num in range(1, BOARD_PAGES + 1):
                log(f"opening job board page {page_num}/{BOARD_PAGES}...")
                page.goto(BOARD_PAGE_URL.format(page=page_num), wait_until="networkidle")
                html = page.content()
                total += post_html_to_ingest(html)
                if page_num < BOARD_PAGES:
                    page.wait_for_timeout(800)  # brief pause between pages
            log(f"done -- {total} listing(s) ingested across {BOARD_PAGES} page(s)")
            return 0
        finally:
            context.close()


if __name__ == "__main__":
    sys.exit(main())
