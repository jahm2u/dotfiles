#!/usr/bin/env python3
"""
Krisp Meeting Matcher - Calendar Integration
Matches Krisp transcripts to khal calendar events with ±15-minute tolerance.

Author: Jeff Hamersly
Date: 2025-11-02
Story: 4-3 - AI Analysis & Note Integration
"""

import argparse
import json
import sys
import subprocess
import re
import os
from datetime import datetime, timedelta
from pathlib import Path
from dotenv import load_dotenv

# Load .env file for OBSIDIAN_VAULT_PATH
env_paths = [
    Path.home() / "repos/02_personal/dotfiles/.env",
    Path.home() / "dotfiles/.env",
    Path(__file__).parent.parent / ".env",
    Path.home() / ".env",
]
for env_path in env_paths:
    if env_path.exists():
        load_dotenv(env_path)
        break

# Month name to number mapping
MONTH_MAP = {
    'january': 1, 'february': 2, 'march': 3, 'april': 4,
    'may': 5, 'june': 6, 'july': 7, 'august': 8,
    'september': 9, 'october': 10, 'november': 11, 'december': 12
}


def log(message, level="INFO"):
    """Simple logging to stderr"""
    print(f"[{level}] {message}", file=sys.stderr)


def parse_krisp_title(title):
    """
    Parse Krisp meeting title to extract time, source, month, day.

    Format: "HH:MM AM/PM - Source meeting Month Day"
    Example: "08:25 PM - Signal meeting October 31"

    Returns dict with time_24h, source, month, day or None if parsing fails.
    """
    # Pattern: HH:MM AM/PM - Source meeting Month Day
    pattern = r'(\d{1,2}):(\d{2})\s+(AM|PM)\s+-\s+(\w+)\s+meeting\s+(\w+)\s+(\d{1,2})'
    match = re.match(pattern, title, re.IGNORECASE)

    if not match:
        log(f"Failed to parse Krisp title: {title}", "WARN")
        return None

    hour, minute, period, source, month, day = match.groups()

    # Convert to 24-hour format
    hour_int = int(hour)
    if period.upper() == 'PM' and hour_int != 12:
        hour_int += 12
    elif period.upper() == 'AM' and hour_int == 12:
        hour_int = 0

    time_24h = f"{hour_int:02d}:{minute}"

    # Convert month name to number
    month_lower = month.lower()
    month_num = MONTH_MAP.get(month_lower)

    if not month_num:
        log(f"Unknown month: {month}", "WARN")
        return None

    return {
        'time_24h': time_24h,
        'source': source.lower(),
        'month': month_num,
        'day': int(day)
    }


