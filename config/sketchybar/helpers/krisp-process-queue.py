#!/usr/bin/env python3
"""
Krisp Queue Processor (Phase 2)
Processes pending meeting downloads one at a time with progress tracking.

Author: Jeff Hamersly
Date: 2025-11-02
Story: 4-3 - AI Analysis & Note Integration
Phase: 2 of 2 (Download & Process)
"""

import json
import sys
import os
import time
from pathlib import Path
from datetime import datetime
from playwright.sync_api import sync_playwright
from dotenv import load_dotenv

# Configuration
CACHE_DIR = Path.home() / ".cache/sketchybar"
PENDING_QUEUE_FILE = CACHE_DIR / "krisp-pending-downloads.json"
CACHE_FILE = CACHE_DIR / "processed-krisp-meetings.json"
PROGRESS_FILE = CACHE_DIR / "krisp-download-progress.json"
LOG_FILE = Path.home() / ".config/sketchybar/logs/krisp-processing.log"
AUTH_FILE = Path.home() / ".config/sketchybar/krisp-auth.json"
TRANSCRIPTS_DIR = Path.home() / ".config/sketchybar/krisp-transcripts"

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


def load_pending_queue():
    """Load pending meetings queue"""
    if not PENDING_QUEUE_FILE.exists():
        log("No pending queue file found", "WARN")
        return []

    with open(PENDING_QUEUE_FILE) as f:
        data = json.load(f)

    return data.get('meetings', [])


def load_progress():
    """Load download progress"""
    if PROGRESS_FILE.exists():
        with open(PROGRESS_FILE) as f:
            return json.load(f)
    return {
        'started_at': datetime.now().isoformat(),
        'completed_ids': [],
        'failed_ids': [],
        'last_processed': None
    }


def save_progress(progress):
    """Save download progress (atomic write)"""
    temp_file = PROGRESS_FILE.with_suffix('.tmp')
    with open(temp_file, 'w') as f:
        json.dump(progress, f, indent=2)
    temp_file.replace(PROGRESS_FILE)


def load_krisp_auth():
    """Load Krisp authentication"""
    if not AUTH_FILE.exists():
        raise FileNotFoundError(f"Auth file not found: {AUTH_FILE}")

    with open(AUTH_FILE) as f:
        auth_data = json.load(f)

    return auth_data.get('cookies', []), auth_data.get('localStorage', {})


def convert_cookie_format(cookie):
    """Convert browser cookie format to Playwright format"""
    pw_cookie = {
        'name': cookie['name'],
        'value': cookie['value'],
        'domain': cookie['domain'],
        'path': cookie['path'],
    }

    if 'expirationDate' in cookie and cookie['expirationDate']:
        pw_cookie['expires'] = int(cookie['expirationDate'])
    if 'httpOnly' in cookie:
        pw_cookie['httpOnly'] = cookie['httpOnly']
    if 'secure' in cookie:
        pw_cookie['secure'] = cookie['secure']
    if 'sameSite' in cookie and cookie['sameSite'] != 'unspecified':
        same_site_map = {
            'no_restriction': 'None',
            'lax': 'Lax',
            'strict': 'Strict'
        }
        pw_cookie['sameSite'] = same_site_map.get(cookie['sameSite'], 'Lax')

    return pw_cookie


def download_transcript(page, meeting):
    """
    Download transcript for a single meeting using clipboard copy method.
    Returns transcript path on success, None on failure.
    """
    meeting_id = meeting['id']
    meeting_url = meeting['url']
    meeting_title = meeting['title']

    log(f"Downloading: {meeting_title} (ID: {meeting_id[:8]}...)")

    try:
        # Navigate to meeting detail page
        full_url = f"https://app.krisp.ai{meeting_url}"
        page.goto(full_url, wait_until="domcontentloaded", timeout=30000)
        page.wait_for_timeout(3000)

        # Click 3-dot menu
        menu_button = page.locator('button[data-test-id="Dropdown"]').first
        if not menu_button.is_visible(timeout=5000):
            log("  3-dot menu not visible", "ERROR")
            return None

        menu_button.click()
        page.wait_for_timeout(2000)

        # Click "Copy transcript" button
        copy_button = page.locator('button:has-text("Copy transcript")').first
        if not copy_button.is_visible(timeout=5000):
            log("  Copy transcript button not visible", "ERROR")
            return None

        copy_button.click()
        page.wait_for_timeout(1000)

        # Read from clipboard
        transcript_text = page.evaluate("""
            async () => {
                try {
                    return await navigator.clipboard.readText();
                } catch (err) {
                    return null;
                }
            }
        """)

        if not transcript_text:
            log("  Failed to read clipboard", "ERROR")
            return None

        # Save transcript
        transcript_path = TRANSCRIPTS_DIR / f"krisp-transcript-{meeting_id}.txt"
        transcript_path.write_text(transcript_text)

        log(f"  ✓ Saved ({len(transcript_text)} chars)")
        return str(transcript_path)

    except Exception as e:
        log(f"  Error: {str(e)}", "ERROR")
        return None


