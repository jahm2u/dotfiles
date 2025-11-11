#!/usr/bin/env python3
"""
Krisp Transcript Download Automation
Downloads meeting transcripts from Krisp.ai using Playwright browser automation.
Uses embedded localStorage + cookies for authentication with exact UI selectors.

Author: Jeff Hamersly
Date: 2025-11-02
Story: 4-2 - Browser Automation & Transcript Download
Updated: 2025-11-02 with exact selectors from interactive discovery
"""

import json
import sys
import os
import re
import time
import random
import hashlib
from pathlib import Path
from datetime import datetime, timedelta
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout
from playwright_stealth import stealth_sync
from dotenv import load_dotenv
import argparse

# Configuration
CACHE_DIR = Path.home() / ".cache/sketchybar"
CACHE_FILE = CACHE_DIR / "krisp-downloaded-transcripts.json"
LOG_FILE = Path.home() / ".config/sketchybar/logs/krisp-download.log"
TRANSCRIPTS_DIR = Path.home() / ".config/sketchybar/krisp-transcripts"
UNMATCHED_DIR = TRANSCRIPTS_DIR / "unmatched"
AUTH_FILE = Path.home() / ".config/sketchybar/krisp-auth.json"

# Ensure directories exist
CACHE_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
TRANSCRIPTS_DIR.mkdir(parents=True, exist_ok=True)
UNMATCHED_DIR.mkdir(parents=True, exist_ok=True)