def get_khal_events(date_str):
    """
    Query khal for events on specified date.

    Args:
        date_str: Date in YYYY-MM-DD format

    Returns list of event dicts with start_time and title.
    """
    try:
        # khal list YYYY-MM-DD 1d --format '{start-time} | {title}'
        result = subprocess.run(
            ['khal', 'list', date_str, '1d', '--format', '{start-time} | {title}'],
            capture_output=True,
            text=True,
            timeout=180  # 3 minutes for large calendar databases (8000+ events)
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
                start_time = parts[0].strip()
                title = parts[1].strip()
                events.append({
                    'start_time': start_time,
                    'title': title
                })

        return events

    except subprocess.TimeoutExpired:
        log("khal query timed out", "ERROR")
        return []
    except FileNotFoundError:
        log("khal not found - ensure it's installed via homebrew", "ERROR")
        return []
    except Exception as e:
        log(f"Error querying khal: {str(e)}", "ERROR")
        return []


def classify_meeting(event_title, date, participants=""):
    """
    Classify meeting using Story 4-1 classify-meeting.py script (AC #2).

    Args:
        event_title: Calendar event title
        date: Date string (YYYY-MM-DD)
        participants: Comma-separated participant emails (optional)

    Returns dict with meeting_type, company, participant, confidence or None on error.
    """
    try:
        script_path = Path(__file__).parent / "classify-meeting.py"
        venv_python = Path.home() / ".config/sketchybar/venv/bin/python3"

        cmd = [
            str(venv_python),
            str(script_path),
            "--title", event_title,
            "--date", date
        ]

        if participants:
            cmd.extend(["--participants", participants])

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            log(f"classify-meeting.py failed: {result.stderr}", "ERROR")
            return None

        # Parse JSON output
        classification = json.loads(result.stdout)
        return classification

    except subprocess.TimeoutExpired:
        log("classify-meeting.py timed out", "ERROR")
        return None
    except json.JSONDecodeError as e:
        log(f"Failed to parse classification JSON: {str(e)}", "ERROR")
        return None
    except Exception as e:
        log(f"Error classifying meeting: {str(e)}", "ERROR")
        return None


def find_person_folder(person_name, company):
    """
    Find person folder in Obsidian vault using Story 4-1 find-person-folder.sh (AC #3).

    Args:
        person_name: Person's name (e.g., "Kyle Smith")
        company: Company name (e.g., "IPMedia")

    Returns dict with person_folder, meetings_folder, profile_path or None on error.
    """
    try:
        script_path = Path(__file__).parent / "find-person-folder.sh"
        vault_path = os.getenv("OBSIDIAN_VAULT_PATH")

        if not vault_path:
            log("OBSIDIAN_VAULT_PATH not set in environment", "ERROR")
            return None

        cmd = [
            "bash",
            str(script_path),
            "--person", person_name,
            "--company", company,
            "--vault-path", vault_path
        ]

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            log(f"find-person-folder.sh failed: {result.stderr}", "WARN")
            return None

        # Parse output (script returns path on stdout)
        person_folder = result.stdout.strip()

        if not person_folder:
            log(f"No folder found for {person_name} at {company}", "WARN")
            return None

        return {
            'person_folder': person_folder,
            'meetings_folder': str(Path(person_folder) / "Meetings"),
            'profile_path': str(Path(person_folder) / "profile.md")
        }

    except subprocess.TimeoutExpired:
        log("find-person-folder.sh timed out", "ERROR")
        return None
    except Exception as e:
        log(f"Error finding person folder: {str(e)}", "ERROR")
        return None


def match_transcript_to_calendar(krisp_title, year=None):
    """
    Match Krisp transcript to calendar event with ±15-minute tolerance (AC #1).

    Args:
        krisp_title: Krisp meeting title (e.g., "08:25 PM - Signal meeting October 31")
        year: Year for the meeting (defaults to current year)

    Returns dict with:
        - confidence: high_confidence|medium_confidence|manual_review_needed|no_match
        - event: Matched calendar event dict (if found)
        - reason: Explanation of matching result
        - candidates: List of candidate events (for manual review)
    """
    # Parse Krisp title
    parsed = parse_krisp_title(krisp_title)
    if not parsed:
        return {
            'confidence': 'no_match',
            'event': None,
            'reason': 'Failed to parse Krisp title',
            'candidates': []
        }

    # Construct datetime for the meeting
    if year is None:
        year = datetime.now().year

    try:
        meeting_time = datetime.strptime(
            f"{year}-{parsed['month']:02d}-{parsed['day']:02d} {parsed['time_24h']}",
            "%Y-%m-%d %H:%M"
        )
    except ValueError as e:
        return {
            'confidence': 'no_match',
            'event': None,
            'reason': f'Invalid date/time: {str(e)}',
            'candidates': []
        }

    # Query khal for events on that date
    date_str = meeting_time.strftime("%Y-%m-%d")
    khal_events = get_khal_events(date_str)

    if not khal_events:
        return {
            'confidence': 'no_match',
            'event': None,
            'reason': f'No calendar events found on {date_str}',
            'candidates': []
        }

    # Find candidates within ±15-minute window
    window_start = meeting_time - timedelta(minutes=15)
    window_end = meeting_time + timedelta(minutes=15)

    candidates = []
    for event in khal_events:
        try:
            # Parse event start time (format: "20:25" or "08:25 PM")
            event_time_str = event['start_time']

            # Try 24-hour format first
            try:
                event_time = datetime.strptime(
                    f"{date_str} {event_time_str}",
                    "%Y-%m-%d %H:%M"
                )
            except ValueError:
                # Try 12-hour format
                event_time = datetime.strptime(
                    f"{date_str} {event_time_str}",
                    "%Y-%m-%d %I:%M %p"
                )

            # Check if within window
            if window_start <= event_time <= window_end:
                time_diff = abs((event_time - meeting_time).total_seconds())
                candidates.append({
                    'event': event,
                    'time_diff_seconds': time_diff,
                    'event_time': event_time
                })

        except ValueError as e:
            log(f"Failed to parse event time '{event_time_str}': {str(e)}", "WARN")
            continue

    # Sort candidates by time difference (closest first)
    candidates.sort(key=lambda x: x['time_diff_seconds'])

    # Determine confidence based on candidate count
    if len(candidates) == 0:
        return {
            'confidence': 'no_match',
            'event': None,
            'reason': f'No events within ±15min of {parsed["time_24h"]}',
            'candidates': []
        }

    elif len(candidates) == 1:
        # Single match = high confidence
        return {
            'confidence': 'high_confidence',
            'event': candidates[0]['event'],
            'reason': f'Single event match within ±15min window',
            'time_diff_seconds': candidates[0]['time_diff_seconds'],
            'candidates': [c['event'] for c in candidates]
        }

    else:
        # Multiple candidates - try to disambiguate by source name
        best_match = candidates[0]  # Closest by time

        # Check if source appears in event title
        source_match = any(
            parsed['source'].lower() in c['event']['title'].lower()
            for c in candidates
        )

        if source_match:
            # Found source name in one of the candidates
            for c in candidates:
                if parsed['source'].lower() in c['event']['title'].lower():
                    return {
                        'confidence': 'medium_confidence',
                        'event': c['event'],
                        'reason': f'Multiple candidates, matched by source name: {parsed["source"]}',
                        'time_diff_seconds': c['time_diff_seconds'],
                        'candidates': [x['event'] for x in candidates]
                    }

        # Multiple candidates, ambiguous
        return {
            'confidence': 'manual_review_needed',
            'event': best_match['event'],
            'reason': f'{len(candidates)} candidates within window, no clear match',
            'time_diff_seconds': best_match['time_diff_seconds'],
            'candidates': [c['event'] for c in candidates]
        }


def main():
    parser = argparse.ArgumentParser(
        description='Match Krisp transcripts to calendar events'
    )
    parser.add_argument(
        '--title',
        required=True,
        help='Krisp meeting title (e.g., "08:25 PM - Signal meeting October 31")'
    )
    parser.add_argument(
        '--year',
        type=int,
        default=None,
        help='Year of the meeting (defaults to current year)'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output result as JSON'
    )

    args = parser.parse_args()

    # Perform matching
    result = match_transcript_to_calendar(args.title, year=args.year)

    if args.json:
        # JSON output for programmatic use
        print(json.dumps(result, indent=2))
    else:
        # Human-readable output
        print(f"Confidence: {result['confidence']}")
        print(f"Reason: {result['reason']}")

        if result['event']:
            print(f"\nMatched Event:")
            print(f"  Time: {result['event']['start_time']}")
            print(f"  Title: {result['event']['title']}")

            if 'time_diff_seconds' in result:
                mins = int(result['time_diff_seconds'] / 60)
                print(f"  Time Difference: {mins} minutes")

        if len(result.get('candidates', [])) > 1:
            print(f"\nAll Candidates ({len(result['candidates'])}):")
            for i, cand in enumerate(result['candidates'], 1):
                print(f"  {i}. {cand['start_time']} - {cand['title']}")

    # Exit code based on confidence
    exit_codes = {
        'high_confidence': 0,
        'medium_confidence': 0,
        'manual_review_needed': 1,
        'no_match': 2
    }

    sys.exit(exit_codes.get(result['confidence'], 2))


if __name__ == '__main__':
    main()
