#!/usr/bin/env python3
"""
Simplified Krisp Transcript Downloader
Iterates through visible meeting items and downloads them one by one
No URL tracking, no ID extraction - just click and download
"""

import json
import sys
import os
import re
import time
from pathlib import Path
from datetime import datetime
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout
from playwright_stealth import stealth_sync
from dotenv import load_dotenv
import argparse
import importlib.util

# Configuration
CACHE_DIR = Path.home() / ".cache/sketchybar"
CACHE_FILE = CACHE_DIR / "processed-krisp-meetings.json"
PROGRESS_FILE = CACHE_DIR / "krisp-progress.json"
LOG_FILE = Path.home() / ".config/sketchybar/logs/krisp-download.log"
TRANSCRIPTS_DIR = Path.home() / ".config/sketchybar/krisp-transcripts"
AUTH_FILE = Path.home() / ".config/sketchybar/krisp-auth.json"
HELPERS_DIR = Path.home() / ".config/sketchybar/helpers"

# Retry configuration
MAX_RETRIES = 3
RETRY_DELAY_BASE = 2  # seconds (exponential backoff)

# Ensure directories exist
CACHE_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
TRANSCRIPTS_DIR.mkdir(parents=True, exist_ok=True)

def log(message, level="INFO"):
    """Log message with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"[{timestamp}] [{level}] {message}"
    print(log_line)
    with open(LOG_FILE, "a") as f:
        f.write(log_line + "\n")

def load_cache_module():
    """Load cache module for tracking processed meetings"""
    try:
        spec = importlib.util.spec_from_file_location("krisp_cache", HELPERS_DIR / "krisp-cache.py")
        cache = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cache)
        return cache
    except Exception as e:
        log(f"Failed to load cache module: {str(e)}", "ERROR")
        return None

def load_env():
    """Load environment variables from dotfiles .env"""
    env_paths = [
        Path.home() / "repos/02_personal/dotfiles/.env",
        Path.home() / "dotfiles/.env",
    ]

    for env_path in env_paths:
        if env_path.exists():
            load_dotenv(env_path)
            log(f"Loaded .env from: {env_path}")
            return

    log("No .env file found, using environment variables only", "WARN")

def load_krisp_auth():
    """Load Krisp authentication from JSON file"""
    if not AUTH_FILE.exists():
        log(f"Auth file not found: {AUTH_FILE}", "ERROR")
        log("Run: bash ~/.config/sketchybar/helpers/krisp-refresh-auth.sh", "ERROR")
        raise FileNotFoundError(f"Krisp auth file not found at {AUTH_FILE}")

    with open(AUTH_FILE) as f:
        auth_data = json.load(f)

    cookies = auth_data.get('cookies', [])
    localstorage = auth_data.get('localStorage', {})
    updated_at = auth_data.get('updated_at', 'unknown')

    log(f"Loaded auth from file (updated: {updated_at})")
    return cookies, localstorage

def convert_cookie_format(cookie):
    """Convert browser cookie format to Playwright format"""
    pw_cookie = {
        'name': cookie['name'],
        'value': cookie['value'],
        'domain': cookie['domain'],
        'path': cookie['path'],
    }

    if 'expires' in cookie and cookie['expires'] != -1:
        pw_cookie['expires'] = cookie['expires']
    if 'httpOnly' in cookie:
        pw_cookie['httpOnly'] = cookie['httpOnly']
    if 'secure' in cookie:
        pw_cookie['secure'] = cookie['secure']
    if 'sameSite' in cookie and cookie['sameSite'] in ['Strict', 'Lax', 'None']:
        pw_cookie['sameSite'] = cookie['sameSite']

    return pw_cookie

def download_transcript_from_current_page(page, retry_count=0):
    """
    Download transcript from currently loaded meeting detail page with retry logic
    Assumes we're already on a meeting detail page
    Returns (status: str, transcript_text: str or None, meeting_id: str or None)
    Status: 'success', 'not_ready', 'error'
    """
    try:
        # Wait for page to load
        page.wait_for_selector('text=/Recording|Transcript/', state='visible', timeout=15000)
        log("Meeting page loaded")

        # Extract meeting ID from URL
        current_url = page.url
        meeting_id_match = re.search(r'--([0-9a-f]{32})', current_url)
        if meeting_id_match:
            meeting_id = meeting_id_match.group(1)
            log(f"Meeting ID: {meeting_id}")
        else:
            log("Could not extract meeting ID from URL", "WARN")
            meeting_id = None

        # Give React time to hydrate
        page.wait_for_timeout(3000)

        # Find 3-dot menu button with retries
        log("Looking for 3-dot menu button...")
        menu_button = page.locator('button[data-test-id="Dropdown"]').first

        try:
            menu_button.wait_for(state="visible", timeout=10000)
            log("Clicking 3-dot menu...")
            menu_button.click()
            page.wait_for_timeout(2000)
        except PlaywrightTimeout:
            # Retry if we haven't exceeded max retries
            if retry_count < MAX_RETRIES:
                delay = RETRY_DELAY_BASE ** retry_count
                log(f"Menu button not found, retrying in {delay}s (attempt {retry_count + 1}/{MAX_RETRIES})...", "WARN")
                time.sleep(delay)
                return download_transcript_from_current_page(page, retry_count + 1)
            else:
                log("Menu button not found after retries", "ERROR")
                return ('error', None, meeting_id)

        # Find Copy transcript button
        log("Looking for Copy transcript button...")
        copy_button = page.locator('button[data-test-id="CopyTranscriptBtn"]').first

        try:
            copy_button.wait_for(state="visible", timeout=3000)
        except PlaywrightTimeout:
            log("Copy transcript button not found - transcript not ready", "WARN")
            return ('not_ready', None, meeting_id)

        # Check if button is disabled
        is_disabled = page.locator('button[data-test-id="CopyTranscriptBtn"][disabled]').count() > 0
        if is_disabled:
            log("Copy transcript button is disabled - transcript still processing", "WARN")
            return ('not_ready', None, meeting_id)

        log("Clicking Copy transcript button...")
        copy_button.click()
        page.wait_for_timeout(1500)  # Slightly longer wait for clipboard

        # Read from clipboard with retry
        log("Reading transcript from clipboard...")
        transcript_text = None
        for attempt in range(3):
            transcript_text = page.evaluate("""
                async () => {
                    try {
                        return await navigator.clipboard.readText();
                    } catch (err) {
                        return null;
                    }
                }
            """)
            if transcript_text:
                break
            if attempt < 2:
                log(f"Clipboard empty, retrying... ({attempt + 1}/3)")
                time.sleep(1)

        if not transcript_text:
            log("Failed to read clipboard after retries", "ERROR")
            return ('error', None, meeting_id)

        # Validate transcript has content
        if len(transcript_text) < 10:
            log("Transcript too short, likely empty", "ERROR")
            return ('error', None, meeting_id)

        # Count speakers
        speaker_pattern = r'^([^|]+) \| \d+:\d+$'
        all_speakers = set()
        for line in transcript_text.split('\n'):
            match = re.match(speaker_pattern, line.strip())
            if match:
                speaker_name = match.group(1).strip()
                all_speakers.add(speaker_name)

        log(f"✓ Transcript has {len(all_speakers)} speakers: {', '.join(list(all_speakers)[:4])}")

        return ('success', transcript_text, meeting_id)

    except Exception as e:
        log(f"Error downloading transcript: {str(e)}", "ERROR")
        return ('error', None, None)

def main():
    load_env()

    parser = argparse.ArgumentParser(description='Download Krisp transcripts (simplified)')
    parser.add_argument('--limit', type=int, default=5, help='Max number of meetings to process')
    parser.add_argument('--visible', action='store_true', help='Run in visible mode')
    args = parser.parse_args()

    log(f"Starting simplified Krisp downloader (limit: {args.limit})...")

    # Load cache module for tracking processed meetings
    cache = load_cache_module()
    if not cache:
        log("WARNING: Cache module not available - downloads may be duplicated", "WARN")

    # Load auth
    cookies, localstorage = load_krisp_auth()

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=not args.visible,
            args=['--disable-blink-features=AutomationControlled']
        )

        context = browser.new_context(
            user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
            permissions=['clipboard-read', 'clipboard-write']
        )

        # Add cookies
        playwright_cookies = [convert_cookie_format(c) for c in cookies]
        context.add_cookies(playwright_cookies)

        page = context.new_page()
        # NOTE: Disabling stealth_sync - it breaks Krisp's React app with JS errors
        # stealth_sync(page)

        # Set localStorage
        page.goto("https://app.krisp.ai/", wait_until="domcontentloaded")
        for key, value in localstorage.items():
            page.evaluate(f'localStorage.setItem("{key}", "{value}")')

        # Reload page so React picks up localStorage
        page.reload(wait_until="load")
        page.wait_for_timeout(3000)

        # Navigate to meeting list
        log("Navigating to meeting list page...")
        page.goto("https://app.krisp.ai/meeting-notes?page=1&limit=20", wait_until="load", timeout=30000)

        # Wait for meeting items to appear
        try:
            page.wait_for_selector('a.meeting-item', state='visible', timeout=15000)
            log("Meeting list loaded")
        except PlaywrightTimeout:
            log("Meeting items not found on page", "ERROR")

            # Debug: Check what IS on the page
            page_title = page.title()
            page_url = page.url
            log(f"Page title: {page_title}")
            log(f"Page URL: {page_url}")

            # Check for login indicators
            has_login = page.locator('input[type="email"]').count() > 0
            has_signin = page.locator('text=/Sign in|Log in/i').count() > 0

            if has_login or has_signin:
                log("LOGIN PAGE DETECTED - Session expired!", "ERROR")
                log("Run: bash ~/.config/sketchybar/helpers/krisp-refresh-auth.sh", "ERROR")
            else:
                # Take screenshot for debugging
                screenshot_path = "/tmp/krisp-debug.png"
                page.screenshot(path=screenshot_path)
                log(f"Screenshot saved to: {screenshot_path}")
                log(f"Page appears blank or has unexpected content")

            sys.exit(1)

        page.wait_for_timeout(3000)  # Extra wait for React

        # Dismiss any modal popups (e.g., "What's New") by pressing Escape
        log("Dismissing any modal popups...")
        page.keyboard.press('Escape')
        page.wait_for_timeout(1000)

        # Get all meeting items
        meeting_items = page.locator('a.meeting-item[data-test-id="ListItem"]').all()
        total_meetings = len(meeting_items)
        log(f"Found {total_meetings} meetings on page")

        # Limit how many to process
        meetings_to_process = min(total_meetings, args.limit)
        log(f"Will process {meetings_to_process} meetings")

        success_count = 0
        not_ready_count = 0
        error_count = 0

        for i in range(meetings_to_process):
            log(f"\n--- Processing meeting {i+1}/{meetings_to_process} ---")

            # Refresh the list of meeting items (page may have changed)
            meeting_items = page.locator('a.meeting-item[data-test-id="ListItem"]').all()

            if i >= len(meeting_items):
                log(f"Meeting {i+1} no longer on page", "WARN")
                break

            meeting_item = meeting_items[i]

            # Get meeting title for logging
            try:
                title_el = meeting_item.locator('p.label-v2-lg').first
                title = title_el.inner_text()
                log(f"Meeting: {title}")
            except:
                title = f"Meeting {i+1}"
                log(f"Meeting: {title}")

            # Click the meeting
            log("Clicking meeting...")
            meeting_item.click()

            # Wait for navigation
            page.wait_for_load_state("load", timeout=15000)

            # Try to download transcript
            status, transcript_text, meeting_id = download_transcript_from_current_page(page)

            # Skip if already processed
            if cache and meeting_id and cache.is_processed(meeting_id):
                log(f"⊘ Already processed, skipping...", "INFO")
                # Navigate back to list
                log("Navigating back to list...")
                page.goto("https://app.krisp.ai/meeting-notes?page=1&limit=20", wait_until="load", timeout=30000)
                page.wait_for_selector('a.meeting-item', state='visible', timeout=10000)
                page.wait_for_timeout(2000)
                continue

            if status == 'success' and transcript_text:
                # Save transcript
                if meeting_id:
                    transcript_path = TRANSCRIPTS_DIR / f"krisp-transcript-{meeting_id}.txt"
                    # Also save metadata with meeting title
                    metadata = {
                        "meeting_id": meeting_id,
                        "title": title,
                        "downloaded_at": datetime.now().isoformat()
                    }
                    metadata_path = TRANSCRIPTS_DIR / f"krisp-transcript-{meeting_id}.json"
                    metadata_path.write_text(json.dumps(metadata, indent=2))
                else:
                    # No meeting ID but we have transcript - use timestamp
                    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
                    transcript_path = TRANSCRIPTS_DIR / f"krisp-transcript-{timestamp}.txt"

                transcript_path.write_text(transcript_text)
                log(f"✓ Saved transcript to: {transcript_path}")
                log(f"✓ Transcript length: {len(transcript_text)} characters")
                success_count += 1

                # Mark as processed in cache to prevent re-downloading
                if cache and meeting_id:
                    metadata = {
                        "title": title,
                        "downloaded_at": datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                        "transcript_path": str(transcript_path)
                    }
                    if cache.add_processed_meeting(meeting_id, metadata):
                        log(f"✓ Marked meeting as processed in cache")
                    else:
                        log(f"⚠ Failed to update cache for meeting {meeting_id}", "WARN")
            elif status == 'not_ready':
                log(f"⏳ Transcript not ready yet, skipping...", "WARN")
                not_ready_count += 1
            else:  # status == 'error'
                log(f"✗ Failed to download transcript", "ERROR")
                error_count += 1

            # Navigate back to list
            log("Navigating back to list...")
            page.goto("https://app.krisp.ai/meeting-notes?page=1&limit=20", wait_until="load", timeout=30000)
            page.wait_for_selector('a.meeting-item', state='visible', timeout=10000)
            page.wait_for_timeout(2000)  # Extra buffer

            # Wait between downloads
            if i < meetings_to_process - 1:
                log(f"Waiting 3s before next download...")
                time.sleep(3)

        browser.close()

        # Save progress tracking
        progress = {
            "last_run": datetime.now().isoformat(),
            "downloaded": success_count,
            "not_ready": not_ready_count,
            "errors": error_count,
            "total_processed": meetings_to_process,
            "success_rate": round((success_count / meetings_to_process * 100) if meetings_to_process > 0 else 0, 1)
        }
        PROGRESS_FILE.write_text(json.dumps(progress, indent=2))
        log(f"Progress saved to: {PROGRESS_FILE}")

        log(f"\n=== Summary ===")
        log(f"✓ Successfully downloaded: {success_count}/{meetings_to_process}")
        log(f"⏳ Not ready: {not_ready_count}/{meetings_to_process}")
        log(f"✗ Errors: {error_count}/{meetings_to_process}")
        log(f"Success rate: {progress['success_rate']}%")

if __name__ == "__main__":
    main()