def log(message, level="INFO"):
    """Log message with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"[{timestamp}] [{level}] {message}"
    print(log_line)
    with open(LOG_FILE, "a") as f:
        f.write(log_line + "\n")


def load_env():
    """Load environment variables from multiple possible locations (AC #8)"""
    env_paths = [
        Path.home() / "repos/02_personal/dotfiles/.env",
        Path.home() / "dotfiles/.env",
        Path(__file__).parent.parent / ".env",
        Path.home() / ".env",
    ]

    for env_path in env_paths:
        if env_path.exists():
            load_dotenv(env_path)
            log(f"Loaded .env from: {env_path}")
            return True

    log("No .env file found in standard locations", "WARN")
    return False


def send_telegram_alert(message: str):
    """
    Send Telegram alert on critical errors (AC #8).
    Used for authentication failures and other critical issues.
    """
    bot_token = os.getenv("TELEGRAM_BOT_TOKEN")
    chat_id = os.getenv("TELEGRAM_CHAT_ID")

    if not bot_token or not chat_id:
        log("Telegram credentials not configured - skipping alert", "WARN")
        return False

    try:
        import requests
        url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
        payload = {
            "chat_id": chat_id,
            "text": message,
            "parse_mode": "HTML"
        }
        response = requests.post(url, json=payload, timeout=10)

        if response.status_code == 200:
            log("✓ Telegram alert sent successfully")
            return True
        else:
            log(f"Telegram alert failed: HTTP {response.status_code}", "ERROR")
            return False
    except Exception as e:
        log(f"Failed to send Telegram alert: {str(e)}", "ERROR")
        return False


def send_telegram_notification(meeting_title, meeting_timestamp, transcript_path, transcript_length):
    """
    Send Telegram notification for each successfully processed meeting.
    Includes meeting details and transcript info.
    """
    bot_token = os.getenv("TELEGRAM_BOT_TOKEN")
    chat_id = os.getenv("TELEGRAM_CHAT_ID")

    if not bot_token or not chat_id:
        log("Telegram credentials not configured - skipping notification", "WARN")
        return False

    # Format timestamp nicely
    try:
        if meeting_timestamp:
            dt = datetime.fromisoformat(meeting_timestamp)
            time_str = dt.strftime("%b %d, %I:%M %p")
        else:
            time_str = "Unknown time"
    except:
        time_str = meeting_timestamp or "Unknown time"

    # Format file size
    file_path = Path(transcript_path)
    if file_path.exists():
        file_size_kb = file_path.stat().st_size / 1024
        size_str = f"{file_size_kb:.1f} KB"
    else:
        size_str = "Unknown size"

    message = (
        "📝 <b>Krisp Transcript Downloaded</b>\n\n"
        f"<b>Meeting:</b> {meeting_title}\n"
        f"<b>Time:</b> {time_str}\n"
        f"<b>Transcript:</b> {transcript_length:,} characters ({size_str})\n"
        f"<b>Saved:</b> <code>{file_path.name}</code>\n\n"
        "✅ Ready for AI analysis (Story 4-3)"
    )

    try:
        import requests
        url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
        payload = {
            "chat_id": chat_id,
            "text": message,
            "parse_mode": "HTML"
        }
        response = requests.post(url, json=payload, timeout=10)

        if response.status_code == 200:
            log("✓ Telegram notification sent successfully")
            return True
        else:
            log(f"Telegram notification failed: HTTP {response.status_code}", "ERROR")
            return False
    except Exception as e:
        log(f"Failed to send Telegram notification: {str(e)}", "ERROR")
        return False


def load_krisp_auth():
    """
    Load Krisp authentication from JSON file.
    Returns tuple of (cookies, localStorage).

    If auth file is missing, provides helpful error message.
    """
    if not AUTH_FILE.exists():
        log(f"Auth file not found: {AUTH_FILE}", "ERROR")
        log("Run this command to set up authentication:", "ERROR")
        log(f"  bash ~/.config/sketchybar/helpers/krisp-refresh-auth.sh", "ERROR")
        raise FileNotFoundError(
            f"Krisp auth file not found at {AUTH_FILE}\n"
            f"Run: bash ~/.config/sketchybar/helpers/krisp-refresh-auth.sh"
        )

    try:
        with open(AUTH_FILE) as f:
            auth_data = json.load(f)

        cookies = auth_data.get('cookies', [])
        localstorage = auth_data.get('localStorage', {})

        if not cookies:
            raise ValueError("No cookies found in auth file")
        if not localstorage:
            raise ValueError("No localStorage found in auth file")

        # Log auth file age for debugging
        updated_at = auth_data.get('updated_at', 'unknown')
        log(f"Loaded auth from file (updated: {updated_at})")

        return cookies, localstorage

    except json.JSONDecodeError as e:
        log(f"Invalid JSON in auth file: {str(e)}", "ERROR")
        raise ValueError(f"Auth file contains invalid JSON: {str(e)}")
    except Exception as e:
        log(f"Error loading auth file: {str(e)}", "ERROR")
        raise


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
    """
    Extract meeting ID from Krisp URL.

    Example: /t/02-58-PM---Slack-meeting-October-29--019a311fc6b372adb39e3e0a053ee5cc
    Returns: 019a311fc6b372adb39e3e0a053ee5cc
    """
    match = re.search(r'--([a-f0-9]+)$', url)
    return match.group(1) if match else None


def parse_title_timestamp(title):
    """
    Parse timestamp from Krisp meeting title (AC #3).

    Example: "08:25 PM - Signal meeting October 31"
    Returns: datetime object or None if parsing fails
    """
    try:
        # Pattern: HH:MM AM/PM - ... Month Day
        match = re.match(r'(\d{1,2}):(\d{2})\s+(AM|PM)\s+-\s+.*?\s+([A-Za-z]+)\s+(\d{1,2})$', title, re.IGNORECASE)

        if not match:
            log(f"Could not parse timestamp from title: {title}", "WARN")
            return None

        hour, minute, period, month_name, day = match.groups()

        # Convert to 24-hour format
        hour_int = int(hour)
        if period.upper() == 'PM' and hour_int != 12:
            hour_int += 12
        elif period.upper() == 'AM' and hour_int == 12:
            hour_int = 0

        # Parse month name
        months = {
            'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5, 'june': 6,
            'july': 7, 'august': 8, 'september': 9, 'october': 10, 'november': 11, 'december': 12
        }
        month = months.get(month_name.lower())
        if not month:
            log(f"Could not parse month: {month_name}", "WARN")
            return None

        # Construct datetime (use current year, adjust if needed)
        now = datetime.now()
        year = now.year
        day_int = int(day)

        meeting_dt = datetime(year, month, day_int, hour_int, int(minute))

        # If meeting appears to be in the future, it's probably from last year
        if meeting_dt > now + timedelta(days=1):
            meeting_dt = datetime(year - 1, month, day_int, hour_int, int(minute))

        return meeting_dt

    except Exception as e:
        log(f"Error parsing title timestamp: {str(e)}", "ERROR")
        return None


def parse_krisp_filename(filename):
    """
    Parse Krisp transcript filename to extract metadata.

    Example: 02_58_pm_-_slack_meeting_october_29_transcript.txt
    Returns: {
        'hour': '02',
        'minute': '58',
        'period': 'pm',
        'source': 'slack',
        'month': 'october',
        'day': 29,
        'time_24h': '14:58'
    }
    """
    # Pattern: {HH}_{MM}_{am/pm}_-_{source}_meeting_{month}_{day}_transcript.txt
    pattern = r'(\d{2})_(\d{2})_([ap]m)_-_([a-z]+)_meeting_([a-z]+)_(\d{1,2})_transcript\.txt'
    match = re.match(pattern, filename)

    if not match:
        log(f"Failed to parse filename: {filename}", "WARN")
        return None

    hour, minute, period, source, month, day = match.groups()

    # Convert to 24-hour format
    hour_int = int(hour)
    if period == 'pm' and hour_int != 12:
        hour_int += 12
    elif period == 'am' and hour_int == 12:
        hour_int = 0

    time_24h = f"{hour_int:02d}:{minute}"

    return {
        'hour': hour,
        'minute': minute,
        'period': period,
        'source': source,
        'month': month,
        'day': int(day),
        'time_24h': time_24h
    }


def test_krisp_auth():
    """
    Test Krisp authentication with localStorage + cookies.
    Returns True if authenticated, False otherwise.
    Sends Telegram alert on auth failure (AC #8).
    """
    log("Testing Krisp authentication...")

    try:
        cookies, localstorage = load_krisp_auth()
    except Exception as e:
        log(f"Failed to load auth: {str(e)}", "ERROR")

        # AC #8: Send Telegram alert on auth file missing
        alert_msg = (
            "🚨 <b>Krisp Auth Failed</b>\n\n"
            "Auth file missing or invalid.\n\n"
            f"<b>File:</b> <code>{AUTH_FILE}</code>\n"
            "<b>Action:</b> Run krisp-refresh-auth.sh to update\n"
            "<b>Retry:</b> Script runs hourly via LaunchAgent"
        )
        send_telegram_alert(alert_msg)
        return False

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=['--disable-blink-features=AutomationControlled']
        )

        context = browser.new_context(
            user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'
        )

        # Add cookies
        playwright_cookies = [convert_cookie_format(c) for c in cookies]
        context.add_cookies(playwright_cookies)
        log(f"Loaded {len(playwright_cookies)} cookies")

        page = context.new_page()
        # NOTE: playwright-stealth is breaking Krisp's React app with JS errors
        # Disabling for now - we already have anti-detection via user-agent and flags
        # stealth_sync(page)  # AC #1: Apply playwright-stealth anti-detection

        # Navigate to domain to set localStorage origin
        log("Navigating to Krisp domain to set localStorage...")
        page.goto("https://app.krisp.ai/", wait_until="domcontentloaded", timeout=30000)

        # Inject localStorage
        log("Injecting localStorage items...")
        for key, value in localstorage.items():
            page.evaluate(f'localStorage.setItem("{key}", "{value}")')

        # Navigate to meeting-notes page
        log("Navigating to meeting-notes page...")
        response = page.goto("https://app.krisp.ai/meeting-notes", wait_until="domcontentloaded", timeout=30000)

        # Wait for page to stabilize
        page.wait_for_timeout(3000)

        # Check authentication status
        page_url = page.url
        page_title = page.title()

        log(f"Page URL: {page_url}")
        log(f"Page title: {page_title}")

        browser.close()

        # Success criteria: not redirected to login
        if "login" in page_url.lower() or "sign" in page_url.lower():
            log("Authentication failed - redirected to login page", "ERROR")

            # AC #8: Send Telegram alert on expired cookies
            alert_msg = (
                "🚨 <b>Krisp Auth Failed</b>\n\n"
                "Cookies expired. Update manually.\n\n"
                f"<b>File:</b> <code>{AUTH_FILE}</code>\n"
                "<b>Action:</b> Run krisp-refresh-auth.sh to update\n"
                "<b>Retry:</b> Script runs hourly via LaunchAgent"
            )
            send_telegram_alert(alert_msg)
            return False

        if "meeting" in page_title.lower() or "meeting" in page_url.lower():
            log("✓ Authentication successful")
            return True

        log(f"Unexpected page state - title: {page_title}", "WARN")
        return False


