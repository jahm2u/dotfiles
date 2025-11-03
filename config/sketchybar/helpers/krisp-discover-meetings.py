#!/usr/bin/env python3
"""
Krisp Meeting Discovery (Phase 1)
Discovers all available meetings from Krisp and creates a pending download queue.

Author: Jeff Hamersly
Date: 2025-11-02
Story: 4-3 - AI Analysis & Note Integration
Phase: 1 of 2 (Discovery)
"""

import json
import sys
import os
import re
import time
from pathlib import Path
from datetime import datetime
from playwright.sync_api import sync_playwright
from dotenv import load_dotenv

# Configuration
CACHE_DIR = Path.home() / ".cache/sketchybar"
PENDING_QUEUE_FILE = CACHE_DIR / "krisp-pending-downloads.json"
CACHE_FILE = CACHE_DIR / "processed-krisp-meetings.json"
LOG_FILE = Path.home() / ".config/sketchybar/logs/krisp-discovery.log"
AUTH_FILE = Path.home() / ".config/sketchybar/krisp-auth.json"

# Ensure directories exist
CACHE_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)


def log(message, level="INFO"):
    """Log message with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"[{timestamp}] [{level}] {message}"
    print(log_line)
    with open(LOG_FILE, "a") as f:
        f.write(log_line + "\n")


def load_krisp_auth():
    """Load Krisp authentication from JSON file"""
    if not AUTH_FILE.exists():
        log(f"Auth file not found: {AUTH_FILE}", "ERROR")
        raise FileNotFoundError(f"Krisp auth file not found at {AUTH_FILE}")

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


def extract_meeting_id(url):
    """Extract meeting ID from Krisp URL"""
    match = re.search(r'--([a-f0-9]+)$', url)
    return match.group(1) if match else None


def parse_meeting_date(date_text):
    """Parse meeting date from text like 'Aug 20' or 'Oct 31'"""
    try:
        # Assume current year if just "Month Day"
        current_year = datetime.now().year
        date_with_year = f"{date_text} {current_year}"
        parsed = datetime.strptime(date_with_year, "%b %d %Y")
        return parsed.strftime("%Y-%m-%d")
    except:
        return None


def discover_meetings_on_page(page, page_num):
    """
    Discover all meetings on a single Krisp page.
    Returns list of meeting dicts with id, title, url, date.
    """
    url = (
        f"https://app.krisp.ai/meeting-notes"
        f"?dates=&companies=&contains=&owner=&access="
        f"&sort=desc&sortKey=created_at&page={page_num}&limit=20"
        f"&starred=false&type="
    )

    log(f"Fetching page {page_num}...")
    page.goto(url, wait_until="domcontentloaded", timeout=30000)
    page.wait_for_timeout(5000)  # Wait for React to render

    meetings = []

    # Extract meeting links (same selector as download script)
    meeting_links = page.query_selector_all('a.meeting-item[href^="/n/"]')
    log(f"  Found {len(meeting_links)} meetings on page {page_num}")

    for link in meeting_links:
        try:
            meeting_url = link.get_attribute('href')
            meeting_id = extract_meeting_id(meeting_url)

            if not meeting_id:
                continue

            # Extract title
            title_el = link.query_selector('p.label-v2-lg')
            title = title_el.inner_text().strip() if title_el else f"Meeting {meeting_id[:8]}"

            # Extract date
            date_el = link.query_selector('span.list-item-date')
            date_text = date_el.inner_text().strip() if date_el else None
            date = parse_meeting_date(date_text) if date_text else None

            meetings.append({
                'id': meeting_id,
                'title': title,
                'url': meeting_url,
                'date': date,
                'date_text': date_text,
                'discovered_at': datetime.now().isoformat(),
                'page': page_num
            })

        except Exception as e:
            log(f"  Error extracting meeting: {str(e)}", "WARN")
            continue

    return meetings


def discover_all_meetings(max_pages=60, target_date=None):
    """
    Phase 1: Discover all available meetings across multiple pages.

    Args:
        max_pages: Maximum number of pages to scan
        target_date: Stop when we reach this date (YYYY-MM-DD format)

    Returns: List of discovered meetings
    """
    log("=== PHASE 1: MEETING DISCOVERY ===")

    cookies, localstorage = load_krisp_auth()

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=['--disable-blink-features=AutomationControlled']
        )

        context = browser.new_context(
            user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
        )

        # Add cookies
        playwright_cookies = [convert_cookie_format(c) for c in cookies]
        context.add_cookies(playwright_cookies)
        log(f"Loaded {len(playwright_cookies)} cookies")

        page = context.new_page()

        # Set localStorage
        page.goto("https://app.krisp.ai/", wait_until="domcontentloaded")
        for key, value in localstorage.items():
            page.evaluate(f'localStorage.setItem("{key}", "{value}")')

        all_meetings = []
        page_num = 1

        while page_num <= max_pages:
            page_meetings = discover_meetings_on_page(page, page_num)

            if not page_meetings:
                log(f"No meetings found on page {page_num} - stopping discovery")
                break

            all_meetings.extend(page_meetings)
            log(f"  Collected {len(page_meetings)} meetings (total: {len(all_meetings)})")

            # Check if we've reached target date
            if target_date and page_meetings:
                oldest_date = page_meetings[-1].get('date')
                if oldest_date and oldest_date <= target_date:
                    log(f"Reached target date {target_date} on page {page_num}")
                    break

            page_num += 1
            time.sleep(2)  # Rate limiting

        browser.close()

        log(f"✓ Discovery complete: Found {len(all_meetings)} total meetings across {page_num} pages")
        return all_meetings


def filter_pending_meetings(discovered_meetings):
    """
    Filter out meetings that have already been processed.
    Returns list of meetings pending download.
    """
    # Load processed meetings cache
    if CACHE_FILE.exists():
        with open(CACHE_FILE) as f:
            cache = json.load(f)
            processed_ids = {m['meeting_id'] for m in cache.get('processed_meetings', [])}
    else:
        processed_ids = set()

    # Filter out already processed
    pending = [m for m in discovered_meetings if m['id'] not in processed_ids]

    log(f"Filtered: {len(discovered_meetings)} discovered - {len(processed_ids)} processed = {len(pending)} pending")

    return pending


def save_pending_queue(pending_meetings):
    """Save pending meetings to queue file"""
    queue_data = {
        'created_at': datetime.now().isoformat(),
        'total_pending': len(pending_meetings),
        'meetings': pending_meetings
    }

    # Atomic write
    temp_file = PENDING_QUEUE_FILE.with_suffix('.tmp')
    with open(temp_file, 'w') as f:
        json.dump(queue_data, f, indent=2)
    temp_file.replace(PENDING_QUEUE_FILE)

    log(f"✓ Saved {len(pending_meetings)} pending meetings to {PENDING_QUEUE_FILE}")


def main():
    import argparse

    parser = argparse.ArgumentParser(description='Phase 1: Discover Krisp meetings')
    parser.add_argument('--max-pages', type=int, default=60, help='Max pages to scan')
    parser.add_argument('--target-date', help='Stop at this date (YYYY-MM-DD)')
    parser.add_argument('--headless', action='store_true', default=True)
    parser.add_argument('--visible', action='store_true', help='Run browser in visible mode')

    args = parser.parse_args()

    if args.visible:
        args.headless = False

    try:
        # Phase 1: Discover all meetings
        discovered = discover_all_meetings(
            max_pages=args.max_pages,
            target_date=args.target_date
        )

        # Filter out already processed
        pending = filter_pending_meetings(discovered)

        # Save to pending queue
        save_pending_queue(pending)

        # Summary
        print(json.dumps({
            'discovered': len(discovered),
            'pending': len(pending),
            'queue_file': str(PENDING_QUEUE_FILE)
        }, indent=2))

        sys.exit(0)

    except Exception as e:
        log(f"Fatal error: {str(e)}", "ERROR")
        import traceback
        log(traceback.format_exc(), "ERROR")
        sys.exit(1)


if __name__ == '__main__':
    main()
