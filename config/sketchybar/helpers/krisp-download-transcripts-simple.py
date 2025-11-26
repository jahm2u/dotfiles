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
import subprocess
from pathlib import Path
from datetime import datetime, timedelta
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout
from playwright_stealth import stealth_sync
from dotenv import load_dotenv
import argparse
import importlib.util

# Configuration
CACHE_DIR = Path.home() / ".cache/sketchybar"
CACHE_FILE = CACHE_DIR / "krisp-downloaded-transcripts.json"
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


def sanitize_filename(title, max_length=50):
    """
    Sanitize a meeting title for use in filename.

    Rules:
    - Lowercase all characters
    - Replace spaces with hyphens
    - Remove special characters except hyphens
    - Truncate to max_length chars
    """
    import unicodedata

    # Normalize unicode characters (é → e, etc.)
    title = unicodedata.normalize('NFKD', title).encode('ASCII', 'ignore').decode('ASCII')

    # Lowercase
    title = title.lower()

    # Replace spaces and underscores with hyphens
    title = re.sub(r'[\s_]+', '-', title)

    # Remove everything except alphanumeric and hyphens
    title = re.sub(r'[^a-z0-9\-]', '', title)

    # Collapse multiple hyphens
    title = re.sub(r'-+', '-', title)

    # Remove leading/trailing hyphens
    title = title.strip('-')

    # Truncate
    if len(title) > max_length:
        title = title[:max_length].rstrip('-')

    return title or 'unknown'


def send_telegram_notification(metadata):
    """
    Send Telegram notification with classification details for verification.
    """
    try:
        bot_token = os.getenv('TELEGRAM_BOT_TOKEN')
        chat_id = os.getenv('TELEGRAM_CHAT_ID')

        if not bot_token or not chat_id:
            log("Telegram credentials not configured, skipping notification", "DEBUG")
            return

        # Build message
        original_title = metadata.get('title', 'Unknown')
        calendar_title = metadata.get('calendar_title', original_title)
        meeting_type = metadata.get('meeting_type', 'unknown')
        confidence = metadata.get('confidence', 0)
        meeting_id = metadata.get('meeting_id', 'unknown')
        date = metadata.get('date', 'unknown')

        # Determine if calendar matched
        calendar_matched = metadata.get('calendar_matched', False)
        match_icon = "✓" if calendar_matched else "?"

        message = f"""📝 Krisp Meeting Downloaded

Original: {original_title}
Resolved: {calendar_title} {match_icon}
Type: {meeting_type}
Confidence: {confidence}
Date: {date}

ID: {meeting_id[:12]}..."""

        # Send via Telegram API
        import urllib.request
        import urllib.parse

        url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
        data = urllib.parse.urlencode({
            'chat_id': chat_id,
            'text': message,
            'parse_mode': 'HTML'
        }).encode('utf-8')

        req = urllib.request.Request(url, data=data)
        urllib.request.urlopen(req, timeout=10)

        log(f"Telegram notification sent for {meeting_id[:8]}...", "INFO")

    except Exception as e:
        log(f"Failed to send Telegram notification: {e}", "WARN")

def parse_krisp_date(title):
    """
    Parse date and time from Krisp title format.
    Examples:
      "04:30 PM - Slack meeting November 4" → ("2024-11-04", "04:30 PM")
      "11:30 AM - Discord meeting October 31" → ("2024-10-31", "11:30 AM")

    Key fix: Assume meetings are from PAST, not future.
    If date appears to be in future, it's actually from last year.
    """
    try:
        # Extract time from beginning
        time_match = re.match(r'(\d{1,2}:\d{2}\s+[AP]M)\s*-', title)
        time_str = time_match.group(1) if time_match else None

        # Extract month and day from end
        date_match = re.search(r'meeting\s+([A-Za-z]+)\s+(\d{1,2})', title)
        if not date_match:
            return None, time_str

        month_str = date_match.group(1)
        day = int(date_match.group(2))

        # Map month name to number
        month_map = {
            'january': 1, 'jan': 1, 'february': 2, 'feb': 2, 'march': 3, 'mar': 3,
            'april': 4, 'apr': 4, 'may': 5, 'june': 6, 'jun': 6,
            'july': 7, 'jul': 7, 'august': 8, 'aug': 8,
            'september': 9, 'sep': 9, 'sept': 9, 'october': 10, 'oct': 10,
            'november': 11, 'nov': 11, 'december': 12, 'dec': 12
        }

        month = month_map.get(month_str.lower())
        if not month:
            return None, time_str

        # Determine year: assume meetings are from the past
        now = datetime.now()

        # Try current year first
        try:
            meeting_date = datetime(now.year, month, day)
            # If this date is in the future (more than 1 day ahead), use last year
            if meeting_date > now + timedelta(days=1):
                meeting_date = datetime(now.year - 1, month, day)
        except ValueError:
            # Invalid date (e.g., Feb 30), use last year
            meeting_date = datetime(now.year - 1, month, day)

        return meeting_date.strftime("%Y-%m-%d"), time_str

    except Exception as e:
        log(f"Failed to parse date from '{title}': {e}", "WARN")
        return None, None