def scrape_krisp_meetings(limit=5, headless=True, days_back=1):
    """
    Scrape meeting list from Krisp dashboard using exact selectors.
    Automatically paginates through pages to reach the target date range.

    Uses discovered selectors:
    - Meeting links: a.meeting-item[href^="/t/"]
    - Title: p.label-v2-lg

    Args:
        limit: Max meetings to return
        headless: Run browser in headless mode
        days_back: How many days back to search (default 1 = 24 hours)
    """
    log(f"Scraping Krisp meetings (limit: {limit}, days_back: {days_back})...")

    cookies, localstorage = load_krisp_auth()

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=headless,
            args=['--disable-blink-features=AutomationControlled']
        )

        context = browser.new_context(
            user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
        )

        # Add cookies
        playwright_cookies = [convert_cookie_format(c) for c in cookies]
        log(f"DEBUG: Converting {len(cookies)} cookies to Playwright format")
        log(f"DEBUG: Sample cookie names: {[c['name'] for c in cookies[:3]]}")
        context.add_cookies(playwright_cookies)
        log(f"DEBUG: Added {len(playwright_cookies)} cookies to context")

        page = context.new_page()
        # NOTE: playwright-stealth is breaking Krisp's React app with JS errors
        # Disabling for now - we already have anti-detection via user-agent and flags
        # stealth_sync(page)  # AC #1: Apply playwright-stealth anti-detection

        # Set localStorage
        page.goto("https://app.krisp.ai/", wait_until="domcontentloaded")
        log(f"DEBUG: Setting {len(localstorage)} localStorage items")
        log(f"DEBUG: localStorage keys: {list(localstorage.keys())}")
        for key, value in localstorage.items():
            # Escape quotes in values for JavaScript eval
            escaped_value = value.replace('"', '\\"').replace("'", "\\'")
            page.evaluate(f'localStorage.setItem("{key}", "{escaped_value}")')
            log(f"DEBUG: Set localStorage['{key}'] = {value[:50]}..." if len(value) > 50 else f"DEBUG: Set localStorage['{key}'] = {value}")

        # Verify cookies and localStorage were set
        page_cookies = page.context.cookies()
        log(f"DEBUG: Page context has {len(page_cookies)} cookies after setting")

        # Check localStorage
        ls_count = page.evaluate("Object.keys(localStorage).length")
        log(f"DEBUG: Page localStorage has {ls_count} items after setting")

        # IMPORTANT: Reload the page so React picks up the localStorage
        log(f"DEBUG: Reloading page to initialize React with localStorage...")
        page.reload(wait_until="load")
        page.wait_for_timeout(3000)

        # Calculate cutoff time based on days_back parameter
        cutoff_time = datetime.now() - timedelta(days=days_back)
        log(f"Filtering meetings newer than: {cutoff_time.isoformat()} ({days_back} days back)")

        meetings = []
        current_page = 1
        max_pages = 20  # Safety limit to avoid infinite loops

        while len(meetings) < limit and current_page <= max_pages:
            # Navigate to meeting-notes page with current page number
            log(f"Scraping page {current_page}...")

            # Try simpler URL first, then add query params via JavaScript
            if current_page == 1:
                # Navigate to base URL first to let React initialize
                log(f"DEBUG: First loading base meeting-notes URL...")
                page.goto("https://app.krisp.ai/meeting-notes", wait_until="load", timeout=60000)
                page.wait_for_timeout(3000)

            # Now navigate with query params
            target_url = f"https://app.krisp.ai/meeting-notes?dates=&companies=&contains=&owner=&access=&sort=desc&sortKey=created_at&page={current_page}&limit=20&starred=false&type="
            log(f"DEBUG: Navigating to: {target_url}")

            response = page.goto(
                target_url,
                wait_until="load",
                timeout=60000
            )

            log(f"DEBUG: Response status: {response.status if response else 'None'}")
            log(f"DEBUG: Final URL after navigation: {page.url}")
            log(f"DEBUG: Page title: {page.title()}")

            # Wait for React to render - give it more time
            log(f"  Waiting for page to fully render...")
            page.wait_for_timeout(5000)  # 5 seconds for React to render

            # Try to wait for the main content area or any common element
            try:
                page.wait_for_selector('body', state='visible', timeout=5000)
                log(f"  Page body is visible")
            except Exception as e:
                log(f"  Warning: Timeout waiting for page elements: {str(e)}", "WARN")

            # Debug: Check what HTML we're actually getting
            if current_page == 1:
                html_content = page.content()
                log(f"DEBUG: Page HTML length: {len(html_content)} characters")
                log(f"DEBUG: First 500 chars of HTML: {html_content[:500]}")

                # Check if it's actually a React app that failed to load
                if '<div id="root"></div>' in html_content or '<div id="app"></div>' in html_content:
                    log("DEBUG: React root div found but appears empty - React app not loading!", "ERROR")

                # Check for any script errors in console
                console_logs = []
                page.on('console', lambda msg: console_logs.append(f"{msg.type}: {msg.text}"))
                page.wait_for_timeout(2000)
                if console_logs:
                    log(f"DEBUG: Console messages: {console_logs}")

            # Debug: Take screenshot and wait longer if not headless
            if not headless:
                screenshot_path = f"/tmp/krisp-page-{current_page}.png"
                page.screenshot(path=screenshot_path)
                log(f"  Screenshot saved to: {screenshot_path}")
                log(f"  Waiting 10 seconds for you to inspect the page...")
                page.wait_for_timeout(10000)

            # Query selector: a.meeting-item - match both /t/ and /n/ URL formats
            meeting_links = page.query_selector_all('a.meeting-item[data-test-id="ListItem"]')
            log(f"  Found {len(meeting_links)} meeting links on page {current_page}")

            # Debug: Log page HTML if no links found
            if len(meeting_links) == 0 and current_page == 1:
                log(f"  No links found. Current URL: {page.url}")
                # Check if we're redirected to login
                if "login" in page.url.lower() or "sign" in page.url.lower():
                    log("  ERROR: Redirected to login page - auth may have expired", "ERROR")
                    break

            if len(meeting_links) == 0:
                log(f"  No more meetings found on page {current_page}, stopping pagination")
                break

            page_has_old_meetings = False
            oldest_on_page = None

            for link in meeting_links:
                try:
                    # Extract meeting URL
                    meeting_url = link.get_attribute('href')

                    # Extract meeting ID from URL
                    meeting_id = extract_meeting_id(meeting_url)
                    if not meeting_id:
                        continue

                    # Extract title
                    title_el = link.query_selector('p.label-v2-lg')
                    title = title_el.inner_text().strip() if title_el else f"Meeting {meeting_id[:8]}"

                    # Note: We check transcript readiness at download time via button state
                    # This is more reliable than trying to detect icons on the list page

                    # Extract timestamp from title
                    meeting_timestamp = parse_title_timestamp(title)

                    # Track oldest meeting on this page
                    if meeting_timestamp:
                        if oldest_on_page is None or meeting_timestamp < oldest_on_page:
                            oldest_on_page = meeting_timestamp

                    # Filter by cutoff time
                    if meeting_timestamp and meeting_timestamp < cutoff_time:
                        log(f"  Skipping old meeting: {title} ({meeting_timestamp.isoformat()})", "DEBUG")
                        page_has_old_meetings = True
                        continue

                    # If we couldn't parse timestamp, include with warning
                    if not meeting_timestamp:
                        log(f"  Including meeting with unknown timestamp: {title}", "WARN")

                    meetings.append({
                        'id': meeting_id,
                        'title': title,
                        'url': meeting_url,
                        'timestamp': meeting_timestamp.isoformat() if meeting_timestamp else None
                    })

                    log(f"  Found: {title} (ID: {meeting_id[:8]}..., URL: {meeting_url}, Time: {meeting_timestamp})")

                    # Stop if we've hit the limit
                    if len(meetings) >= limit:
                        break

                except Exception as e:
                    log(f"Error extracting meeting data: {str(e)}", "ERROR")
                    continue

            # Log page summary
            if oldest_on_page:
                log(f"  Oldest meeting on page {current_page}: {oldest_on_page.isoformat()}")

            # Stop pagination if we've hit the limit
            if len(meetings) >= limit:
                log(f"  Reached limit of {limit} meetings, stopping pagination")
                break

            # Stop pagination if all meetings on this page are too old
            if page_has_old_meetings and oldest_on_page and oldest_on_page < cutoff_time:
                log(f"  All meetings on page {current_page} are older than cutoff, stopping pagination")
                break

            # Only scan page 1 (20 meetings is sufficient for hourly runs)
            if current_page >= 1:
                log(f"  Processed page 1, stopping pagination (20 meetings is sufficient)")
                break

            # Move to next page
            current_page += 1

        browser.close()

        log(f"Successfully extracted {len(meetings)} meetings across {current_page} pages")
        return meetings


