#!/usr/bin/env python3
"""
Create processing queue from downloaded transcripts
Bridges simplified download script with batch processor

Author: Claude
Date: 2025-11-05
"""

import json
import re
from pathlib import Path
from datetime import datetime
from dateutil import parser as date_parser

# Configuration
CACHE_DIR = Path.home() / ".cache/sketchybar"
PENDING_QUEUE_FILE = CACHE_DIR / "krisp-pending-downloads.json"
TRANSCRIPTS_DIR = Path.home() / ".config/sketchybar/krisp-transcripts"

CACHE_DIR.mkdir(parents=True, exist_ok=True)

def parse_krisp_date(title):
    """
    Parse date from Krisp title format
    Examples:
      "04:30 PM - Slack meeting November 4" → "2025-11-04"
      "11:30 AM - Discord meeting October 31" → "2025-10-31"

    Returns: (date_str, time_str) tuple or (None, None) if parsing fails
    """
    try:
        # Extract time from beginning (e.g., "04:30 PM")
        time_match = re.match(r'(\d{1,2}:\d{2}\s+[AP]M)\s*-', title)
        time_str = time_match.group(1) if time_match else None

        # Extract date portion (after " - " and the word "meeting")
        # Pattern: "HH:MM AM/PM - Platform meeting Month Day"
        date_match = re.search(r'-\s+.+?meeting\s+(.+)$', title)
        if date_match:
            date_str = date_match.group(1).strip()

            # Parse with dateutil (handles "November 4", "Oct 31", etc.)
            parsed = date_parser.parse(date_str, fuzzy=True)

            # Handle year wrapping: if parsed date is in future, assume previous year
            now = datetime.now()
            if parsed.month > now.month or (parsed.month == now.month and parsed.day > now.day):
                parsed = parsed.replace(year=now.year - 1)
            else:
                parsed = parsed.replace(year=now.year)

            return parsed.strftime("%Y-%m-%d"), time_str
    except Exception as e:
        print(f"Warning: Failed to parse date from title '{title}': {e}")

    return None, None

def extract_meeting_id(transcript_path):
    """Extract meeting ID from transcript filename"""
    filename = transcript_path.name
    meeting_id = filename.replace("krisp-transcript-", "").replace(".txt", "")
    return meeting_id

def parse_transcript_for_metadata(transcript_path):
    """
    Parse transcript file to extract basic metadata
    First tries to read companion .json metadata file, falls back to parsing transcript
    Returns: dict with date_text, title from Krisp
    """
    # Try to read metadata JSON file first
    meeting_id = extract_meeting_id(transcript_path)
    metadata_path = transcript_path.parent / f"krisp-transcript-{meeting_id}.json"

    if metadata_path.exists():
        try:
            metadata = json.loads(metadata_path.read_text())
            title = metadata.get('title', 'Unknown Meeting')

            # Try to parse date from Krisp title first (e.g., "04:30 PM - Slack meeting November 4")
            date, time_str = parse_krisp_date(title)

            if date:
                # Successfully parsed from title
                if time_str:
                    date_text = f"{date} {time_str}"
                else:
                    date_text = f"{date} 00:00"
            else:
                # Fallback to downloaded_at timestamp
                downloaded_at = metadata.get('downloaded_at')
                if downloaded_at:
                    dt = datetime.fromisoformat(downloaded_at.replace('Z', '+00:00'))
                    date = dt.strftime("%Y-%m-%d")
                    date_text = dt.strftime("%Y-%m-%d %H:%M")
                else:
                    # Last resort: file modification time
                    mtime = transcript_path.stat().st_mtime
                    date = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d")
                    date_text = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")

            return {
                'date': date,
                'date_text': date_text,
                'title': title
            }
        except Exception as e:
            print(f"Warning: Failed to parse metadata file: {e}")
            # Fall through to fallback

    # Fallback: Use file modification time
    try:
        mtime = transcript_path.stat().st_mtime
        date = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d")
        date_text = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")

        return {
            'date': date,
            'date_text': date_text,
            'title': 'Unknown Meeting'
        }
    except Exception as e:
        return {
            'date': '9999-12-31',
            'date_text': 'Unknown',
            'title': 'Unknown Meeting'
        }

def main():
    """Create queue file from downloaded transcripts"""
    transcripts = list(TRANSCRIPTS_DIR.glob("krisp-transcript-*.txt"))

    if not transcripts:
        print("No transcripts found")
        return

    meetings = []
    for transcript_path in transcripts:
        meeting_id = extract_meeting_id(transcript_path)
        metadata = parse_transcript_for_metadata(transcript_path)

        meetings.append({
            'id': meeting_id,
            'date': metadata['date'],
            'date_text': metadata['date_text'],
            'title': metadata['title'],
            'status': 'downloaded',
            'transcript_path': str(transcript_path)
        })

    # Sort by date
    meetings.sort(key=lambda x: x['date'])

    # Write queue file
    queue_data = {
        'meetings': meetings,
        'generated_at': datetime.now().isoformat(),
        'count': len(meetings)
    }

    PENDING_QUEUE_FILE.write_text(json.dumps(queue_data, indent=2))
    print(f"✓ Created queue file with {len(meetings)} meetings")
    print(f"  Saved to: {PENDING_QUEUE_FILE}")

if __name__ == "__main__":
    main()
