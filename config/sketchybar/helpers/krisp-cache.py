#!/usr/bin/env python3
"""
Krisp Cache Management
Manages processed meetings and failed matches cache for Krisp transcript automation.

Author: Jeff Hamersly
Date: 2025-11-03
Story: 4-3 - AI Analysis & Note Integration
"""

import json
import os
import time
from pathlib import Path
from datetime import datetime
from dotenv import load_dotenv

# Load .env file
env_paths = [
    Path.home() / "repos/02_personal/dotfiles/.env",
    Path.home() / "dotfiles/.env",
    Path.home() / ".env",
]
for env_path in env_paths:
    if env_path.exists():
        load_dotenv(env_path)
        break

# Cache directory - use standard cache location, not Obsidian vault
CACHE_DIR = Path.home() / ".cache/sketchybar"
CACHE_FILE = CACHE_DIR / "krisp-updated-meeting-notes.json"

LOG_FILE = Path.home() / ".config/sketchybar/logs/krisp-automation.log"
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)


def log(message, level="INFO"):
    """Log message to file"""
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"[{timestamp}] [{level}] {message}"
    with open(LOG_FILE, "a") as f:
        f.write(log_line + "\n")


def load_cache():
    """
    Load cache from file or create new cache if file doesn't exist.

    Returns: Dict with processed_meetings, failed_matches, last_check
    """
    if not CACHE_FILE.exists():
        # Create directory if needed
        CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
        # Initialize with empty cache
        cache = {
            "last_check": None,
            "processed_meetings": [],
            "failed_matches": []
        }
        save_cache(cache)
        return cache

    try:
        with open(CACHE_FILE, 'r') as f:
            cache = json.load(f)

        # Ensure all required keys exist
        if 'processed_meetings' not in cache:
            cache['processed_meetings'] = []
        if 'failed_matches' not in cache:
            cache['failed_matches'] = []
        if 'last_check' not in cache:
            cache['last_check'] = None

        return cache
    except Exception as e:
        log(f"Failed to load cache: {str(e)}", "ERROR")
        # Return empty cache on error
        return {
            "last_check": None,
            "processed_meetings": [],
            "failed_matches": []
        }


def save_cache(cache):
    """
    Save cache to file atomically.

    Args:
        cache: Dict with processed_meetings, failed_matches, last_check

    Returns: True on success, False on failure
    """
    try:
        # Ensure directory exists
        CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)

        # Write to temp file first (atomic operation)
        temp_file = CACHE_FILE.with_suffix('.tmp')
        with open(temp_file, 'w') as f:
            json.dump(cache, f, indent=2)

        # Rename to actual file (atomic on Unix)
        temp_file.replace(CACHE_FILE)

        return True
    except Exception as e:
        log(f"Failed to save cache: {str(e)}", "ERROR")
        return False


def add_processed_meeting(meeting_id, metadata=None):
    """
    Add a successfully processed meeting to the cache.

    Args:
        meeting_id: Unique meeting ID from Krisp
        metadata: Optional dict with additional info (date, person, company, etc.)

    Returns: True on success, False on failure
    """
    try:
        cache = load_cache()

        # Check if already processed
        if meeting_id in cache['processed_meetings']:
            log(f"Meeting {meeting_id} already in processed list", "WARN")
            return True

        # Add to processed list
        entry = {
            "meeting_id": meeting_id,
            "processed_at": datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        }

        if metadata:
            entry.update(metadata)

        cache['processed_meetings'].append(entry)
        cache['last_check'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

        return save_cache(cache)

    except Exception as e:
        log(f"Failed to add processed meeting: {str(e)}", "ERROR")
        return False


def add_failed_match(meeting_id, reason, metadata=None):
    """
    Add a failed meeting match to the cache (AC #7).

    Args:
        meeting_id: Unique meeting ID from Krisp
        reason: Failure reason ('no_calendar_match', 'person_not_found', 'ai_failure', etc.)
        metadata: Optional dict with additional context (transcript_path, date, error, etc.)

    Returns: True on success, False on failure
    """
    try:
        cache = load_cache()

        # Check if already in failed matches
        existing = next((m for m in cache['failed_matches'] if m.get('meeting_id') == meeting_id), None)
        if existing:
            log(f"Meeting {meeting_id} already in failed matches", "WARN")
            return True

        # Build failed match entry
        entry = {
            "meeting_id": meeting_id,
            "reason": reason,
            "failed_at": datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        }

        if metadata:
            entry.update(metadata)

        # Add to failed matches
        cache['failed_matches'].append(entry)
        cache['last_check'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

        # Log the failed match
        log(f"Failed match: {meeting_id} - Reason: {reason}", "WARN")
        if metadata:
            log(f"  Metadata: {json.dumps(metadata)}", "WARN")

        return save_cache(cache)

    except Exception as e:
        log(f"Failed to add failed match: {str(e)}", "ERROR")
        return False


def is_processed(meeting_id):
    """
    Check if a meeting has already been processed.

    Args:
        meeting_id: Unique meeting ID from Krisp

    Returns: True if processed, False otherwise
    """
    cache = load_cache()
    return meeting_id in [m.get('meeting_id') for m in cache['processed_meetings']]


def is_failed(meeting_id):
    """
    Check if a meeting is in the failed matches list.

    Args:
        meeting_id: Unique meeting ID from Krisp

    Returns: True if in failed matches, False otherwise
    """
    cache = load_cache()
    return meeting_id in [m.get('meeting_id') for m in cache['failed_matches']]


def get_failed_matches_summary():
    """
    Get summary of failed matches for daily reports.

    Returns: String like "3 failed matches (see cache for details)"
    """
    cache = load_cache()
    failed_count = len(cache['failed_matches'])

    if failed_count == 0:
        return "No failed matches"
    else:
        return f"{failed_count} failed match{'es' if failed_count != 1 else ''} (see cache for details)"


if __name__ == '__main__':
    # Test the module
    print(f"Cache file: {CACHE_FILE}")
    print(f"Cache exists: {CACHE_FILE.exists()}")

    cache = load_cache()
    print(f"\nCache contents:")
    print(json.dumps(cache, indent=2))

    print(f"\nFailed matches summary: {get_failed_matches_summary()}")
