#!/usr/bin/env python3
"""
Unified Meeting Classification with Calendar Matching
A single source of truth for meeting classification across all scripts.

This script provides consistent meeting classification by:
1. First attempting to match with calendar events (most accurate)
2. Falling back to pattern matching if no calendar match found
3. Applying email-to-name mappings for participant identification

Used by:
- meeting-prep.sh (when clicking meeting icon)
- krisp processing pipeline (for downloaded transcripts)
- any other script needing meeting classification

Author: Claude (unifying John's work)
Date: 2025-11-10
"""

import argparse
import json
import re
import subprocess
import sys
import os
from datetime import datetime, timedelta
from pathlib import Path

# Month name to number mapping
MONTH_MAP = {
    'january': 1, 'jan': 1,
    'february': 2, 'feb': 2,
    'march': 3, 'mar': 3,
    'april': 4, 'apr': 4,
    'may': 5,
    'june': 6, 'jun': 6,
    'july': 7, 'jul': 7,
    'august': 8, 'aug': 8,
    'september': 9, 'sep': 9, 'sept': 9,
    'october': 10, 'oct': 10,
    'november': 11, 'nov': 11,
    'december': 12, 'dec': 12
}

# Known company mapping for Discord/external meetings
PARTICIPANT_COMPANY_MAP = {
    'dannniboy': 'DT',
    'danniboy': 'DT',
    'chris': 'MT',
    'nima': 'CO',  # Cross-organization
    'kyle': 'CO',
}


def log(message, level="INFO"):
    """Log to stderr to avoid contaminating JSON output"""
    print(f"[{level}] {message}", file=sys.stderr)


