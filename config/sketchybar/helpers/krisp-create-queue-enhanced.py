#!/usr/bin/env python3
"""
Enhanced Queue Creator with Calendar Matching
Creates processing queue with full meeting classification using calendar data

This script bridges the gap between Krisp downloads and note processing by:
1. Finding all downloaded transcripts
2. Matching them to calendar events for proper classification
3. Creating a queue file with complete metadata for processing

Author: Claude (completing John's work)
Date: 2025-11-10
"""

import json
import re
import subprocess
import sys
from pathlib import Path
from datetime import datetime, timedelta
from dateutil import parser as date_parser

# Configuration
CACHE_DIR = Path.home() / ".cache/sketchybar"
PENDING_QUEUE_FILE = CACHE_DIR / "krisp-pending-downloads.json"
TRANSCRIPTS_DIR = Path.home() / ".config/sketchybar/krisp-transcripts"
HELPERS_DIR = Path(__file__).parent
VENV_PYTHON = HELPERS_DIR.parent / "venv/bin/python3"
LOG_FILE = Path.home() / ".config/sketchybar/logs/krisp-queue-enhanced.log"

CACHE_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)


def log(message, level="INFO"):
    """Log message with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"[{timestamp}] [{level}] {message}"
    print(log_line)
    with open(LOG_FILE, "a") as f:
        f.write(log_line + "\n")


def parse_krisp_date(title):
    """
    Parse date and time from Krisp title format
    Examples:
      "04:30 PM - Slack meeting November 4" → ("2025-11-04", "04:30 PM")
      "11:30 AM - Discord meeting October 31" → ("2025-10-31", "11:30 AM")
    """
    try:
        # Extract time from beginning
        time_match = re.match(r'(\d{1,2}:\d{2}\s+[AP]M)\s*-', title)
        time_str = time_match.group(1) if time_match else None

        # Extract date portion
        date_match = re.search(r'-\s+.+?meeting\s+(.+)$', title)
        if date_match:
            date_str = date_match.group(1).strip()

            # Parse with dateutil
            parsed = date_parser.parse(date_str, fuzzy=True)

            # Handle year wrapping
            now = datetime.now()
            if parsed.month > now.month or (parsed.month == now.month and parsed.day > now.day):
                parsed = parsed.replace(year=now.year - 1)
            else:
                parsed = parsed.replace(year=now.year)

            return parsed.strftime("%Y-%m-%d"), time_str
    except Exception as e:
        log(f"Failed to parse date from '{title}': {e}", "WARN")

    return None, None


def call_calendar_matching(title, date, time_str=None):
    """
    Call krisp-match-meetings.py to get calendar-based classification

    Returns: Dict with meeting_type, company, participant, person_folder, etc.
    """
    try:
        # Extract year from date
        year = date.split('-')[0] if date else str(datetime.now().year)

        # Build command using unified classifier
        cmd = [
            str(VENV_PYTHON),
            str(HELPERS_DIR / "classify-meeting-unified.py"),
            "--title", title,
            "--date", date if date else "",
            "--time", time_str if time_str else ""
        ]

        log(f"Calling calendar matching: {' '.join(cmd)}")

        # Execute calendar matching
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode == 0 and result.stdout:
            # Parse JSON output
            match_data = json.loads(result.stdout)
            log(f"Calendar match successful: {match_data.get('meeting_type', 'unknown')}")
            return match_data
        else:
            log(f"Calendar matching failed: {result.stderr}", "WARN")
            return None

    except subprocess.TimeoutExpired:
        log("Calendar matching timed out", "ERROR")
    except json.JSONDecodeError as e:
        log(f"Failed to parse calendar match output: {e}", "ERROR")
    except Exception as e:
        log(f"Calendar matching error: {e}", "ERROR")

    return None


def extract_meeting_id(transcript_path):
    """Extract meeting ID from transcript filename"""
    filename = transcript_path.name
    meeting_id = filename.replace("krisp-transcript-", "").replace(".txt", "")
    return meeting_id


def get_transcript_metadata(transcript_path):
    """
    Get complete metadata for a transcript including calendar matching

    Returns: Dict with all metadata needed for processing
    """
    meeting_id = extract_meeting_id(transcript_path)

    # Try to read companion metadata file
    metadata_path = transcript_path.parent / f"krisp-transcript-{meeting_id}.json"

    if metadata_path.exists():
        try:
            krisp_meta = json.loads(metadata_path.read_text())
            title = krisp_meta.get('title', 'Unknown Meeting')
        except:
            title = 'Unknown Meeting'
            krisp_meta = {}
    else:
        title = 'Unknown Meeting'
        krisp_meta = {}

    log(f"Processing: {title}")

    # Parse date and time from Krisp title
    date, time_str = parse_krisp_date(title)

    if not date:
        # Fallback to download timestamp or file mtime
        if krisp_meta.get('downloaded_at'):
            dt = datetime.fromisoformat(krisp_meta['downloaded_at'].replace('Z', '+00:00'))
            date = dt.strftime("%Y-%m-%d")
            time_str = dt.strftime("%I:%M %p")
        else:
            mtime = transcript_path.stat().st_mtime
            dt = datetime.fromtimestamp(mtime)
            date = dt.strftime("%Y-%m-%d")
            time_str = dt.strftime("%I:%M %p")

    # Get calendar-based classification
    calendar_match = call_calendar_matching(title, date, time_str)

    # Build complete metadata
    metadata = {
        'id': meeting_id,
        'title': title,  # Original Krisp title
        'date': date,
        'time': time_str,
        'date_text': f"{date} {time_str}" if time_str else date,
        'transcript_path': str(transcript_path),
        'platform': extract_platform(title)
    }

    # Add calendar match data if available
    if calendar_match:
        metadata.update({
            'calendar_title': calendar_match.get('meeting_title'),
            'meeting_type': calendar_match.get('meeting_type'),
            'company': calendar_match.get('company'),
            'participant': calendar_match.get('participant'),
            'person_folder': calendar_match.get('person_folder'),
            'confidence': calendar_match.get('confidence', 0)
        })
    else:
        # Fallback classification from title alone
        metadata.update({
            'meeting_type': 'unknown',
            'company': 'unknown',
            'participant': extract_participant_from_title(title)
        })

    return metadata


def extract_platform(title):
    """Extract platform from title (Slack, Discord, etc.)"""
    title_lower = title.lower()
    if 'slack' in title_lower:
        return 'slack'
    elif 'discord' in title_lower:
        return 'discord'
    elif 'zoom' in title_lower:
        return 'zoom'
    elif 'teams' in title_lower:
        return 'teams'
    return 'unknown'


def extract_participant_from_title(title):
    """Fallback: try to extract participant name from title"""
    # This is a weak heuristic - calendar matching is much better
    # But useful for debugging
    patterns = [
        r'1:1 with (\w+)',
        r'1on1 with (\w+)',
        r'meeting with (\w+)',
        r'call with (\w+)'
    ]

    for pattern in patterns:
        match = re.search(pattern, title, re.IGNORECASE)
        if match:
            return match.group(1)

    return None


def main():
    log("=== Enhanced Queue Creator Starting ===")

    # Find all downloaded transcripts
    transcripts = list(TRANSCRIPTS_DIR.glob("krisp-transcript-*.txt"))
    log(f"Found {len(transcripts)} transcript files")

    if not transcripts:
        log("No transcripts to process", "WARN")
        # Create empty queue file
        queue_data = {
            'created_at': datetime.now().isoformat(),
            'total': 0,
            'meetings': []
        }
        PENDING_QUEUE_FILE.write_text(json.dumps(queue_data, indent=2))
        sys.exit(0)

    # Process each transcript to get metadata
    meetings = []
    stats = {
        'calendar_matched': 0,
        'one_on_one': 0,
        'company_meetings': 0,
        'unknown': 0
    }

    for transcript_path in transcripts:
        log(f"\nProcessing transcript: {transcript_path.name}")
        metadata = get_transcript_metadata(transcript_path)
        meetings.append(metadata)

        # Update stats
        if metadata.get('person_folder'):
            stats['calendar_matched'] += 1

        meeting_type = metadata.get('meeting_type', 'unknown')
        if meeting_type == 'one-on-one':
            stats['one_on_one'] += 1
        elif meeting_type in ['company', 'team']:
            stats['company_meetings'] += 1
        else:
            stats['unknown'] += 1

        log(f"  → Type: {meeting_type}, Company: {metadata.get('company', 'unknown')}, "
            f"Participant: {metadata.get('participant', 'unknown')}")

    # Sort by date (oldest first)
    meetings.sort(key=lambda m: m.get('date', '9999-99-99'))

    # Create queue file
    queue_data = {
        'created_at': datetime.now().isoformat(),
        'total': len(meetings),
        'stats': stats,
        'meetings': meetings
    }

    PENDING_QUEUE_FILE.write_text(json.dumps(queue_data, indent=2))
    log(f"\n✓ Created queue file: {PENDING_QUEUE_FILE}")

    # Summary
    log("\n=== Summary ===")
    log(f"Total meetings: {len(meetings)}")
    log(f"Calendar matched: {stats['calendar_matched']}")
    log(f"1-on-1 meetings: {stats['one_on_one']}")
    log(f"Company meetings: {stats['company_meetings']}")
    log(f"Unknown type: {stats['unknown']}")

    # List any unmatched meetings
    unmatched = [m for m in meetings if m.get('meeting_type') == 'unknown']
    if unmatched:
        log("\n⚠ Unmatched meetings (need calendar entries):")
        for m in unmatched[:5]:  # Show first 5
            log(f"  - {m['title']}")
        if len(unmatched) > 5:
            log(f"  ... and {len(unmatched) - 5} more")

    return 0


if __name__ == "__main__":
    sys.exit(main())