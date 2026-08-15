#!/usr/bin/env python3
"""
Syncs the login-gated Yonsei GSIS CDC Job/Internship Board into the
Productivity Tracker app.

This script never sees, reads, or handles a Yonsei password anywhere. It
drives a dedicated Chrome profile (via Playwright, headless -- no visible
window, no disruption to whatever you're doing) to the login page and
clicks the submit button -- Chrome's own saved-password autofill is what
actually fills in the credentials, the same way it would if you visited the
page yourself and clicked "Login". The script only ever looks at page state
(is a "Logout" link present -> login succeeded) and page content (the job
board's HTML), never at form field values before submission.

Runs fully on its own once set up -- no manual browser step per run, no
window ever appears, doesn't touch your normal Chrome profile or windows at
all.

One-time setup:
  1. pip install playwright
     playwright install chrome
  2. In Chrome, create a NEW profile dedicated to this script (menu -> "Add
     Profile"). This has to be a separate profile, not your everyday one --
     Chrome won't let two processes drive the same profile at once, so
     reusing your normal profile would conflict with a normal Chrome window
     you have open when the script runs.
  3. In that new profile, manually log into
     https://gsis1.yonsei.ac.kr/cdc/member.asp?mid=n00_02 once, and let
     Chrome offer to save the password. That saved password is what makes
     autofill work here -- after this, you never interact with that profile
     again.
  4. Find that profile's folder name (chrome://version in that profile shows
     "Profile Path", e.g. ".../Google/Chrome/Profile 3") and set
     CHROME_PROFILE_DIR below (or via the YONSEI_CHROME_PROFILE_DIR env var).

Run manually:
  python3 yonsei_jobboard_sync.py

Run on a schedule: see yonsei_jobboard_sync.plist in this same folder for a
launchd job that runs this periodically, fully unattended.
"""

import os
import sys
import json
import urllib.request

from playwright.sync_api import sync_playwright

LOGIN_URL = "https://gsis1.yonsei.ac.kr/cdc/member.asp?mid=n00_02"
BOARD_URL = "https://gsis1.yonsei.ac.kr/cdc/board.asp?mid=n02_01"
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

# CHANGE THIS to your dedicated profile's folder name (see setup step 4
# above), or set the YONSEI_CHROME_PROFILE_DIR env var instead of editing
# this file.
CHROME_PROFILE_DIR = os.environ.get(
    "YONSEI_CHROME_PROFILE_DIR",
    os.path.expanduser("~/Library/Application Support/Google/Chrome/Profile Yonsei Bot"),
)


def log(msg: str) -> None:
    print(f"[yonsei_jobboard_sync] {msg}", flush=True)


def post_html_to_ingest(html: str) -> None:
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
    with urllib.request.urlopen(req, timeout=30) as resp:
        result = json.loads(resp.read().decode("utf-8"))
    if not result.get("ok"):
        raise RuntimeError(f"ingest endpoint reported failure: {result}")
    log(f"ingested {result.get('count', 0)} listing(s)")


def main() -> int:
    if not INGEST_SECRET:
        log("ERROR: YONSEI_INGEST_SECRET is not set.")
        log("Copy .env.example to .env in this folder and fill in the real secret,")
        log("or export YONSEI_INGEST_SECRET in your shell before running this script.")
        return 1
    if not os.path.isdir(CHROME_PROFILE_DIR):
        log(f"ERROR: Chrome profile directory not found: {CHROME_PROFILE_DIR}")
        log("Set YONSEI_CHROME_PROFILE_DIR or edit CHROME_PROFILE_DIR in this script.")
        return 1

    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(
            CHROME_PROFILE_DIR,
            channel="chrome",
            headless=True,
        )
        try:
            page = context.new_page()
            log("opening login page...")
            page.goto(LOGIN_URL, wait_until="networkidle")
            # Give Chrome's autofill a moment to populate the saved
            # credentials before we click submit.
            page.wait_for_timeout(1500)

            submit = page.locator('div.login_submit input[type="image"]')
            if submit.count() == 0:
                log("ERROR: login submit button not found -- page layout may have changed.")
                return 1
            submit.first.click()
            page.wait_for_load_state("networkidle")

            if page.locator('a[title="Logout"]').count() == 0:
                log("ERROR: login does not appear to have succeeded (no Logout link found).")
                log("Check that the saved password in this Chrome profile is still valid.")
                return 1
            log("login succeeded")

            log("opening job board...")
            page.goto(BOARD_URL, wait_until="networkidle")
            html = page.content()

            post_html_to_ingest(html)
            return 0
        finally:
            context.close()


if __name__ == "__main__":
    sys.exit(main())