def download_transcript(page, meeting_id, meeting_url, download_dir=None):
    """
    Download transcript by clicking row on list page, then checking for transcript button.
    Uses browser back navigation to return to list for next meeting.

    Steps:
    1. Find row on list page by meeting ID
    2. Click row to open meeting detail
    3. Click 3-dot menu: button[data-test-id="Dropdown"]
    4. Look for "Copy transcript" button
    5. If not found: mark as not ready
    6. If found: click, read clipboard, save
    7. Press browser back to return to list

    Args:
        page: Playwright page object (should be on list page)
        meeting_id: Krisp meeting ID
        meeting_url: Not used (kept for compatibility)
        download_dir: Directory to save transcript (default: TRANSCRIPTS_DIR)

    Returns:
        Tuple of (status, path):
        - ("success", path): Transcript downloaded successfully
        - ("not_ready", None): Transcript button not found (Krisp still processing)
        - ("error", None): Other error occurred
    """
    if download_dir is None:
        download_dir = TRANSCRIPTS_DIR

    log(f"Downloading transcript for meeting: {meeting_id}")

    # Exponential backoff retry logic (up to 3 attempts)
    max_retries = 3
    for attempt in range(max_retries):
        if attempt > 0:
            backoff_delay = 2 ** (attempt - 1)  # 0s, 2s, 4s
            log(f"Retry attempt {attempt + 1}/{max_retries} after {backoff_delay}s delay...")
            time.sleep(backoff_delay)

        try:
            # Ensure we're on the list page (in case previous download took us to detail page)
            current_url = page.url
            if '/meeting-notes' not in current_url:
                log("Navigating back to meeting list page...")
                page.goto("https://app.krisp.ai/meeting-notes?page=1&limit=20", wait_until="load", timeout=30000)
                page.wait_for_selector('a.meeting-item', state='visible', timeout=10000)
                log("Back on list page")

            # Step 1: Find and click the meeting link on the list page
            log(f"Looking for meeting link with ID: {meeting_id}")

            # Debug: Check what's on the page
            all_meeting_links = page.locator('a.meeting-item').all()
            log(f"DEBUG: Found {len(all_meeting_links)} meeting-item links on list page")
            if len(all_meeting_links) > 0:
                first_href = all_meeting_links[0].get_attribute('href')
                log(f"DEBUG: First meeting-item href: {first_href}")

            # Find the meeting link by ID in href
            meeting_link = page.locator(f'a.meeting-item[href*="{meeting_id}"]').first

            try:
                meeting_link.wait_for(state="visible", timeout=10000)
                log("Found meeting link, clicking to open...")
                meeting_link.click()
                # Wait for navigation to complete
                page.wait_for_load_state("load", timeout=15000)
                log("Meeting detail page loaded")
            except PlaywrightTimeout:
                if attempt < max_retries - 1:
                    log(f"Meeting link not found on attempt {attempt + 1} - will retry", "WARN")
                    continue
                else:
                    log("Meeting row not found on list page after all retries", "WARN")
                    return ("not_ready", None)

            # Step 2: Look for 3-dot menu button
            log("Looking for 3-dot menu button...")
            menu_button = page.locator('button[data-test-id="Dropdown"]').first

            # Strategy 1: Wait for button to be attached to DOM (more reliable than visible)
            try:
                menu_button.wait_for(state="attached", timeout=5000)
                log("Menu button found in DOM")
            except PlaywrightTimeout:
                if attempt < max_retries - 1:
                    log(f"Menu button not attached to DOM on attempt {attempt + 1} - will retry", "WARN")
                    continue
                else:
                    log("Menu button not found in DOM after all retries", "WARN")
                    return ("not_ready", None)

            # Strategy 2: Scroll to button to ensure it's in viewport
            try:
                menu_button.scroll_into_view_if_needed(timeout=3000)
                log("Scrolled menu button into view")
            except Exception as e:
                log(f"Scroll to button failed (may not be needed): {str(e)}", "DEBUG")

            # Strategy 3: Wait for button to be visible and enabled
            try:
                menu_button.wait_for(state="visible", timeout=8000)
                log("Menu button is visible")

                # Ensure button is not disabled before clicking
                is_disabled = menu_button.is_disabled()
                if is_disabled:
                    if attempt < max_retries - 1:
                        log(f"Menu button is disabled on attempt {attempt + 1} - will retry", "WARN")
                        continue
                    else:
                        log("Menu button is disabled after all retries", "WARN")
                        return ("not_ready", None)

                log("Clicking 3-dot menu...")
                menu_button.click()
                page.wait_for_timeout(2000)  # Wait for menu to appear

            except PlaywrightTimeout:
                if attempt < max_retries - 1:
                    log(f"Menu button not visible/clickable on attempt {attempt + 1} - will retry", "WARN")
                    continue
                else:
                    log("Menu button not visible after all retries", "WARN")
                    return ("not_ready", None)

            # Step 2: Check if "Copy transcript" button exists in the menu
            log("Looking for Copy transcript button...")
            copy_button = page.locator('button[data-test-id="CopyTranscriptBtn"]').first

            try:
                copy_button.wait_for(state="visible", timeout=3000)
            except PlaywrightTimeout:
                if attempt < max_retries - 1:
                    log(f"Copy transcript button not found on attempt {attempt + 1} - will retry", "WARN")
                    continue
                else:
                    log("Copy transcript button not in menu - transcript not available", "WARN")
                    # Go back to list page before returning
                    page.go_back()
                    page.wait_for_timeout(1000)
                    return ("not_ready", None)

            # Check if button is enabled (not disabled)
            is_disabled = page.locator('button[data-test-id="CopyTranscriptBtn"][disabled]').count() > 0
            if is_disabled:
                if attempt < max_retries - 1:
                    log(f"Copy transcript button is disabled on attempt {attempt + 1} - will retry", "WARN")
                    continue
                else:
                    log("Copy transcript button is disabled - transcript still processing", "WARN")
                    # Go back to list page before returning
                    page.go_back()
                    page.wait_for_timeout(1000)
                    return ("not_ready", None)

            log("Clicking Copy transcript button...")
            copy_button.click()
            page.wait_for_timeout(1000)  # Wait for clipboard to be populated

            # Read from clipboard using JavaScript
            log("Reading transcript from clipboard...")
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
                if attempt < max_retries - 1:
                    log(f"Failed to read clipboard on attempt {attempt + 1} - will retry", "ERROR")
                    continue
                else:
                    log("Failed to read clipboard after all retries", "ERROR")
                    return ("error", None)

            # Count speakers for logging (but don't skip - we'll filter during processing)
            speaker_pattern = r'^([^|]+) \| \d+:\d+$'
            all_speakers = set()
            generic_speakers = set()  # "Speaker 1", "Speaker 2", etc

            for line in transcript_text.split('\n'):
                match = re.match(speaker_pattern, line.strip())
                if match:
                    speaker_name = match.group(1).strip()
                    all_speakers.add(speaker_name)
                    # Track generic speaker labels (these indicate multiple people)
                    if re.match(r'^(Speaker \d+|Unknown)$', speaker_name, re.IGNORECASE):
                        generic_speakers.add(speaker_name)

            speaker_summary = f"{len(all_speakers)} speakers"
            if generic_speakers:
                speaker_summary += f" ({len(generic_speakers)} unidentified)"
            log(f"✓ Transcript has {speaker_summary}: {', '.join(list(all_speakers)[:4])}{'...' if len(all_speakers) > 4 else ''}")

            # Save transcript to configured directory
            transcript_path = Path(download_dir) / f"krisp-transcript-{meeting_id}.txt"
            transcript_path.write_text(transcript_text)

            log(f"✓ Saved transcript to: {transcript_path}")
            log(f"✓ Transcript length: {len(transcript_text)} characters")

            # Success! Go back to list page for next meeting
            log("Going back to list page...")
            page.go_back()
            page.wait_for_timeout(2000)  # Wait for list page to load

            return ("success", str(transcript_path))

        except PlaywrightTimeout as e:
            if attempt < max_retries - 1:
                log(f"Timeout on attempt {attempt + 1} - will retry: {str(e)}", "WARN")
                continue
            else:
                log(f"Timeout after all retries: {str(e)}", "ERROR")
                return ("error", None)
        except Exception as e:
            log(f"Unexpected error downloading transcript: {str(e)}", "ERROR")
            return ("error", None)

    # Should never reach here (all paths return in the loop)
    log("Unexpected: exited retry loop without returning", "ERROR")
    return ("error", None)