def enrich_with_calendar_match(title, meeting_id):
    """
    Enrich meeting metadata with calendar matching.
    Returns dict with full classification data.
    """
    log(f"Enriching metadata with calendar match for: {title}")

    # Parse date/time from title
    date, time_str = parse_krisp_date(title)

    if not date:
        log("Could not parse date from title", "WARN")
        return {
            "meeting_id": meeting_id,
            "title": title,
            "downloaded_at": datetime.now().isoformat(),
            "date": None,
            "time": None,
            "calendar_matched": False
        }

    log(f"Parsed date: {date}, time: {time_str}")

    # Call unified classifier with calendar matching
    try:
        classify_script = HELPERS_DIR / "classify-meeting-unified.py"
        venv_python = Path.home() / ".config/sketchybar/venv/bin/python3"

        cmd = [str(venv_python), str(classify_script), "--title", title, "--date", date]
        if time_str:
            cmd.extend(["--time", time_str])

        log(f"Calling classifier: {' '.join(cmd)}")

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode == 0 and result.stdout:
            classification = json.loads(result.stdout)

            # Build enriched metadata
            metadata = {
                "meeting_id": meeting_id,
                "title": title,
                "downloaded_at": datetime.now().isoformat(),
                "date": date,
                "time": time_str,
                "calendar_matched": classification.get('source') == 'calendar',
                "calendar_title": classification.get('meeting_title'),
                "meeting_type": classification.get('meeting_type'),
                "company": classification.get('company'),
                "participant": classification.get('participant'),
                "person_folder": classification.get('person_folder'),
                "confidence": classification.get('confidence', 0),
                "classification_source": classification.get('source')
            }

            log(f"✓ Calendar match: {metadata['calendar_matched']}, Type: {metadata['meeting_type']}, "
                f"Company: {metadata['company']}, Participant: {metadata['participant']}")

            return metadata
        else:
            log(f"Classifier failed: {result.stderr}", "WARN")

    except subprocess.TimeoutExpired:
        log("Classifier timed out", "ERROR")
    except json.JSONDecodeError as e:
        log(f"Failed to parse classifier output: {e}", "ERROR")
    except Exception as e:
        log(f"Calendar matching error: {e}", "ERROR")

    # Fallback: basic metadata without calendar match
    return {
        "meeting_id": meeting_id,
        "title": title,
        "downloaded_at": datetime.now().isoformat(),
        "date": date,
        "time": time_str,
        "calendar_matched": False
    }

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
            elif status == 'success' and transcript_text:
                # Enrich metadata with calendar matching FIRST
                metadata = enrich_with_calendar_match(title, meeting_id) if meeting_id else {}

                # Build filename using new naming convention:
                # {date}-{sanitized-calendar-title}-{meeting_id}.txt
                if meeting_id:
                    # Use calendar_title if available, else original title
                    display_title = metadata.get('calendar_title') or title
                    date_str = metadata.get('date') or datetime.now().strftime("%Y-%m-%d")
                    sanitized_title = sanitize_filename(display_title)

                    # New naming: date-title-id.txt
                    base_filename = f"{date_str}-{sanitized_title}-{meeting_id}"
                    transcript_path = TRANSCRIPTS_DIR / f"{base_filename}.txt"
                    metadata_path = TRANSCRIPTS_DIR / f"{base_filename}.json"

                    # Store the filename in metadata for reference
                    metadata['filename'] = base_filename

                    # Save enriched metadata
                    metadata_path.write_text(json.dumps(metadata, indent=2))
                    log(f"✓ Saved metadata: {metadata_path.name}")

                    # Send Telegram notification for verification
                    send_telegram_notification(metadata)
                else:
                    # No meeting ID - use timestamp fallback
                    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
                    transcript_path = TRANSCRIPTS_DIR / f"unknown-{timestamp}.txt"

                transcript_path.write_text(transcript_text)
                log(f"✓ Saved transcript: {transcript_path.name}")
                log(f"✓ Transcript length: {len(transcript_text)} characters")
                log(f"✓ Classification: {metadata.get('meeting_type', 'unknown')} (confidence: {metadata.get('confidence', 0)})")
                success_count += 1

                # Note: We don't mark as processed here - let krisp-process-transcript.py
                # mark it as processed after successful AI analysis and note update
                log(f"✓ Download complete, will be processed in batch phase")
            elif status == 'not_ready':
                log(f"⏳ Transcript not ready yet, skipping...", "WARN")
                not_ready_count += 1
            else:  # status == 'error'
                log(f"✗ Failed to download transcript", "ERROR")
                error_count += 1

            # Navigate back to list
            log("Navigating back to list...")
            try:
                page.goto("https://app.krisp.ai/meeting-notes?page=1&limit=20", wait_until="load", timeout=30000)
                page.wait_for_selector('a.meeting-item', state='visible', timeout=15000)  # Increased timeout
                page.wait_for_timeout(2000)  # Extra buffer
            except Exception as nav_error:
                log(f"⚠ Navigation back failed: {nav_error}", "WARN")
                # Try to recover by refreshing the page
                try:
                    log("Attempting recovery with page refresh...")
                    page.reload(wait_until="load", timeout=30000)
                    page.wait_for_selector('a.meeting-item', state='visible', timeout=15000)
                except Exception as recovery_error:
                    log(f"✗ Recovery failed: {recovery_error}", "ERROR")
                    raise  # Re-raise to exit gracefully

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
