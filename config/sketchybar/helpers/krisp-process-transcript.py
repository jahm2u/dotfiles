#!/usr/bin/env python3
"""
Krisp Transcript Processor
Main orchestration script that processes a single transcript through the full pipeline:
1. Match transcript to calendar event
2. Classify meeting type
3. Find person folder
4. Analyze transcript with AI
5. Update Obsidian note
6. Organize transcript file

Implements graceful degradation per AC #8.

Author: Jeff Hamersly
Date: 2025-11-03
Story: 4-3 - AI Analysis & Note Integration
"""

import argparse
import json
import sys
import os
import subprocess
import time
from pathlib import Path
from datetime import datetime
from dotenv import load_dotenv

# Load .env file
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

# Configuration
LOG_FILE = Path.home() / ".config/sketchybar/logs/krisp-automation.log"
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

HELPERS_DIR = Path(__file__).parent
VENV_PYTHON = HELPERS_DIR.parent / "venv/bin/python3"


def log(message, level="INFO"):
    """Log message to file and stderr"""
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"[{timestamp}] [{level}] {message}"
    print(log_line, file=sys.stderr)
    with open(LOG_FILE, "a") as f:
        f.write(log_line + "\n")


def load_cache_module():
    """Load cache module functions"""
    import importlib.util
    spec = importlib.util.spec_from_file_location("krisp_cache", HELPERS_DIR / "krisp-cache.py")
    cache = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cache)
    return cache