def load_cache():
    """Load processed meetings cache with pending transcripts"""
    if CACHE_FILE.exists():
        with open(CACHE_FILE) as f:
            cache = json.load(f)
            # Ensure pending_transcripts exists (backwards compatibility)
            if 'pending_transcripts' not in cache:
                cache['pending_transcripts'] = []
            return cache
    else:
        return {
            "last_check": datetime.now().isoformat(),
            "processed_meetings": [],
            "failed_downloads": [],
            "pending_transcripts": []
        }


def save_cache(cache):
    """Save processed meetings cache (atomic write)"""
    temp_file = CACHE_FILE.with_suffix('.tmp')
    with open(temp_file, 'w') as f:
        json.dump(cache, f, indent=2)
    temp_file.replace(CACHE_FILE)


def is_meeting_processed(meeting_id, cache):
    """Check if meeting has already been processed"""
    return any(m['meeting_id'] == meeting_id for m in cache['processed_meetings'])


def is_meeting_pending(meeting_id, cache):
    """Check if meeting is in pending transcripts list"""
    return any(m['meeting_id'] == meeting_id for m in cache.get('pending_transcripts', []))


def mark_meeting_pending(meeting, reason, cache):
    """
    Mark meeting as pending (transcript not ready yet).
    Will be retried on next run.
    """
    pending = cache.get('pending_transcripts', [])

    # Check if already pending - update retry count
    existing = next((m for m in pending if m['meeting_id'] == meeting['id']), None)

    if existing:
        existing['retry_count'] = existing.get('retry_count', 0) + 1
        existing['last_retry'] = datetime.now().isoformat()
        log(f"Updated pending meeting {meeting['id']} (retry #{existing['retry_count']})")
    else:
        # Add new pending meeting
        pending.append({
            'meeting_id': meeting['id'],
            'title': meeting['title'],
            'url': meeting['url'],
            'timestamp': meeting.get('timestamp'),
            'first_attempt': datetime.now().isoformat(),
            'retry_count': 1,
            'last_retry': datetime.now().isoformat(),
            'reason': reason
        })
        log(f"Added meeting {meeting['id']} to pending list (reason: {reason})")

    cache['pending_transcripts'] = pending
    save_cache(cache)


