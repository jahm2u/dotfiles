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


def log(message, level="INFO", context=None, exc_info=None):
    """
    Enhanced logging with context and exception support (matching krisp-process-transcript.py).

    Args:
        message: Log message
        level: Log level (INFO, WARN, ERROR, DEBUG)
        context: Dict with contextual metadata (queue_pos, meeting_id, transcript, etc.)
        exc_info: Exception object for full traceback logging
    """
    import traceback
    import sys

    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # Build context string
    ctx_str = ""
    if context:
        ctx_items = [f"{k}={v}" for k, v in context.items()]
        ctx_str = f" [{', '.join(ctx_items)}]"

    log_line = f"[{timestamp}] [{level}]{ctx_str} {message}"

    # Console output (INFO and WARN to stdout, ERROR to stderr)
    if level in ["ERROR"]:
        print(log_line, file=sys.stderr)
    else:
        print(log_line)

    # File output with exception details
    with open(LOG_FILE, "a") as f:
        f.write(log_line + "\n")

        # Log exception traceback to file only
        if exc_info:
            f.write(f"[{timestamp}] [ERROR] Exception: {type(exc_info).__name__}: {str(exc_info)}\n")
            tb_lines = traceback.format_exception(type(exc_info), exc_info, exc_info.__traceback__)
            for tb_line in tb_lines:
                f.write(f"[{timestamp}] [ERROR] {tb_line}")
                if not tb_line.endswith('\n'):
                    f.write('\n')


def load_pending_queue():
    """Load pending queue metadata"""
    ctx = {"function": "load_pending_queue", "queue_file": str(PENDING_QUEUE_FILE)}

    if not PENDING_QUEUE_FILE.exists():
        log("Pending queue file not found", "ERROR", context=ctx)
        return []

    try:
        log(f"Loading pending queue: {PENDING_QUEUE_FILE}", "DEBUG", context=ctx)
        with open(PENDING_QUEUE_FILE) as f:
            data = json.load(f)

        meetings = data.get('meetings', [])
        log(f"Loaded {len(meetings)} meetings from queue", "DEBUG", context=ctx)
        return meetings

    except json.JSONDecodeError as e:
        log(f"Invalid JSON in pending queue file", "ERROR", exc_info=e, context=ctx)
        return []
    except Exception as e:
        log(f"Failed to load pending queue", "ERROR", exc_info=e, context=ctx)
        return []


def find_downloaded_transcripts():
    """Find all downloaded transcript files"""
    ctx = {"function": "find_downloaded_transcripts", "transcripts_dir": str(TRANSCRIPTS_DIR)}

    log(f"Scanning transcripts directory", "DEBUG", context=ctx)

    try:
        transcripts = list(TRANSCRIPTS_DIR.glob("krisp-transcript-*.txt"))
        log(f"Found {len(transcripts)} downloaded transcripts", "INFO", context=ctx)
        return transcripts
    except Exception as e:
        log(f"Failed to scan transcripts directory", "ERROR", exc_info=e, context=ctx)
        return []


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
    ctx = {"function": "build_processing_queue", "transcripts_count": len(transcripts), "metadata_count": len(queue_metadata)}

    log(f"Building processing queue from {len(transcripts)} transcripts", "DEBUG", context=ctx)

    processing_queue = []

    # Create metadata lookup by meeting_id
    metadata_by_id = {m['id']: m for m in queue_metadata}
    log(f"Created metadata lookup for {len(metadata_by_id)} meetings", "DEBUG", context=ctx)

    skipped_count = 0
    for transcript_path in transcripts:
        meeting_id = extract_meeting_id(transcript_path)

        # Find metadata
        metadata = metadata_by_id.get(meeting_id)
        if not metadata:
            skipped_count += 1
            log(f"No metadata found for {meeting_id}, skipping", "WARN", context={"meeting_id": meeting_id, "transcript": str(transcript_path)})
            continue

        processing_queue.append({
            'transcript_path': str(transcript_path),
            'meeting_id': meeting_id,
            'date': metadata.get('date') or '9999-12-31',  # Sort unknowns last
            'title': metadata.get('title', 'Unknown'),
            'date_text': metadata.get('date_text', 'Unknown')
        })

    # Sort by date (oldest first)
    processing_queue.sort(key=lambda x: x['date'])

    log(f"Built queue: {len(processing_queue)} meetings (skipped {skipped_count} without metadata)", "INFO", context=ctx)

    return processing_queue