def process_transcript(transcript_path, meeting_id):
    """
    Process a single transcript through the full pipeline with graceful degradation (AC #8).

    Args:
        transcript_path: Path to transcript file
        meeting_id: Unique Krisp meeting ID

    Returns: Dict with success boolean and details
    """
    result = {
        "success": False,
        "meeting_id": meeting_id,
        "transcript_path": str(transcript_path),
        "errors": [],
        "stages_completed": []
    }

    cache = load_cache_module()

    # Check if already processed
    if cache.is_processed(meeting_id):
        log(f"Meeting {meeting_id} already processed, skipping", "INFO")
        result["success"] = True
        result["skipped"] = True
        return result

    # Check if in failed matches
    if cache.is_failed(meeting_id):
        log(f"Meeting {meeting_id} previously failed, skipping", "WARN")
        result["skipped"] = True
        return result

    try:
        # Stage 1: Load meeting metadata from pending downloads
        log(f"Processing transcript: {transcript_path}", "INFO")

        # Load metadata from krisp-pending-downloads.json
        pending_file = Path.home() / ".cache/sketchybar/krisp-pending-downloads.json"
        if not pending_file.exists():
            log("Pending downloads file not found", "ERROR")
            cache.add_failed_match(meeting_id, "metadata_not_found", {"transcript_path": str(transcript_path)})
            result["errors"].append("metadata_not_found")
            return result

        with open(pending_file, 'r') as f:
            pending_data = json.load(f)

        # Find meeting metadata by ID
        meeting_meta = next((m for m in pending_data.get('meetings', []) if m['id'] == meeting_id), None)
        if not meeting_meta:
            log(f"Meeting metadata not found for ID: {meeting_id}", "ERROR")
            cache.add_failed_match(meeting_id, "metadata_not_found", {"transcript_path": str(transcript_path)})
            result["errors"].append("metadata_not_found")
            return result

        log(f"Found metadata: {meeting_meta['title']}", "INFO")

        # Stage 2: Match to calendar event (AC #1)
        log("Stage 1: Matching to calendar event...", "INFO")
        match_cmd = [
            str(VENV_PYTHON),
            str(HELPERS_DIR / "krisp-match-meetings.py"),
            "--title", meeting_meta['title'],
            "--year", meeting_meta['date'].split('-')[0],
            "--json"
        ]

        try:
            match_result = subprocess.run(
                match_cmd,
                capture_output=True,
                text=True,
                timeout=180  # 3 minutes for large calendar databases (8000+ events)
            )

            if match_result.returncode != 0:
                raise Exception(f"Calendar matching failed: {match_result.stderr}")

            calendar_match = json.loads(match_result.stdout)

        except Exception as e:
            log(f"Calendar matching error: {str(e)}", "ERROR")
            cache.add_failed_match(meeting_id, "calendar_match_error", {"transcript_path": str(transcript_path), "error": str(e)})
            result["errors"].append(f"calendar_match_error: {str(e)}")
            return result

        if calendar_match.get("confidence") == "no_match":
            # AC #7: Failed match handling
            log("No calendar match found", "WARN")
            cache.add_failed_match(
                meeting_id,
                "no_calendar_match",
                {"transcript_path": str(transcript_path), "date": calendar_match.get("krisp_date")}
            )
            result["errors"].append("no_calendar_match")
            return result

        result["stages_completed"].append("calendar_match")

        # Extract event data from match result
        matched_event = calendar_match.get("event", {})
        event_title = matched_event.get("title", "Unknown")
        # Use the date from the Krisp metadata
        event_date = meeting_meta.get("date", "")

        # Stage 3: Classify meeting (AC #2)
        log("Stage 2: Classifying meeting type...", "INFO")
        classify_cmd = [
            str(VENV_PYTHON),
            str(HELPERS_DIR / "classify-meeting.py"),
            "--title", event_title,
            "--date", event_date,
            "--participants", ""  # No participant data from khal
        ]

        try:
            classify_result = subprocess.run(
                classify_cmd,
                capture_output=True,
                text=True,
                timeout=10
            )

            if classify_result.returncode != 0:
                raise Exception(f"Classification failed: {classify_result.stderr}")

            classification = json.loads(classify_result.stdout)
            result["stages_completed"].append("classification")

        except Exception as e:
            # AC #8: Classification failure → skip with error log
            log(f"Classification error: {str(e)}", "ERROR")
            cache.add_failed_match(
                meeting_id,
                "classification_failed",
                {"transcript_path": str(transcript_path), "error": str(e)}
            )
            result["errors"].append(f"classification_failed: {str(e)}")
            return result

        # Stage 4: Find person folder (AC #3)
        log("Stage 3: Finding person folder...", "INFO")
        find_cmd = [
            "bash",
            str(HELPERS_DIR / "find-person-folder.sh"),
            "--person", classification.get("participant", "Unknown"),
            "--company", classification.get("company", "Unknown")
        ]

        try:
            find_result = subprocess.run(
                find_cmd,
                capture_output=True,
                text=True,
                timeout=10
            )

            if find_result.returncode != 0:
                # AC #8: Person not found → skip with error log
                log(f"Person not found: {classification.get('participant')}", "ERROR")
                cache.add_failed_match(
                    meeting_id,
                    "person_not_found",
                    {
                        "transcript_path": str(transcript_path),
                        "person": classification.get("participant"),
                        "company": classification.get("company")
                    }
                )
                result["errors"].append("person_not_found")
                return result

            person_folder = find_result.stdout.strip()
            result["stages_completed"].append("person_folder")

        except subprocess.TimeoutExpired:
            log("Person folder search timed out", "ERROR")
            cache.add_failed_match(meeting_id, "person_search_timeout", {"transcript_path": str(transcript_path)})
            result["errors"].append("person_search_timeout")
            return result

        # Stage 5: Find or create meeting note
        log("Stage 4: Locating meeting note...", "INFO")
        meetings_folder = Path(person_folder) / "Meetings"
        note_date = event_date  # Use event_date extracted earlier from calendar match
        person_name = classification.get("participant", "Unknown")
        note_filename = f"{note_date} 1on1 with {person_name}.md"
        note_path = meetings_folder / note_filename

        if not note_path.exists():
            # AC #8: Missing note → create from template, continue processing
            log(f"Note not found, creating from template: {note_path}", "WARN")

            # Create simple 1on1 template
            meetings_folder.mkdir(parents=True, exist_ok=True)
            template = f"""# {note_date} 1on1 with {person_name}

**Date:** {note_date}
**Participants:** {person_name}, Jeff Hamersly
**Company:** {classification.get('company', 'Unknown')}
**Meeting Type:** {classification.get('meeting_type', '1on1')}

## 📝 Post-Meeting Summary
*Auto-generated from transcript analysis*

### 🎯 Discussion Highlights

### ✅ Action Items Captured

### 💡 Topics to Review Next Time

### 🔗 Related Context

"""
            try:
                note_path.write_text(template)
                log(f"✓ Created note from template: {note_path}", "INFO")
            except Exception as e:
                log(f"Failed to create note: {str(e)}", "ERROR")
                cache.add_failed_match(meeting_id, "note_creation_failed", {"transcript_path": str(transcript_path), "error": str(e)})
                result["errors"].append("note_creation_failed")
                return result

        result["stages_completed"].append("note_found")

        # Stage 6: Analyze transcript with AI (AC #4)
        log("Stage 5: Analyzing transcript with AI...", "INFO")
        analyze_cmd = [
            str(VENV_PYTHON),
            str(HELPERS_DIR / "krisp-analyze-transcript.py"),
            "--transcript", str(transcript_path),
            "--note", str(note_path),
            "--person", person_name,
            "--company", classification.get("company", "Unknown"),
            "--meeting-type", classification.get("meeting_type", "1on1"),
            "--date", note_date,
            "--json"
        ]

        try:
            analyze_result = subprocess.run(
                analyze_cmd,
                capture_output=True,
                text=True,
                timeout=120  # 2 minutes for AI processing
            )

            if analyze_result.returncode != 0:
                # AC #8: AI failure → already retried in script, skip
                log(f"AI analysis failed: {analyze_result.stderr}", "ERROR")
                cache.add_failed_match(
                    meeting_id,
                    "ai_analysis_failed",
                    {"transcript_path": str(transcript_path), "error": analyze_result.stderr}
                )
                result["errors"].append("ai_analysis_failed")
                return result

            analysis = json.loads(analyze_result.stdout)
            result["stages_completed"].append("ai_analysis")

        except subprocess.TimeoutExpired:
            # AC #8: AI timeout → skip
            log("AI analysis timed out", "ERROR")
            cache.add_failed_match(meeting_id, "ai_timeout", {"transcript_path": str(transcript_path)})
            result["errors"].append("ai_timeout")
            return result
        except json.JSONDecodeError as e:
            # AC #8: Invalid JSON from AI → skip
            log(f"Invalid JSON from AI: {str(e)}", "ERROR")
            cache.add_failed_match(meeting_id, "invalid_json", {"transcript_path": str(transcript_path)})
            result["errors"].append("invalid_json")
            return result

        # Stage 7: Update note (AC #5)
        log("Stage 6: Updating Obsidian note...", "INFO")
        transcript_rel_path = f"attachments/{note_date}-{person_name.lower().replace(' ', '-')}-transcript.txt"

        update_cmd = [
            str(VENV_PYTHON),
            str(HELPERS_DIR / "krisp-update-note.py"),
            "--note", str(note_path),
            "--analysis", json.dumps(analysis),
            "--transcript-path", transcript_rel_path,
            "--duration", "Unknown"  # TODO: Calculate from transcript
        ]

        try:
            update_result = subprocess.run(
                update_cmd,
                capture_output=True,
                text=True,
                timeout=10
            )

            if update_result.returncode != 0:
                # AC #8: File I/O error → skip with permissions log
                log(f"Note update failed: {update_result.stderr}", "ERROR")
                cache.add_failed_match(
                    meeting_id,
                    "file_io_error",
                    {"transcript_path": str(transcript_path), "note_path": str(note_path), "error": update_result.stderr}
                )
                result["errors"].append("file_io_error")
                return result

            result["stages_completed"].append("note_updated")

        except Exception as e:
            log(f"Note update error: {str(e)}", "ERROR")
            cache.add_failed_match(meeting_id, "note_update_error", {"transcript_path": str(transcript_path), "error": str(e)})
            result["errors"].append(f"note_update_error: {str(e)}")
            return result

        # Stage 8: Organize transcript file (AC #6)
        log("Stage 7: Organizing transcript file...", "INFO")

        # Generate standardized filename
        source = meeting_meta['title'].split(' - ')[-1].split()[0].lower()  # Extract source (slack, discord, etc.)
        person_slug = person_name.lower().replace(' ', '-')
        organized_filename = f"{note_date}-{person_slug}-{source}-transcript.txt"

        # Create attachments directory
        attachments_dir = Path(person_folder) / "attachments"
        attachments_dir.mkdir(parents=True, exist_ok=True)

        # Copy transcript (not move, in case of errors)
        organized_path = attachments_dir / organized_filename
        try:
            import shutil
            shutil.copy2(transcript_path, organized_path)
            log(f"✓ Organized transcript: {organized_path}", "INFO")
            result["stages_completed"].append("transcript_organized")
        except Exception as e:
            log(f"Failed to organize transcript: {str(e)}", "ERROR")
            # Non-critical error - note already updated, just log it
            result["errors"].append(f"transcript_org_failed: {str(e)}")

        # Success! Mark as processed
        cache.add_processed_meeting(
            meeting_id,
            {
                "date": note_date,
                "person": person_name,
                "company": classification.get("company"),
                "meeting_type": classification.get("meeting_type"),
                "note_path": str(note_path)
            }
        )

        result["success"] = True
        log(f"✓ Successfully processed meeting {meeting_id}", "INFO")
        return result

    except Exception as e:
        # Catch-all for unexpected errors
        log(f"Unexpected error processing {meeting_id}: {str(e)}", "ERROR")
        cache.add_failed_match(
            meeting_id,
            "unexpected_error",
            {"transcript_path": str(transcript_path), "error": str(e)}
        )
        result["errors"].append(f"unexpected_error: {str(e)}")
        return result


def main():
    parser = argparse.ArgumentParser(
        description='Process a Krisp transcript through the full automation pipeline'
    )
    parser.add_argument(
        '--transcript',
        required=True,
        help='Path to transcript file'
    )
    parser.add_argument(
        '--meeting-id',
        required=True,
        help='Unique Krisp meeting ID'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output result as JSON'
    )

    args = parser.parse_args()

    # Validate transcript exists
    transcript_path = Path(args.transcript)
    if not transcript_path.exists():
        print(f"✗ Transcript not found: {transcript_path}", file=sys.stderr)
        sys.exit(1)

    # Process transcript
    result = process_transcript(transcript_path, args.meeting_id)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        if result.get("success"):
            print(f"✓ Successfully processed meeting {args.meeting_id}")
            print(f"  Stages: {', '.join(result['stages_completed'])}")
        elif result.get("skipped"):
            print(f"⊘ Skipped meeting {args.meeting_id} (already processed or failed)")
        else:
            print(f"✗ Failed to process meeting {args.meeting_id}")
            print(f"  Errors: {', '.join(result['errors'])}")
            print(f"  Completed stages: {', '.join(result['stages_completed'])}")

    sys.exit(0 if result.get("success") else 1)


if __name__ == '__main__':
    main()
