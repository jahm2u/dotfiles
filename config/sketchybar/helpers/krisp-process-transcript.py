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


def extract_speakers(transcript_path):
    """
    Extract speaker names from transcript file.

    Format: "Name | MM:SS"
    Returns: List of unique speaker names (excluding Jeff and generic labels)
    """
    import re

    speakers = set()
    try:
        with open(transcript_path, 'r') as f:
            content = f.read()

        # Pattern: capture everything before ' | MM:SS'
        pattern = r'^([^|]+) \| \d+:\d+$'
        matches = re.findall(pattern, content, re.MULTILINE)

        for speaker in matches:
            speaker = speaker.strip()
            # Filter out generic labels and Jeff
            if speaker not in ["Speaker 2", "Speaker 3", "Speaker 4", "Jeff Ipmedia", "Jeff Hamersly", "Jeff"]:
                speakers.add(speaker)

        return list(speakers)
    except Exception as e:
        log(f"Error extracting speakers: {str(e)}", "WARN")
        return []


def search_calendar_by_participant(participant_name, event_date):
    """
    Search calendar events for participant name match on given date.

    Returns: List of matching events (title, start_time, description)
    """
    import subprocess

    try:
        # Search khal for events on date containing participant name
        khal_cmd = ["khal", "list", "--day-format", "", event_date, "1d"]
        result = subprocess.run(khal_cmd, capture_output=True, text=True, timeout=10)

        if result.returncode != 0:
            return []

        # Parse khal output for events containing participant name
        events = []
        for line in result.stdout.strip().split('\n'):
            if not line.strip():
                continue

            # Check if participant name appears in event title
            if participant_name.lower() in line.lower():
                # Extract time and title (format: "HH:MM-HH:MM Event Title")
                parts = line.split(' ', 1)
                if len(parts) == 2:
                    time_range, title = parts
                    events.append({
                        "title": title.strip(),
                        "time": time_range,
                        "participant": participant_name
                    })

        return events
    except Exception as e:
        log(f"Error searching calendar by participant: {str(e)}", "WARN")
        return []


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
        "status": "failed",  # Default status (success/skipped/failed)
        "meeting_id": meeting_id,
        "transcript_path": str(transcript_path),
        "errors": [],
        "stages_completed": []
    }

    cache = load_cache_module()

    # Check if already processed
    if cache.is_processed(meeting_id):
        log(f"Meeting {meeting_id} already processed, skipping", "INFO")
        result["status"] = "skipped"
        result["skipped"] = True
        result["reason"] = "Already processed"
        return result

    # Check if in failed matches
    if cache.is_failed(meeting_id):
        log(f"Meeting {meeting_id} previously failed, skipping", "WARN")
        result["status"] = "skipped"
        result["skipped"] = True
        result["reason"] = "Previously failed"
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
            result["status"] = "failed"
            result["reason"] = "metadata_not_found"
            return result

        with open(pending_file, 'r') as f:
            pending_data = json.load(f)

        # Find meeting metadata by ID
        meeting_meta = next((m for m in pending_data.get('meetings', []) if m['id'] == meeting_id), None)
        if not meeting_meta:
            log(f"Meeting metadata not found for ID: {meeting_id}", "ERROR")
            cache.add_failed_match(meeting_id, "metadata_not_found", {"transcript_path": str(transcript_path)})
            result["errors"].append("metadata_not_found")
            result["status"] = "failed"
            result["reason"] = "metadata_not_found"
            return result

        log(f"Found metadata: {meeting_meta['title']}", "INFO")

        # Stage 2: Match to calendar event (AC #1)
        log("Stage 1: Matching to calendar event...", "INFO")

        # Extract year from date, fallback to current year if None
        if meeting_meta.get('date'):
            year = meeting_meta['date'].split('-')[0]
        else:
            year = str(datetime.now().year)

        match_cmd = [
            str(VENV_PYTHON),
            str(HELPERS_DIR / "krisp-match-meetings.py"),
            "--title", meeting_meta['title'],
            "--year", year,
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

        # Stage 2.5: Speaker-based matching fallback for improved accuracy
        speakers = extract_speakers(transcript_path)
        log(f"Extracted speakers from transcript: {speakers}", "INFO")

        # If we have a single speaker (likely 1on1), try participant-based matching
        if len(speakers) == 1:
            participant_events = search_calendar_by_participant(speakers[0], event_date)

            if participant_events:
                log(f"Found {len(participant_events)} calendar events matching participant '{speakers[0]}'", "INFO")

                # Check if time-based match has low confidence or doesn't match participant
                time_match_confidence = calendar_match.get("confidence", "no_match")
                time_match_title = calendar_match.get("event", {}).get("title", "")

                # If participant name in time match, keep it
                if speakers[0].lower() in time_match_title.lower():
                    log(f"Time-based match '{time_match_title}' contains participant name, keeping it", "INFO")
                # If time match has no participant name, prefer participant match
                elif time_match_confidence in ["low", "medium"]:
                    log(f"Time match has {time_match_confidence} confidence, overriding with participant match", "INFO")
                    # Use first participant match
                    event_title = participant_events[0]["title"]
                    calendar_match = {
                        "confidence": "high",
                        "event": {"title": event_title},
                        "match_method": "speaker_based"
                    }
                elif time_match_confidence == "no_match":
                    log("No time match, using participant match", "INFO")
                    event_title = participant_events[0]["title"]
                    calendar_match = {
                        "confidence": "high",
                        "event": {"title": event_title},
                        "match_method": "speaker_based"
                    }

        if calendar_match.get("confidence") == "no_match":
            # AC #7: Failed match handling
            log("No calendar match found (time or speaker)", "WARN")
            cache.add_failed_match(
                meeting_id,
                "no_calendar_match",
                {"transcript_path": str(transcript_path), "date": calendar_match.get("krisp_date"), "speakers": speakers}
            )
            result["errors"].append("no_calendar_match")
            result["status"] = "failed"
            result["reason"] = "no_calendar_match"
            return result

        result["stages_completed"].append("calendar_match")

        # Extract event data from match result
        matched_event = calendar_match.get("event", {})
        event_title = matched_event.get("title", "Unknown")
        # Use the date from the Krisp metadata
        event_date = meeting_meta.get("date")

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

        # Stage 4: Determine folder and note path based on meeting type
        log("Stage 3: Determining meeting folder...", "INFO")
        meeting_type = classification.get("meeting_type", "unknown")
        note_date = event_date  # Use event_date extracted earlier from calendar match

        # Get vault path from env
        vault_path = Path(os.getenv("OBSIDIAN_VAULT_PATH", ""))
        if not vault_path or not vault_path.exists():
            log("OBSIDIAN_VAULT_PATH not set or invalid", "ERROR")
            cache.add_failed_match(meeting_id, "vault_not_found", {"transcript_path": str(transcript_path)})
            result["errors"].append("vault_not_found")
            result["status"] = "failed"
            result["reason"] = "vault_not_found"
            return result

        # Handle different meeting types
        if meeting_type in ["ipmedia_1on1", "ipmedia_executive"]:
            # 1on1 or Executive: Find person folder
            log(f"Finding person folder for {classification.get('participant')}...", "INFO")
            find_cmd = [
                "bash",
                str(HELPERS_DIR / "find-person-folder.sh"),
                "--person", classification.get("participant", "Unknown"),
                "--company", classification.get("company", "IPMedia")
            ]

            try:
                find_result = subprocess.run(find_cmd, capture_output=True, text=True, timeout=10)
                if find_result.returncode != 0:
                    log(f"Person not found: {classification.get('participant')}", "ERROR")
                    cache.add_failed_match(
                        meeting_id, "person_not_found",
                        {"transcript_path": str(transcript_path), "person": classification.get("participant")}
                    )
                    result["errors"].append("person_not_found")
                    result["status"] = "failed"
                    result["reason"] = "person_not_found"
                    return result

                person_folder = Path(find_result.stdout.strip())
                meetings_folder = person_folder / "Meetings"
                person_name = classification.get("participant", "Unknown")

                # Note naming: "YYYY-MM-DD 1on1 with Person.md"
                note_filename = f"{note_date} 1on1 with {person_name}.md"
                note_path = meetings_folder / note_filename

            except subprocess.TimeoutExpired:
                log("Person folder search timed out", "ERROR")
                cache.add_failed_match(meeting_id, "person_search_timeout", {"transcript_path": str(transcript_path)})
                result["errors"].append("person_search_timeout")
                result["status"] = "failed"
                result["reason"] = "person_search_timeout"
                return result

        elif meeting_type.startswith("ipmedia_team_"):
            # Team meeting: Business/Teams/{Team}/Meetings/
            team_name = meeting_type.replace("ipmedia_team_", "").title()
            meetings_folder = vault_path / "Business" / "Teams" / team_name / "Meetings"
            meetings_folder.mkdir(parents=True, exist_ok=True)

            # Note naming: "YYYY-MM-DD {Team} Team Meeting.md"
            note_filename = f"{note_date} {team_name} Team Meeting.md"
            note_path = meetings_folder / note_filename
            log(f"Using team folder: {meetings_folder}", "INFO")

        elif meeting_type == "ipmedia_company_wide":
            # Company-wide: Business/Company/IPMedia/Meetings/
            meetings_folder = vault_path / "Business" / "Company" / "IPMedia" / "Meetings"
            meetings_folder.mkdir(parents=True, exist_ok=True)

            # Note naming: "YYYY-MM-DD Company Meeting.md"
            note_filename = f"{note_date} Company Meeting.md"
            note_path = meetings_folder / note_filename
            log(f"Using company-wide folder: {meetings_folder}", "INFO")

        elif meeting_type.startswith("co_"):
            # Portfolio company: Business/Company/{Company}/Meetings/
            company_code = meeting_type.replace("co_", "").replace("_meeting", "").upper()
            meetings_folder = vault_path / "Business" / "Company" / company_code / "Meetings"
            meetings_folder.mkdir(parents=True, exist_ok=True)

            # Note naming: "YYYY-MM-DD {Company} Meeting.md"
            note_filename = f"{note_date} {company_code} Meeting.md"
            note_path = meetings_folder / note_filename
            log(f"Using company folder: {meetings_folder}", "INFO")

        elif meeting_type == "ipmedia_standup":
            # Standup: Business/Teams/Development/Meetings/
            meetings_folder = vault_path / "Business" / "Teams" / "Development" / "Meetings"
            meetings_folder.mkdir(parents=True, exist_ok=True)

            # Note naming: "YYYY-MM-DD Standup.md"
            note_filename = f"{note_date} Standup.md"
            note_path = meetings_folder / note_filename
            log(f"Using standup folder: {meetings_folder}", "INFO")

        else:
            # Unknown meeting type
            log(f"Unknown meeting type: {meeting_type}", "ERROR")
            cache.add_failed_match(meeting_id, "unknown_meeting_type", {"transcript_path": str(transcript_path), "meeting_type": meeting_type})
            result["errors"].append(f"unknown_meeting_type: {meeting_type}")
            result["status"] = "failed"
            result["reason"] = "Unknown error"
            return result

        result["stages_completed"].append("folder_determined")

        # Set meeting identifier for later use (AI analysis, transcript naming, etc.)
        if meeting_type in ["ipmedia_1on1", "ipmedia_executive"]:
            meeting_identifier = classification.get("participant", "Unknown")
        elif meeting_type.startswith("ipmedia_team_"):
            meeting_identifier = meeting_type.replace("ipmedia_team_", "").title()
        elif meeting_type == "ipmedia_company_wide":
            meeting_identifier = "Company"
        elif meeting_type == "ipmedia_standup":
            meeting_identifier = "Standup"
        elif meeting_type.startswith("co_"):
            meeting_identifier = meeting_type.replace("co_", "").replace("_meeting", "").upper()
        else:
            meeting_identifier = "Unknown"

        # Stage 5: Find or create meeting note
        log(f"Stage 4: Locating meeting note: {note_filename}", "INFO")
        note_date = event_date  # Use event_date extracted earlier from calendar match

        # Track if note was created (for telegram notification details)
        note_was_created = not note_path.exists()

        if note_was_created:
            # AC #8: Missing note → create from template, continue processing
            log(f"Note not found, creating from template: {note_path}", "WARN")
            meetings_folder.mkdir(parents=True, exist_ok=True)

            # Generate template based on meeting type
            if meeting_type in ["ipmedia_1on1", "ipmedia_executive"]:
                # 1on1 or Executive template (fallback - matches vault template structure)
                person_name = classification.get("participant", "Unknown")
                template = f"""# {note_date} 1on1 with {person_name}

**Date:** {note_date}
**Participants:** [[Personal/Jeff|Jeff Hamersly]], [[Business/People/{classification.get('company', 'IPMedia')}/{person_name}/{person_name}|{person_name}]]
**Company:** {classification.get('company', 'IPMedia')}
**Meeting Type:** 1on1

---

## 📝 MEETING CAPTURE (Fill During/After Meeting)

### Notes During Meeting
<!-- Manual notes go here -->


### Action Items
<!-- AI extracts from transcript; manual additions welcome -->


### Key Insights & Quotes
<!-- AI extracts significant quotes and insights from transcript -->


### Decisions Made
<!-- AI extracts from transcript -->


### Blockers Identified
<!-- AI extracts from transcript -->


### Growth & Development
<!-- AI analyzes from transcript -->


### Business Impact
<!-- AI analyzes and summarizes business implications -->


---

## 📚 REFERENCE & CONTEXT

### Related Documents
- [[Business/People/{classification.get('company', 'IPMedia')}/{person_name}/{person_name}|{person_name} Profile]]
- [[Business/People/{classification.get('company', 'IPMedia')}/{person_name}/Meetings/|All Meetings with {person_name}]]

---

"""
            elif meeting_type.startswith("ipmedia_team_"):
                # Team meeting template
                team_name = meeting_type.replace("ipmedia_team_", "").title()
                template = f"""# {note_date} {team_name} Team Meeting

**Date:** {note_date}
**Team:** {team_name}
**Meeting Type:** Team Meeting

## 📝 Meeting Summary
*Auto-generated from transcript analysis*

### 🎯 Key Discussion Points

### ✅ Action Items & Owners

### 📊 Metrics & Updates

### 🔗 Related Context

"""
            elif meeting_type == "ipmedia_company_wide":
                # Company-wide template
                template = f"""# {note_date} Company Meeting

**Date:** {note_date}
**Company:** IPMedia
**Meeting Type:** Company-Wide

## 📝 Meeting Summary
*Auto-generated from transcript analysis*

### 🎯 Key Announcements

### ✅ Action Items

### 📊 Company Updates

### 🔗 Related Context

"""
            elif meeting_type == "ipmedia_standup":
                # Standup template
                template = f"""# {note_date} Standup

**Date:** {note_date}
**Team:** Development
**Meeting Type:** Daily Standup

## 📝 Standup Summary
*Auto-generated from transcript analysis*

### 🎯 What We Did Yesterday

### 🚀 What We're Doing Today

### 🚧 Blockers & Issues

### ✅ Action Items

"""
            else:
                # Portfolio company template
                company_code = meeting_type.replace("co_", "").replace("_meeting", "").upper()
                template = f"""# {note_date} {company_code} Meeting

**Date:** {note_date}
**Company:** {company_code}
**Meeting Type:** Portfolio Company Meeting

## 📝 Meeting Summary
*Auto-generated from transcript analysis*

### 🎯 Key Discussion Points

### ✅ Action Items

### 📊 Updates & Metrics

### 🔗 Related Context

"""

            try:
                note_path.write_text(template)
                log(f"✓ Created note from template: {note_path}", "INFO")
            except Exception as e:
                log(f"Failed to create note: {str(e)}", "ERROR")
                cache.add_failed_match(meeting_id, "note_creation_failed", {"transcript_path": str(transcript_path), "error": str(e)})
                result["errors"].append("note_creation_failed")
                result["status"] = "failed"
                result["reason"] = "note_creation_failed"
                return result

        result["stages_completed"].append("note_found")

        # Stage 6: Analyze transcript with AI (AC #4)
        log("Stage 5: Analyzing transcript with AI...", "INFO")
        analyze_cmd = [
            str(VENV_PYTHON),
            str(HELPERS_DIR / "krisp-analyze-transcript.py"),
            "--transcript", str(transcript_path),
            "--note", str(note_path),
            "--person", meeting_identifier,
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
                result["status"] = "failed"
                result["reason"] = "ai_analysis_failed"
                return result

            analysis = json.loads(analyze_result.stdout)
            result["stages_completed"].append("ai_analysis")

        except subprocess.TimeoutExpired:
            # AC #8: AI timeout → skip
            log("AI analysis timed out", "ERROR")
            cache.add_failed_match(meeting_id, "ai_timeout", {"transcript_path": str(transcript_path)})
            result["errors"].append("ai_timeout")
            result["status"] = "failed"
            result["reason"] = "ai_timeout"
            return result
        except json.JSONDecodeError as e:
            # AC #8: Invalid JSON from AI → skip
            log(f"Invalid JSON from AI: {str(e)}", "ERROR")
            cache.add_failed_match(meeting_id, "invalid_json", {"transcript_path": str(transcript_path)})
            result["errors"].append("invalid_json")
            result["status"] = "failed"
            result["reason"] = "invalid_json"
            return result

        # Stage 7: Update note (AC #5)
        log("Stage 6: Updating Obsidian note...", "INFO")
        transcript_rel_path = f"attachments/{note_date}-{meeting_identifier.lower().replace(' ', '-')}-transcript.txt"

        update_cmd = [
            str(VENV_PYTHON),
            str(HELPERS_DIR / "krisp-update-note.py"),
            "--note", str(note_path),
            "--transcript-path", transcript_rel_path,
            "--duration", "Unknown"  # TODO: Calculate from transcript
        ]

        try:
            update_result = subprocess.run(
                update_cmd,
                input=json.dumps(analysis),
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
                result["status"] = "failed"
                result["reason"] = "file_io_error"
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
        identifier_slug = meeting_identifier.lower().replace(' ', '-')
        organized_filename = f"{note_date}-{identifier_slug}-{source}-transcript.txt"

        # Create attachments directory (parent of Meetings folder)
        attachments_dir = meetings_folder.parent / "attachments"
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
                "person": meeting_identifier,
                "company": classification.get("company"),
                "meeting_type": classification.get("meeting_type"),
                "note_path": str(note_path)
            }
        )

        result["success"] = True
        result["status"] = "success"

        # Add action details for Telegram notification
        note_filename = note_path.name
        action_verb = "Created" if note_was_created else "Updated"
        result["action"] = f"{action_verb} {note_filename}"

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
        result["status"] = "failed"
        result["reason"] = result["errors"][0] if result["errors"] else "Unknown error"
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