def remove_from_pending(meeting_id, cache):
    """Remove meeting from pending list (successfully processed or exceeded retries)"""
    cache['pending_transcripts'] = [
        m for m in cache.get('pending_transcripts', [])
        if m['meeting_id'] != meeting_id
    ]
    save_cache(cache)


def mark_meeting_processed(meeting_id, metadata, cache):
    """
    Mark meeting as processed with full metadata (AC #6).

    Required fields:
    - meeting_id: Krisp meeting ID
    - krisp_timestamp: Meeting timestamp from Krisp
    - matched_calendar_event: Calendar event title (None if not matched yet)
    - obsidian_note_path: Path to Obsidian note (None if not created yet)
    - transcript_path: Path to downloaded transcript
    - processed_at: ISO 8601 timestamp when processed
    - confidence: Match confidence (None if not matched yet)
    """
    cache['processed_meetings'].append({
        'meeting_id': meeting_id,
        'krisp_timestamp': metadata.get('krisp_timestamp'),
        'matched_calendar_event': metadata.get('matched_calendar_event'),
        'obsidian_note_path': metadata.get('obsidian_note_path'),
        'transcript_path': metadata.get('transcript_path'),
        'processed_at': datetime.now().isoformat(),
        'confidence': metadata.get('confidence'),
        'title': metadata.get('title')  # Keep for reference
    })
    cache['last_check'] = datetime.now().isoformat()
    save_cache(cache)