def load_email_name_map():
    """Load email to Obsidian name mapping from config file."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    map_file = os.path.join(script_dir, "email-name-map.txt")

    email_map = {}
    if os.path.exists(map_file):
        with open(map_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                if '=' in line:
                    email, name = line.split('=', 1)
                    email_map[email.strip().lower()] = name.strip()

    return email_map


def query_calendar_events(date_str):
    """
    Query khal for events on specified date.
    Returns list of events with start_time and title.
    """
    try:
        # Use khal to get events for the date
        result = subprocess.run(
            ['khal', 'list', date_str, '1d', '--format', '{start-time} | {title}'],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode != 0:
            log(f"khal query failed: {result.stderr}", "ERROR")
            return []

        events = []
        for line in result.stdout.strip().split('\n'):
            if not line or '|' not in line:
                continue

            parts = line.split('|', 1)
            if len(parts) == 2:
                start_time_raw = parts[0].strip()
                title = parts[1].strip()

                # Convert khal's 12-hour format (08:00 AM) to 24-hour format (08:00)
                try:
                    if 'AM' in start_time_raw or 'PM' in start_time_raw:
                        time_obj = datetime.strptime(start_time_raw, "%I:%M %p")
                        start_time_24h = time_obj.strftime("%H:%M")
                    else:
                        start_time_24h = start_time_raw

                    events.append({
                        'start_time': start_time_24h,
                        'title': title
                    })
                except ValueError:
                    # If parsing fails, skip this event
                    log(f"Failed to parse time '{start_time_raw}'", "WARN")
                    continue

        log(f"Found {len(events)} calendar events for {date_str}", "INFO")
        return events

    except subprocess.TimeoutExpired:
        log("khal query timed out", "ERROR")
    except FileNotFoundError:
        log("khal not found - install with: brew install khal", "ERROR")
    except Exception as e:
        log(f"Calendar query error: {e}", "ERROR")

    return []


def match_with_calendar(title, date, time_str=None):
    """
    Try to match a meeting title/time with actual calendar events.
    Returns the best matching calendar event or None.
    """
    if not date:
        return None

    # Query calendar for the date
    events = query_calendar_events(date)
    if not events:
        return None

    # If we have a specific time, try to match it
    if time_str:
        # Convert to 24h format for comparison
        try:
            time_obj = datetime.strptime(time_str, "%I:%M %p")
            time_24h = time_obj.strftime("%H:%M")
        except:
            time_24h = None

        if time_24h:
            # Look for exact time match first
            for event in events:
                if event['start_time'] == time_24h:
                    log(f"Exact calendar match: {event['title']}", "INFO")
                    return event

            # Look for close time match (within 15 minutes - meetings often start late)
            for event in events:
                try:
                    event_time = datetime.strptime(event['start_time'], "%H:%M")
                    target_time = datetime.strptime(time_24h, "%H:%M")
                    diff = abs((event_time - target_time).total_seconds() / 60)
                    if diff <= 15:
                        log(f"Close calendar match (±{int(diff)}min): {event['title']}", "INFO")
                        return event
                except:
                    continue

    # If no time match within 15 min, try relaxed matching (within 30 min)
    # but ONLY for events that also have platform hints
    if time_24h:
        title_lower = title.lower()
        for event in events:
            try:
                event_time = datetime.strptime(event['start_time'], "%H:%M")
                target_time = datetime.strptime(time_24h, "%H:%M")
                diff = abs((event_time - target_time).total_seconds() / 60)

                # Within 30 min AND has platform/pattern hint
                if diff <= 30:
                    event_title_lower = event['title'].lower()
                    has_hint = (
                        ('slack' in title_lower and 'slack' in event_title_lower) or
                        ('discord' in title_lower and ('discord' in event_title_lower or '1:1' in event_title_lower or '1on1' in event_title_lower)) or
                        ('zoom' in title_lower and 'zoom' in event_title_lower)
                    )
                    if has_hint:
                        log(f"Relaxed calendar match (±{int(diff)}min + platform hint): {event['title']}", "INFO")
                        return event
            except:
                continue

    return None


def extract_participant_from_title(title, user_names=['jeff', 'hamersly']):
    """
    Extract participant name from meeting title, filtering out the user.

    Handles patterns like:
    - "Jeff <> Giovanna" → "Giovanna"
    - "Vlad & Jeff" → "Vlad"
    - "1on1 Thais Jeff" → "Thais"
    - "Follow-up APM Position Jeff <> Giovanna" → "Giovanna"
    """
    # Pattern 1: "<>" separator
    match = re.search(r'([^<]+)\s*<>\s*(.+)', title)
    if match:
        left = match.group(1).strip()
        right = match.group(2).strip()

        # Extract just the names (usually last word on left, first word on right)
        left_words = left.split()
        right_words = right.split()

        # Take last word from left side, first word from right side
        left_name = left_words[-1] if left_words else ""
        right_name = right_words[0] if right_words else ""

        # Return the one that isn't the user
        if right_name.lower() not in user_names and right_name:
            return right_name  # Prefer right side first
        if left_name.lower() not in user_names and left_name:
            return left_name

    # Pattern 2: "&" separator
    match = re.search(r'(.+?)\s+&\s+(.+?)(?:\s+moving forward)?', title, re.IGNORECASE)
    if match:
        left = match.group(1).strip().split()[-1]  # Take last word
        right = match.group(2).strip().split()[0]   # Take first word

        if left.lower() not in user_names:
            return left
        if right.lower() not in user_names:
            return right

    # Pattern 3: "1on1 Name1 Name2"
    match = re.search(r'1on1\s+(\w+)(?:\s+(\w+))?', title, re.IGNORECASE)
    if match:
        name1 = match.group(1)
        name2 = match.group(2) if match.group(2) else None

        if name1.lower() not in user_names:
            return name1
        if name2 and name2.lower() not in user_names:
            return name2

    # Pattern 4: "1:1 with Name" or "1on1 with Name"
    match = re.search(r'1[:o]1\s+with\s+(\w+)', title, re.IGNORECASE)
    if match:
        return match.group(1)

    return None


def classify_from_calendar_title(title):
    """
    Classify a meeting based on calendar title (more reliable than Krisp titles).
    Returns dict with meeting_type, company, participant.
    """
    title_lower = title.lower()
    result = {
        'meeting_type': 'unknown',
        'company': None,
        'participant': None,
        'confidence': 0
    }

    # Check for 1-on-1 patterns
    one_on_one_indicators = [
        r'1:1', r'1on1', r'1-on-1',
        r'<>', r'\s&\s'  # Separators indicating 1-on-1
    ]

    is_one_on_one = any(re.search(pattern, title, re.IGNORECASE) for pattern in one_on_one_indicators)

    if is_one_on_one:
        result['meeting_type'] = 'one-on-one'
        result['participant'] = extract_participant_from_title(title)
        result['confidence'] = 0.9 if result['participant'] else 0.5

    # If no 1:1 pattern, check for company meetings
    if result['meeting_type'] == 'unknown':
        company_patterns = [
            (r'\[IPMedia\]', 'IPMedia'),
            (r'IPMedia', 'IPMedia'),
            (r'\[DT\]', 'DT'),
            (r'\[MT\]', 'MT'),
            (r'\[CO\]', 'CO'),
            (r'All Hands', 'company'),
            (r'Team Meeting', 'team'),
            (r'Sprint', 'team'),
            (r'Retro', 'team'),
            (r'Planning', 'team')
        ]

        for pattern, company in company_patterns:
            if re.search(pattern, title, re.IGNORECASE):
                result['company'] = company if company != 'company' and company != 'team' else 'IPMedia'
                result['meeting_type'] = 'company' if company == 'company' else 'team'
                result['confidence'] = 0.8
                break

    # Extract participant if not already found
    if not result['participant'] and result['meeting_type'] == 'one-on-one':
        # Try to extract name before common words
        name_match = re.search(r'^(\w+)\s+(?:1:1|1on1|meeting)', title, re.IGNORECASE)
        if name_match:
            result['participant'] = name_match.group(1)

    return result


def classify_from_krisp_title(title):
    """
    Fallback classification from Krisp title alone (less accurate).
    """
    title_lower = title.lower()
    result = {
        'meeting_type': 'unknown',
        'company': None,
        'participant': None,
        'confidence': 0.3
    }

    # Platform gives hints
    if 'discord' in title_lower:
        # Discord usually means external/CO meetings
        result['meeting_type'] = 'one-on-one'
        result['company'] = 'CO'

        # Try to infer participant from known mappings
        for name, company in PARTICIPANT_COMPANY_MAP.items():
            if name in title_lower:
                result['participant'] = name.capitalize()
                result['company'] = company
                result['confidence'] = 0.6
                break

    elif 'slack' in title_lower:
        # Slack is usually internal IPMedia
        result['company'] = 'IPMedia'
        result['confidence'] = 0.5

    return result


def main():
    parser = argparse.ArgumentParser(description='Unified meeting classification')
    parser.add_argument('--title', required=True, help='Meeting title (from Krisp or calendar)')
    parser.add_argument('--date', help='Meeting date (YYYY-MM-DD)')
    parser.add_argument('--time', help='Meeting time (HH:MM AM/PM)')
    parser.add_argument('--participants', help='Comma-separated participant emails')
    parser.add_argument('--year', help='Year if date not provided')
    parser.add_argument('--month', help='Month if date not provided')
    parser.add_argument('--day', help='Day if date not provided')

    args = parser.parse_args()

    # Construct date if provided as components
    if not args.date and args.year and args.month and args.day:
        args.date = f"{args.year}-{args.month:02d}-{args.day:02d}"

    result = {
        'meeting_title': args.title,
        'meeting_type': 'unknown',
        'company': None,
        'participant': None,
        'confidence': 0,
        'source': 'unknown'
    }

    # Step 1: Try calendar matching (most accurate)
    calendar_event = None
    if args.date:
        calendar_event = match_with_calendar(args.title, args.date, args.time)
        if calendar_event:
            # Use calendar title for classification
            classification = classify_from_calendar_title(calendar_event['title'])
            result.update(classification)
            result['meeting_title'] = calendar_event['title']  # Use calendar title
            result['source'] = 'calendar'
            log(f"Using calendar classification: {result['meeting_type']}", "INFO")

    # Step 2: If no calendar match, try pattern matching on title
    if not calendar_event:
        # First try as if it's a calendar title (might be from meeting-prep.sh)
        classification = classify_from_calendar_title(args.title)
        if classification['confidence'] > 0.7:
            result.update(classification)
            result['source'] = 'title_pattern'
            log(f"Using title pattern classification: {result['meeting_type']}", "INFO")
        else:
            # Fall back to Krisp title classification
            classification = classify_from_krisp_title(args.title)
            result.update(classification)
            result['source'] = 'krisp_pattern'
            log(f"Using Krisp pattern classification: {result['meeting_type']}", "INFO")

    # Step 3: Apply email mapping if we have participants
    if args.participants:
        email_map = load_email_name_map()
        emails = [e.strip().lower() for e in args.participants.split(',')]

        for email in emails:
            if email in email_map:
                name = email_map[email]
                if name != "SKIP":
                    result['participant'] = name
                    break

    # Step 4: Determine company from participant if needed
    if result['participant'] and not result['company']:
        participant_lower = result['participant'].lower()
        if participant_lower in PARTICIPANT_COMPANY_MAP:
            result['company'] = PARTICIPANT_COMPANY_MAP[participant_lower]
        elif result['meeting_type'] == 'one-on-one':
            # Default to IPMedia for internal 1:1s
            result['company'] = 'IPMedia'

    # Step 5: Call find-person-folder if we have a participant
    if result['participant'] and result['company']:
        try:
            script_dir = Path(__file__).parent
            folder_result = subprocess.run(
                ['bash', str(script_dir / 'find-person-folder.sh'), result['participant']],
                capture_output=True,
                text=True,
                timeout=5
            )
            if folder_result.returncode == 0:
                result['person_folder'] = folder_result.stdout.strip()
                log(f"Found person folder: {result['person_folder']}", "INFO")
        except Exception as e:
            log(f"Failed to find person folder: {e}", "WARN")

    # Output JSON result
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())