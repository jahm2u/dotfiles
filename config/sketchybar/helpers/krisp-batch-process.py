#!/usr/bin/env python3
"""
Krisp Batch Processor
Processes all downloaded transcripts in chronological order (oldest first).

Usage:
    python3 krisp-batch-process.py [--limit N] [--dry-run]

Author: Jeff Hamersly
Date: 2025-11-03
"""

import json
import sys
import subprocess
from pathlib import Path
from datetime import datetime

# Configuration
CACHE_DIR = Path.home() / ".cache/sketchybar"
PENDING_QUEUE_FILE = CACHE_DIR / "krisp-pending-downloads.json"
TRANSCRIPTS_DIR = Path.home() / ".config/sketchybar/krisp-transcripts"
LOG_FILE = Path.home() / ".config/sketchybar/logs/krisp-batch-process.log"
HELPERS_DIR = Path(__file__).parent
VENV_PYTHON = HELPERS_DIR.parent / "venv/bin/python3"

LOG_FILE.parent.mkdir(parents=True, exist_ok=True)


def log(message, level="INFO"):
    """Log message with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"[{timestamp}] [{level}] {message}"
    print(log_line)
    with open(LOG_FILE, "a") as f:
        f.write(log_line + "\n")


def load_pending_queue():
    """Load pending queue metadata"""
    if not PENDING_QUEUE_FILE.exists():
        log("No pending queue file found", "ERROR")
        return []

    with open(PENDING_QUEUE_FILE) as f:
        data = json.load(f)

    return data.get('meetings', [])


def find_downloaded_transcripts():
    """Find all downloaded transcript files"""
    transcripts = list(TRANSCRIPTS_DIR.glob("krisp-transcript-*.txt"))
    log(f"Found {len(transcripts)} downloaded transcripts")
    return transcripts


def extract_meeting_id(transcript_path):
    """Extract meeting ID from transcript filename"""
    # Format: krisp-transcript-{meeting_id}.txt
    filename = transcript_path.name
    meeting_id = filename.replace("krisp-transcript-", "").replace(".txt", "")
    return meeting_id


def build_processing_queue(transcripts, queue_metadata):
    """
    Build processing queue sorted by date (oldest first).

    Args:
        transcripts: List of transcript file paths
        queue_metadata: List of meeting metadata from pending queue

    Returns: List of dicts with transcript_path, meeting_id, date, title
    """
    processing_queue = []

    # Create metadata lookup by meeting_id
    metadata_by_id = {m['id']: m for m in queue_metadata}

    for transcript_path in transcripts:
        meeting_id = extract_meeting_id(transcript_path)

        # Find metadata
        metadata = metadata_by_id.get(meeting_id)
        if not metadata:
            log(f"No metadata found for {meeting_id}, skipping", "WARN")
            continue

        processing_queue.append({
            'transcript_path': str(transcript_path),
            'meeting_id': meeting_id,
            'date': metadata.get('date', '9999-12-31'),  # Sort unknowns last
            'title': metadata.get('title', 'Unknown'),
            'date_text': metadata.get('date_text', 'Unknown')
        })

    # Sort by date (oldest first)
    processing_queue.sort(key=lambda x: x['date'])

    return processing_queue


def process_transcript(transcript_path, meeting_id):
    """
    Process a single transcript using krisp-process-transcript.py

    Returns: Dict with status, reason, and details
    """
    cmd = [
        str(VENV_PYTHON),
        str(HELPERS_DIR / "krisp-process-transcript.py"),
        "--transcript", transcript_path,
        "--meeting-id", meeting_id,
        "--json"
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=180  # 3 minutes per transcript (includes AI processing)
        )

        if result.returncode == 0:
            # Parse result
            output = json.loads(result.stdout)
            if output.get('success'):
                return {
                    'status': 'success',
                    'action': 'Note updated',
                    'details': output
                }
            elif output.get('skipped'):
                log(f"  Skipped (already processed or failed previously)", "INFO")
                return {
                    'status': 'skipped',
                    'reason': 'Already processed',
                    'details': output
                }
            else:
                errors = ', '.join(output.get('errors', ['unknown']))
                log(f"  Failed: {errors}", "ERROR")
                return {
                    'status': 'failed',
                    'reason': errors,
                    'details': output
                }
        else:
            log(f"  Process failed: {result.stderr}", "ERROR")
            return {
                'status': 'failed',
                'reason': 'Process error',
                'error': result.stderr
            }

    except subprocess.TimeoutExpired:
        log(f"  Timeout processing transcript", "ERROR")
        return {
            'status': 'failed',
            'reason': 'Timeout'
        }
    except Exception as e:
        log(f"  Error: {str(e)}", "ERROR")
        return {
            'status': 'failed',
            'reason': str(e)
        }


def main():
    import argparse

    parser = argparse.ArgumentParser(description='Batch process transcripts (oldest first)')
    parser.add_argument('--limit', type=int, help='Max transcripts to process')
    parser.add_argument('--dry-run', action='store_true', help='Preview without processing')
    parser.add_argument('--start-from', type=int, default=0, help='Skip first N transcripts')

    args = parser.parse_args()

    log("=== KRISP BATCH PROCESSOR ===")

    # Load pending queue metadata
    queue_metadata = load_pending_queue()
    if not queue_metadata:
        log("No metadata available", "ERROR")
        sys.exit(1)

    # Find downloaded transcripts
    transcripts = find_downloaded_transcripts()
    if not transcripts:
        log("No transcripts to process", "WARN")
        sys.exit(0)

    # Build processing queue (sorted oldest → newest)
    processing_queue = build_processing_queue(transcripts, queue_metadata)

    # Apply start_from and limit
    processing_queue = processing_queue[args.start_from:]
    if args.limit:
        processing_queue = processing_queue[:args.limit]

    total = len(processing_queue)
    log(f"Processing queue: {total} transcripts (oldest → newest)")

    if total == 0:
        log("No transcripts to process after filtering", "WARN")
        sys.exit(0)

    # Dry run mode
    if args.dry_run:
        log("=== DRY RUN MODE ===")
        for i, item in enumerate(processing_queue, 1):
            print(f"{i}. [{item['date']}] {item['title']}")
        log(f"Would process {total} transcripts")
        sys.exit(0)

    # Process transcripts
    stats = {'success': 0, 'failed': 0, 'skipped': 0, 'details': []}

    for i, item in enumerate(processing_queue, 1):
        log(f"\n[{i}/{total}] Processing: [{item['date']}] {item['title']}")

        result = process_transcript(item['transcript_path'], item['meeting_id'])

        # Collect detailed result
        detail = {
            'title': item['title'],
            'date': item['date'],
            'date_text': item.get('date_text', item['date']),
            'status': result['status'],
            'meeting_id': item['meeting_id']
        }

        if result['status'] == 'success':
            stats['success'] += 1
            detail['action'] = result.get('action', 'Note updated')
            log(f"  ✓ Success ({stats['success']}/{total})")
        elif result['status'] == 'skipped':
            stats['skipped'] += 1
            detail['reason'] = result.get('reason', 'Already processed')
            log(f"  ⊘ Skipped ({stats['skipped']}/{total})")
        else:  # failed
            stats['failed'] += 1
            detail['reason'] = result.get('reason', 'Unknown error')
            log(f"  ✗ Failed ({stats['failed']}/{total})")

        stats['details'].append(detail)

    log(f"\n=== BATCH PROCESSING COMPLETE ===")
    log(f"Success: {stats['success']}")
    log(f"Failed: {stats['failed']}")
    log(f"Skipped: {stats['skipped']}")

    # Output JSON for programmatic use
    print(json.dumps(stats, indent=2))

    sys.exit(0 if stats['failed'] == 0 else 1)


if __name__ == '__main__':
    main()