def main():
    parser = argparse.ArgumentParser(description='Download Krisp transcripts')
    parser.add_argument('--test-auth', action='store_true', help='Test authentication only')
    parser.add_argument('--download-new', action='store_true', help='Download new transcripts')
    parser.add_argument('--limit', type=int, default=5, help='Max meetings to download (default: 5)')
    parser.add_argument('--days-back', type=int, default=1, help='How many days back to search (default: 1 = last 24 hours)')
    parser.add_argument('--dry-run', action='store_true', help='Preview meetings without downloading')
    parser.add_argument('--headless', action='store_true', default=True, help='Run browser in headless mode')
    parser.add_argument('--visible', action='store_true', help='Run browser in visible mode (for debugging)')

    args = parser.parse_args()

    # Load environment variables for Telegram alerts (AC #8)
    load_env()

    if args.visible:
        args.headless = False

    try:
        if args.test_auth:
            success = test_krisp_auth()
            sys.exit(0 if success else 1)

        if args.download_new or args.dry_run:
            # Load cache
            cache = load_cache()

            # Scrape meetings with days_back parameter
            meetings = scrape_krisp_meetings(limit=args.limit, headless=args.headless, days_back=args.days_back)

            # Filter unprocessed meetings
            new_meetings = [m for m in meetings if not is_meeting_processed(m['id'], cache)]

            # Add pending meetings (with retry limit)
            MAX_RETRIES = 5
            pending_meetings = [
                m for m in cache.get('pending_transcripts', [])
                if m.get('retry_count', 0) < MAX_RETRIES
            ]

            # Convert pending meetings to meeting format
            pending_as_meetings = [
                {
                    'id': p['meeting_id'],
                    'title': p['title'],
                    'url': p['url'],
                    'timestamp': p.get('timestamp')
                }
                for p in pending_meetings
            ]

            # Merge new and pending (dedup by ID)
            all_meeting_ids = {m['id'] for m in new_meetings}
            for pending in pending_as_meetings:
                if pending['id'] not in all_meeting_ids:
                    new_meetings.append(pending)
                    all_meeting_ids.add(pending['id'])

            log(f"Found {len(new_meetings)} unprocessed meetings ({len(pending_as_meetings)} from pending list)")

            if len(new_meetings) == 0:
                log("No new meetings to process")
                print(json.dumps([], indent=2))
                sys.exit(0)

            # Dry-run mode: preview meetings without downloading
            if args.dry_run:
                log("=== DRY RUN MODE - No downloads will be performed ===")
                preview = []
                for i, meeting in enumerate(new_meetings, 1):
                    timestamp_str = meeting.get('timestamp', 'unknown')
                    preview.append({
                        'index': i,
                        'meeting_id': meeting['id'][:12] + '...',
                        'title': meeting['title'],
                        'timestamp': timestamp_str,
                        'status': 'pending' if is_meeting_pending(meeting['id'], cache) else 'new'
                    })
                    log(f"{i}. {meeting['title']} ({timestamp_str}) - {preview[-1]['status']}")

                print(json.dumps(preview, indent=2))
                log(f"=== Would download {len(new_meetings)} meetings (use --download-new to proceed) ===")
                sys.exit(0)

            # Create single browser session for all downloads
            log("Creating browser session for downloads...")

            cookies, localstorage = load_krisp_auth()

            with sync_playwright() as p:
                browser = p.chromium.launch(
                    headless=args.headless,
                    args=['--disable-blink-features=AutomationControlled']
                )

                context = browser.new_context(
                    user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
                    accept_downloads=True,
                    permissions=['clipboard-read', 'clipboard-write']
                )

                # Add cookies
                playwright_cookies = [convert_cookie_format(c) for c in cookies]
                context.add_cookies(playwright_cookies)

                page = context.new_page()
                stealth_sync(page)  # AC #1: Apply playwright-stealth anti-detection

                # Set localStorage
                page.goto("https://app.krisp.ai/", wait_until="domcontentloaded")
                for key, value in localstorage.items():
                    page.evaluate(f'localStorage.setItem("{key}", "{value}")')

                # Navigate to meeting list page for click-based downloads
                log("Navigating to meeting list page for downloads...")
                page.goto("https://app.krisp.ai/meeting-notes?page=1&limit=20", wait_until="load", timeout=30000)

                # Wait for meeting links to appear (React rendering)
                try:
                    page.wait_for_selector('a.meeting-item', state='visible', timeout=15000)
                    log("Meeting list page loaded with meeting links visible")
                except Exception as e:
                    log(f"Warning: Meeting links not visible: {str(e)}", "WARN")

                page.wait_for_timeout(2000)  # Extra buffer for React
                log("Starting downloads...")

                results = []
                pending_count = 0
                for meeting in new_meetings:
                    # Reuse same page for all downloads
                    status, transcript_path = download_transcript(
                        page,
                        meeting['id'],
                        meeting['url'],
                        download_dir=TRANSCRIPTS_DIR
                    )

                    if status == "success":
                        # Get transcript length for notification
                        transcript_file = Path(transcript_path)
                        transcript_length = len(transcript_file.read_text()) if transcript_file.exists() else 0

                        results.append({
                            'meeting_id': meeting['id'],
                            'title': meeting['title'],
                            'transcript_path': transcript_path
                        })

                        # Mark as processed with full metadata (AC #6)
                        mark_meeting_processed(meeting['id'], {
                            'title': meeting['title'],
                            'krisp_timestamp': meeting.get('timestamp'),  # From title parsing
                            'transcript_path': transcript_path,
                            'matched_calendar_event': None,  # Story 4-3 will populate
                            'obsidian_note_path': None,  # Story 4-3 will populate
                            'confidence': None  # Story 4-3 will populate
                        }, cache)

                        # Remove from pending if it was there
                        if is_meeting_pending(meeting['id'], cache):
                            remove_from_pending(meeting['id'], cache)
                            log(f"✓ Removed {meeting['id']} from pending list (successfully processed)")

                        # Send Telegram notification for successful download
                        send_telegram_notification(
                            meeting_title=meeting['title'],
                            meeting_timestamp=meeting.get('timestamp'),
                            transcript_path=transcript_path,
                            transcript_length=transcript_length
                        )

                    elif status == "not_ready":
                        # Transcript not ready yet - add to pending list for retry
                        mark_meeting_pending(meeting, "transcript_not_ready", cache)
                        pending_count += 1

                    else:  # error
                        log(f"Failed to download: {meeting['title']}", "ERROR")

                    # Random delay between downloads (2-4 seconds)
                    delay = 2 + (hash(meeting['id']) % 3)
                    log(f"Waiting {delay}s before next download...")
                    time.sleep(delay)

                browser.close()

            # Output results as JSON for orchestrator
            log(f"✓ Successfully downloaded {len(results)}/{len(new_meetings)} transcripts")
            if pending_count > 0:
                log(f"⏳ {pending_count} meetings added to pending list (transcript not ready)")

            # Send summary notification if any meetings were processed
            if len(results) > 0 or pending_count > 0:
                summary_msg = (
                    "📊 <b>Krisp Download Batch Complete</b>\n\n"
                    f"✅ <b>Downloaded:</b> {len(results)} transcripts\n"
                )
                if pending_count > 0:
                    summary_msg += f"⏳ <b>Pending:</b> {pending_count} (transcript not ready)\n"

                failed_count = len(new_meetings) - len(results) - pending_count
                if failed_count > 0:
                    summary_msg += f"❌ <b>Failed:</b> {failed_count}\n"

                summary_msg += f"\n<b>Time range:</b> Last {args.days_back} days"

                send_telegram_alert(summary_msg)

            print(json.dumps(results, indent=2))
            sys.exit(0)

        # Default: show help
        parser.print_help()

    except Exception as e:
        log(f"Fatal error: {str(e)}", "ERROR")
        import traceback
        log(traceback.format_exc(), "ERROR")
        sys.exit(1)


if __name__ == '__main__':
    main()