def mark_meeting_processed(meeting_id, metadata):
    """Mark meeting as successfully processed in cache"""
    if CACHE_FILE.exists():
        with open(CACHE_FILE) as f:
            cache = json.load(f)
    else:
        cache = {
            'last_check': datetime.now().isoformat(),
            'processed_meetings': [],
            'failed_downloads': []
        }

    cache['processed_meetings'].append({
        'meeting_id': meeting_id,
        'processed_at': datetime.now().isoformat(),
        **metadata
    })

    cache['last_check'] = datetime.now().isoformat()

    # Atomic write
    temp_file = CACHE_FILE.with_suffix('.tmp')
    with open(temp_file, 'w') as f:
        json.dump(cache, f, indent=2)
    temp_file.replace(CACHE_FILE)


def process_queue(limit=None, start_from=0):
    """
    Phase 2: Process pending download queue one meeting at a time.

    Args:
        limit: Max meetings to process (None = all)
        start_from: Skip first N meetings

    Returns: Dict with statistics
    """
    log("=== PHASE 2: PROCESSING QUEUE ===")

    # Load queue and progress
    pending = load_pending_queue()
    progress = load_progress()

    if not pending:
        log("No pending meetings to process")
        return {'processed': 0, 'failed': 0, 'skipped': 0}

    # Filter out already processed from this session
    completed_ids = set(progress['completed_ids'])
    failed_ids = set(progress['failed_ids'])
    to_process = [m for m in pending if m['id'] not in completed_ids and m['id'] not in failed_ids]

    # Apply start_from and limit
    to_process = to_process[start_from:]
    if limit:
        to_process = to_process[:limit]

    total = len(to_process)
    log(f"Queue: {total} meetings to process")

    if total == 0:
        return {'processed': 0, 'failed': 0, 'skipped': len(pending)}

    # Setup browser
    cookies, localstorage = load_krisp_auth()

    stats = {'processed': 0, 'failed': 0, 'skipped': start_from}

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
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
        page.set_default_timeout(30000)  # 30 second timeout

        # Quick session establishment - navigate to meeting-notes page once
        log("Establishing session...")
        page.goto("https://app.krisp.ai/meeting-notes", wait_until="domcontentloaded", timeout=30000)
        page.wait_for_timeout(2000)  # Wait for session to establish

        # Process each meeting
        for idx, meeting in enumerate(to_process, 1):
            meeting_id = meeting['id']

            log(f"\n[{idx}/{total}] Processing: {meeting['title']}")

            transcript_path = download_transcript(page, meeting)

            if transcript_path:
                # Success
                mark_meeting_processed(meeting_id, {
                    'title': meeting['title'],
                    'transcript_path': transcript_path,
                    'date': meeting.get('date'),
                })

                progress['completed_ids'].append(meeting_id)
                progress['last_processed'] = meeting_id
                stats['processed'] += 1

                log(f"  ✓ Success ({stats['processed']}/{total})")

            else:
                # Failure
                progress['failed_ids'].append(meeting_id)
                stats['failed'] += 1

                log(f"  ✗ Failed ({stats['failed']}/{total})")

            # Save progress after each meeting
            save_progress(progress)

            # Rate limiting (2-4 seconds between meetings)
            if idx < total:
                delay = 2 + (hash(meeting_id) % 3)
                log(f"  Waiting {delay}s...")
                time.sleep(delay)

        browser.close()

    log(f"\n=== PROCESSING COMPLETE ===")
    log(f"Processed: {stats['processed']}")
    log(f"Failed: {stats['failed']}")
    log(f"Skipped: {stats['skipped']}")

    return stats


def main():
    import argparse

    parser = argparse.ArgumentParser(description='Phase 2: Process download queue')
    parser.add_argument('--limit', type=int, help='Max meetings to process')
    parser.add_argument('--start-from', type=int, default=0, help='Skip first N meetings')
    parser.add_argument('--reset-progress', action='store_true', help='Clear progress and start fresh')

    args = parser.parse_args()

    try:
        if args.reset_progress and PROGRESS_FILE.exists():
            PROGRESS_FILE.unlink()
            log("Progress file cleared")

        stats = process_queue(
            limit=args.limit,
            start_from=args.start_from
        )

        print(json.dumps(stats, indent=2))
        sys.exit(0)

    except Exception as e:
        log(f"Fatal error: {str(e)}", "ERROR")
        import traceback
        log(traceback.format_exc(), "ERROR")
        sys.exit(1)


if __name__ == '__main__':
    main()