def process_transcript(transcript_path, meeting_id):
    """
    Process a single transcript using krisp-process-transcript.py

    Returns: Dict with status, reason, and details
    """
    ctx = {
        "function": "process_transcript",
        "meeting_id": meeting_id,
        "transcript": transcript_path
    }

    log(f"Invoking krisp-process-transcript.py", "DEBUG", context=ctx)

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

        log(f"Process completed with exit code: {result.returncode}", "DEBUG", context=ctx)

        if result.returncode == 0:
            # Parse result
            try:
                output = json.loads(result.stdout)
            except json.JSONDecodeError as e:
                log(f"Invalid JSON from process: {result.stdout[:500]}", "ERROR", exc_info=e, context=ctx)
                return {
                    'status': 'failed',
                    'reason': 'Invalid JSON output',
                    'error': str(e)
                }

            if output.get('success'):
                action = output.get('action', 'Note updated')
                log(f"✓ {action}", "INFO", context=ctx)
                return {
                    'status': 'success',
                    'action': action,
                    'note_path': output.get('note_path', ''),
                    'details': output
                }
            elif output.get('skipped'):
                reason = output.get('reason', 'Already processed')
                log(f"⊘ Skipped: {reason}", "INFO", context=ctx)
                return {
                    'status': 'skipped',
                    'reason': reason,
                    'details': output
                }
            else:
                errors = ', '.join(output.get('errors', ['unknown']))
                log(f"✗ Failed: {errors}", "ERROR", context=ctx)
                return {
                    'status': 'failed',
                    'reason': errors,
                    'details': output
                }
        else:
            log(f"Process returned non-zero exit: {result.stderr[:500]}", "ERROR", context=ctx)
            return {
                'status': 'failed',
                'reason': 'Process error',
                'error': result.stderr[:500]
            }

    except subprocess.TimeoutExpired:
        log(f"Process timed out (>180s)", "ERROR", context=ctx)
        return {
            'status': 'failed',
            'reason': 'Timeout (>180s)'
        }
    except Exception as e:
        log(f"Process failed unexpectedly", "ERROR", exc_info=e, context=ctx)
        return {
            'status': 'failed',
            'reason': f"Unexpected error: {str(e)}"
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

    log(f"Starting batch processing: {total} meetings", "INFO")

    for i, item in enumerate(processing_queue, 1):
        ctx = {
            "queue_pos": f"{i}/{total}",
            "meeting_id": item['meeting_id'],
            "date": item['date'],
            "title": item['title'][:50]  # Truncate for logging
        }

        log(f"Processing meeting: [{item['date']}] {item['title']}", "INFO", context=ctx)

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
            detail['note_path'] = result.get('note_path', '')
            log(f"✓ Success: {detail['action']} ({stats['success']}/{total})", "INFO", context=ctx)
        elif result['status'] == 'skipped':
            stats['skipped'] += 1
            detail['reason'] = result.get('reason', 'Already processed')
            log(f"⊘ Skipped: {detail['reason']} ({stats['skipped']}/{total})", "INFO", context=ctx)
        else:  # failed
            stats['failed'] += 1
            detail['reason'] = result.get('reason', 'Unknown error')
            log(f"✗ Failed: {detail['reason']} ({stats['failed']}/{total})", "ERROR", context=ctx)

        stats['details'].append(detail)

    # Summary with context
    summary_ctx = {
        "total": total,
        "success": stats['success'],
        "failed": stats['failed'],
        "skipped": stats['skipped']
    }

    log(f"=== BATCH PROCESSING COMPLETE ===", "INFO", context=summary_ctx)
    log(f"Results: {stats['success']} succeeded, {stats['failed']} failed, {stats['skipped']} skipped", "INFO", context=summary_ctx)

    # Output JSON for programmatic use
    print(json.dumps(stats, indent=2))

    sys.exit(0 if stats['failed'] == 0 else 1)


if __name__ == '__main__':
    main()
