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


def log(message, level="INFO", exc_info=None, context=None):
    """
    Enhanced logging with context and exception support

    Args:
        message: Log message
        level: Log level (DEBUG, INFO, WARN, ERROR)
        exc_info: Exception object for traceback logging
        context: Dict of contextual information (meeting_id, file_path, etc.)
    """
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")

    # Build context string
    context_str = ""
    if context:
        context_parts = [f"{k}={v}" for k, v in context.items() if v is not None]
        if context_parts:
            context_str = f" [{', '.join(context_parts)}]"

    log_line = f"[{timestamp}] [{level}]{context_str} {message}"
    print(log_line, file=sys.stderr)

    with open(LOG_FILE, "a") as f:
        f.write(log_line + "\n")

        # Add exception traceback if provided
        if exc_info:
            import traceback
            tb_lines = traceback.format_exception(type(exc_info), exc_info, exc_info.__traceback__)
            for line in tb_lines:
                f.write(f"[{timestamp}] [{level}] {line}")
            print(f"[{timestamp}] [{level}] Exception: {type(exc_info).__name__}: {str(exc_info)}", file=sys.stderr)


def extract_speakers(transcript_path):
    """
    Extract speaker names from transcript file.

    Format: "Name | MM:SS"
    Returns: List of unique speaker names (excluding Jeff and generic labels)
    """
    import re

    ctx = {"function": "extract_speakers", "transcript": transcript_path}
    speakers = set()

    try:
        log(f"Reading transcript file", "DEBUG", context=ctx)

        with open(transcript_path, 'r') as f:
            content = f.read()

        log(f"Transcript size: {len(content)} bytes", "DEBUG", context=ctx)

        # Pattern: capture only the speaker name (letters/spaces) before ' | MM:SS'
        # Don't allow newlines in the capture group to prevent matching previous text lines
        pattern = r'^([A-Za-z\s]+) \| \d+:\d+$'
        matches = re.findall(pattern, content, re.MULTILINE)

        log(f"Found {len(matches)} speaker lines in transcript", "DEBUG", context=ctx)

        for speaker in matches:
            speaker = speaker.strip()
            # Only filter out Jeff (keep generic Speaker labels to count participants)
            if speaker not in ["Jeff Ipmedia", "Jeff Hamersly", "Jeff"]:
                speakers.add(speaker)

        speaker_list = list(speakers)
        log(f"Extracted {len(speaker_list)} unique speakers: {speaker_list}", "DEBUG", context=ctx)

        # Return unique speakers as a list
        return speaker_list

    except FileNotFoundError as e:
        log(f"Transcript file not found: {transcript_path}", "ERROR", exc_info=e, context=ctx)
        return []
    except Exception as e:
        log(f"Failed to extract speakers from transcript", "ERROR", exc_info=e, context=ctx)
        return []


def search_calendar_by_participant(participant_name, event_date):
    """
    Search calendar events for participant name match on given date.

    Returns: List of matching events (title, start_time, description)
    """
    import subprocess

    ctx = {
        "function": "search_calendar_by_participant",
        "participant": participant_name,
        "date": event_date
    }

    try:
        log(f"Searching calendar for participant '{participant_name}' on {event_date}", "DEBUG", context=ctx)

        # Search khal for events on date containing participant name
        khal_cmd = ["khal", "list", "--day-format", "", event_date, "1d"]
        log(f"Running command: {' '.join(khal_cmd)}", "DEBUG", context=ctx)

        result = subprocess.run(khal_cmd, capture_output=True, text=True, timeout=10)

        if result.returncode != 0:
            log(f"khal command failed with exit code {result.returncode}", "WARN", context=ctx)
            if result.stderr:
                log(f"khal stderr: {result.stderr}", "DEBUG", context=ctx)
            return []

        # Parse khal output for events containing participant name
        events = []
        lines = result.stdout.strip().split('\n')
        log(f"Got {len(lines)} lines from khal", "DEBUG", context=ctx)

        for line in lines:
            if not line.strip():
                continue

            # Check if participant name appears in event title
            if participant_name.lower() in line.lower():
                log(f"Found matching event line: {line[:100]}", "DEBUG", context=ctx)

                # Extract time and title (format: "HH:MM-HH:MM Event Title")
                parts = line.split(' ', 1)
                if len(parts) == 2:
                    time_range, title = parts
                    events.append({
                        "title": title.strip(),
                        "time": time_range,
                        "participant": participant_name
                    })

        log(f"Found {len(events)} matching calendar events", "DEBUG", context=ctx)
        return events

    except subprocess.TimeoutExpired as e:
        log(f"Calendar search timed out after 10 seconds", "ERROR", exc_info=e, context=ctx)
        return []
    except FileNotFoundError as e:
        log("khal not found - install with: brew install khal", "ERROR", exc_info=e, context=ctx)
        return []
    except Exception as e:
        log(f"Calendar search failed unexpectedly", "ERROR", exc_info=e, context=ctx)
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
    # Context dict for all logging in this function
    ctx = {
        "meeting_id": meeting_id,
        "transcript": str(transcript_path)
    }

    result = {
        "success": False,
        "status": "failed",  # Default status (success/skipped/failed)
        "meeting_id": meeting_id,
        "transcript_path": str(transcript_path),
        "errors": [],
        "stages_completed": []
    }

    # Initialize variables that will be used throughout
    event_title = "Unknown"
    event_date = None
    meeting_type = "unknown"

    log(f"Starting transcript processing pipeline", "INFO", context=ctx)

    cache = load_cache_module()

    # Check if already processed
    if cache.is_processed(meeting_id):
        log(f"Meeting already processed, skipping", "INFO", context=ctx)
        result["status"] = "skipped"
        result["skipped"] = True
        result["reason"] = "Already processed"
        return result

    # Check if in failed matches
    if cache.is_failed(meeting_id):
        log(f"Meeting previously failed, skipping", "WARN", context=ctx)
        result["status"] = "skipped"
        result["skipped"] = True
        result["reason"] = "Previously failed"
        return result

    try:
        # Stage 1: Load meeting metadata from pending downloads
        log(f"Stage 1: Loading meeting metadata", "INFO", context=ctx)

        # Load metadata from krisp-pending-downloads.json
        pending_file = Path.home() / ".cache/sketchybar/krisp-pending-downloads.json"
        if not pending_file.exists():
            log(f"Pending downloads file not found at {pending_file}", "ERROR", context=ctx)
            cache.add_failed_match(meeting_id, "metadata_not_found", {"transcript_path": str(transcript_path)})
            result["errors"].append("metadata_not_found")
            result["status"] = "failed"
            result["reason"] = "metadata_not_found"
            return result

        log(f"Reading pending downloads from {pending_file}", "DEBUG", context=ctx)

        with open(pending_file, 'r') as f:
            pending_data = json.load(f)

        # Find meeting metadata by ID
        meeting_meta = next((m for m in pending_data.get('meetings', []) if m['id'] == meeting_id), None)
        if not meeting_meta:
            log(f"Meeting metadata not found in pending downloads", "ERROR", context=ctx)
            cache.add_failed_match(meeting_id, "metadata_not_found", {"transcript_path": str(transcript_path)})
            result["errors"].append("metadata_not_found")
            result["status"] = "failed"
            result["reason"] = "metadata_not_found"
            return result

        # Update context with meeting details
        ctx["title"] = meeting_meta['title']
        ctx["date"] = meeting_meta.get('date', 'unknown')
        ctx["time"] = meeting_meta.get('time', 'unknown')

        log(f"Found metadata: {meeting_meta['title']}", "INFO", context=ctx)
        log(f"Meeting date: {meeting_meta.get('date', 'unknown')}, time: {meeting_meta.get('time', 'unknown')}", "DEBUG", context=ctx)

        # Extract date early for use in calendar matching and note naming
        event_date = meeting_meta.get("date")
        note_date = event_date  # Used for note filename creation

        # Stage 2: Match to calendar event (AC #1)
        log("Stage 1: Matching to calendar event...", "INFO", context=ctx)

        # Extract year from date, fallback to current year if None
        if meeting_meta.get('date'):
            year = meeting_meta['date'].split('-')[0]
        else:
            year = str(datetime.now().year)

        # Use unified classification with calendar matching
        match_cmd = [
            str(VENV_PYTHON),
            str(HELPERS_DIR / "classify-meeting-unified.py"),
            "--title", meeting_meta['title'],
            "--date", meeting_meta.get('date', ''),  # Will be parsed from title if needed
            "--time", meeting_meta.get('time', '')   # Optional time hint
        ]

        log(f"Running classification: {' '.join(match_cmd[2:])}", "DEBUG", context=ctx)

        try:
            match_result = subprocess.run(
                match_cmd,
                capture_output=True,
                text=True,
                timeout=180  # 3 minutes for large calendar databases (8000+ events)
            )

            if match_result.returncode != 0:
                log(f"Classification script failed with exit code {match_result.returncode}", "ERROR", context=ctx)
                if match_result.stderr:
                    log(f"Classification stderr: {match_result.stderr[:500]}", "DEBUG", context=ctx)
                raise Exception(f"Calendar matching failed: {match_result.stderr}")

            log(f"Classification output: {len(match_result.stdout)} bytes", "DEBUG", context=ctx)
            calendar_match = json.loads(match_result.stdout)
            log(f"Classification result: type={calendar_match.get('meeting_type')}, confidence={calendar_match.get('confidence')}", "INFO", context=ctx)

        except json.JSONDecodeError as e:
            log(f"Failed to parse classification JSON output", "ERROR", exc_info=e, context=ctx)
            log(f"Raw output: {match_result.stdout[:500]}", "DEBUG", context=ctx)
            cache.add_failed_match(meeting_id, "classification_parse_error", {"transcript_path": str(transcript_path), "error": str(e)})
            result["errors"].append(f"classification_parse_error: {str(e)}")
            return result
        except subprocess.TimeoutExpired as e:
            log(f"Classification timed out after 180 seconds", "ERROR", exc_info=e, context=ctx)
            cache.add_failed_match(meeting_id, "classification_timeout", {"transcript_path": str(transcript_path)})
            result["errors"].append("classification_timeout")
            return result
        except Exception as e:
            log(f"Classification failed unexpectedly", "ERROR", exc_info=e, context=ctx)
            cache.add_failed_match(meeting_id, "calendar_match_error", {"transcript_path": str(transcript_path), "error": str(e)})
            result["errors"].append(f"calendar_match_error: {str(e)}")
            return result

        # Stage 2.5: Speaker-based matching fallback for improved accuracy
        log("Stage 2: Speaker-based matching (fallback/validation)", "INFO", context=ctx)
        speakers = extract_speakers(transcript_path)

        ctx["speakers"] = speakers  # Add to context
        log(f"Extracted {len(speakers)} speakers from transcript: {speakers}", "INFO", context=ctx)

        # FILTER: Skip empty or single-speaker transcripts (solo recordings, not meetings)
        # Note: 1on1s will have 2+ speakers, so this only catches true solo recordings
        if len(speakers) == 0:
            log(f"Empty transcript detected, no speakers found - skipping as solo recording", "WARN", context=ctx)
            cache.add_failed_match(
                meeting_id,
                "empty_transcript",
                {"transcript_path": str(transcript_path)}
            )
            result["errors"].append("empty_transcript")
            result["status"] = "skipped"
            result["reason"] = "empty_transcript"
            return result

        # If we have multiple speakers, try participant-based matching
        # Only if event_date is available (required for khal query)
        if len(speakers) >= 1 and event_date:
            log(f"Attempting speaker-based calendar matching with primary speaker: {speakers[0]}", "DEBUG", context=ctx)
            participant_events = search_calendar_by_participant(speakers[0], event_date)

            if participant_events:
                log(f"Speaker-based match found {len(participant_events)} calendar events for '{speakers[0]}'", "INFO", context=ctx)

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
        # event_date already extracted earlier (line 209)

        # Stage 3: Use classification from calendar match (AC #2)
        # The unified classifier already classified the meeting in Stage 1
        log("Stage 2: Using classification from calendar match...", "INFO")
        classification = {
            "meeting_type": calendar_match.get("meeting_type", "unknown"),
            "company": calendar_match.get("company"),
            "participant": calendar_match.get("participant"),
            "confidence": calendar_match.get("confidence", 0)
        }
        log(f"Classification: {classification['meeting_type']} (company: {classification['company']}, participant: {classification['participant']})", "INFO")

        # FILTER: Skip excluded meetings (lunch, breaks, etc.)
        if classification['meeting_type'] == 'excluded':
            log(f"Skipping excluded meeting: {event_title}", "INFO")
            cache.add_failed_match(
                meeting_id,
                "excluded_meeting",
                {"transcript_path": str(transcript_path), "event_title": event_title}
            )
            result["status"] = "skipped"
            result["reason"] = "excluded_meeting"
            return result

        result["stages_completed"].append("classification")

        # Stage 4: Determine folder and note path based on meeting type
        log("Stage 3: Determining meeting folder...", "INFO")
        meeting_type = classification.get("meeting_type", "unknown")
        note_date = event_date if event_date else meeting_meta.get("date")  # Use event_date or fallback to meeting_meta

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
            person_name = classification.get("participant", "Unknown")
            company_name = classification.get("company", "IPMedia")
            ctx = {
                "meeting_id": meeting_id,
                "person": person_name,
                "company": company_name,
                "meeting_type": meeting_type
            }

            log(f"Finding person folder for {person_name}...", "INFO", context=ctx)
            find_cmd = [
                "bash",
                str(HELPERS_DIR / "find-person-folder.sh"),
                "--person", person_name,
                "--company", company_name
            ]

            log(f"Running find-person-folder.sh: --person {person_name} --company {company_name}", "DEBUG", context=ctx)

            try:
                find_result = subprocess.run(find_cmd, capture_output=True, text=True, timeout=10)

                if find_result.returncode != 0:
                    log(f"Person folder search failed: {find_result.stderr.strip()}", "ERROR", context=ctx)
                    log(f"Person not found in vault: {person_name}", "ERROR", context=ctx)
                    cache.add_failed_match(
                        meeting_id, "person_not_found",
                        {"transcript_path": str(transcript_path), "person": person_name, "company": company_name}
                    )
                    result["errors"].append("person_not_found")
                    result["status"] = "failed"
                    result["reason"] = "person_not_found"
                    return result

                person_folder = Path(find_result.stdout.strip())
                meetings_folder = person_folder / "Meetings"

                log(f"✓ Found person folder: {person_folder}", "INFO", context=ctx)
                log(f"Meetings folder: {meetings_folder}", "DEBUG", context=ctx)

                # Note naming: "YYYY-MM-DD 1on1 with Person.md"
                note_filename = f"{note_date} 1on1 with {person_name}.md"
                note_path = meetings_folder / note_filename

            except subprocess.TimeoutExpired:
                log("Person folder search timed out (>10s)", "ERROR", context=ctx)
                cache.add_failed_match(meeting_id, "person_search_timeout", {"transcript_path": str(transcript_path)})
                result["errors"].append("person_search_timeout")
                result["status"] = "failed"
                result["reason"] = "person_search_timeout"
                return result
            except Exception as e:
                log("Person folder search failed unexpectedly", "ERROR", exc_info=e, context=ctx)
                cache.add_failed_match(meeting_id, "person_search_error", {"transcript_path": str(transcript_path), "error": str(e)})
                result["errors"].append(f"person_search_error: {str(e)}")
                result["status"] = "failed"
                result["reason"] = "person_search_error"
                return result

        elif meeting_type.startswith("ipmedia_team_"):
            # Team meeting: Business/IPMedia/Teams/{Team}/Meetings/
            team_name = meeting_type.replace("ipmedia_team_", "").title()
            ctx = {"meeting_id": meeting_id, "team": team_name, "meeting_type": meeting_type}

            meetings_folder = vault_path / "Business" / "IPMedia" / "Teams" / team_name / "Meetings"
            log(f"Creating/using team folder: {meetings_folder}", "DEBUG", context=ctx)
            meetings_folder.mkdir(parents=True, exist_ok=True)

            # Note naming: "YYYY-MM-DD {Team} Team Meeting.md"
            note_filename = f"{note_date} {team_name} Team Meeting.md"
            note_path = meetings_folder / note_filename
            log(f"✓ Team folder determined: {meetings_folder}", "INFO", context=ctx)

        elif meeting_type == "ipmedia_company_wide":
            # Company-wide: Business/Company/IPMedia/Meetings/
            ctx = {"meeting_id": meeting_id, "meeting_type": "company_wide"}

            meetings_folder = vault_path / "Business" / "Company" / "IPMedia" / "Meetings"
            log(f"Creating/using company-wide folder: {meetings_folder}", "DEBUG", context=ctx)
            meetings_folder.mkdir(parents=True, exist_ok=True)

            # Note naming: "YYYY-MM-DD Company Meeting.md"
            note_filename = f"{note_date} Company Meeting.md"
            note_path = meetings_folder / note_filename
            log(f"✓ Company-wide folder determined: {meetings_folder}", "INFO", context=ctx)

        elif meeting_type.startswith("co_"):
            # Portfolio company: Business/Company/{Company}/Meetings/
            company_code = meeting_type.replace("co_", "").replace("_meeting", "").upper()
            ctx = {"meeting_id": meeting_id, "company": company_code, "meeting_type": meeting_type}

            meetings_folder = vault_path / "Business" / "Company" / company_code / "Meetings"
            log(f"Creating/using portfolio company folder: {meetings_folder}", "DEBUG", context=ctx)
            meetings_folder.mkdir(parents=True, exist_ok=True)

            # Note naming: "YYYY-MM-DD {Company} Meeting.md"
            note_filename = f"{note_date} {company_code} Meeting.md"
            note_path = meetings_folder / note_filename
            log(f"✓ Portfolio company folder determined: {meetings_folder}", "INFO", context=ctx)

        elif meeting_type == "ipmedia_standup":
            # Standup: Business/IPMedia/Teams/Development/Meetings/
            ctx = {"meeting_id": meeting_id, "meeting_type": "standup"}

            meetings_folder = vault_path / "Business" / "IPMedia" / "Teams" / "Development" / "Meetings"
            log(f"Creating/using standup folder: {meetings_folder}", "DEBUG", context=ctx)
            meetings_folder.mkdir(parents=True, exist_ok=True)

            # Note naming: "YYYY-MM-DD Standup.md"
            note_filename = f"{note_date} Standup.md"
            note_path = meetings_folder / note_filename
            log(f"✓ Standup folder determined: {meetings_folder}", "INFO", context=ctx)

        else:
            # Unknown meeting type - use Unclassified folder (graceful degradation)
            ctx = {"meeting_id": meeting_id, "meeting_type": meeting_type, "event_title": event_title}

            log(f"Unknown meeting type '{meeting_type}', using Unclassified folder", "WARN", context=ctx)
            meetings_folder = vault_path / "Business" / "Meetings" / "Unclassified"
            log(f"Creating/using unclassified folder: {meetings_folder}", "DEBUG", context=ctx)
            meetings_folder.mkdir(parents=True, exist_ok=True)

            # Use calendar event title for filename (sanitize)
            safe_title = event_title.replace("/", "-").replace(":", "")[:60]
            note_filename = f"{note_date} {safe_title}.md"
            note_path = meetings_folder / note_filename
            meeting_type = "unclassified"  # Mark for special Telegram notification
            log(f"✓ Unclassified folder determined: {meetings_folder}", "INFO", context=ctx)

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
        elif meeting_type == "unclassified":
            meeting_identifier = "Unclassified"
        else:
            meeting_identifier = "Unknown"

        # Stage 5: Find or create meeting note
        ctx = {
            "meeting_id": meeting_id,
            "note_filename": note_filename,
            "note_path": str(note_path),
            "meeting_type": meeting_type
        }

        log(f"Stage 4: Locating meeting note: {note_filename}", "INFO", context=ctx)
        log(f"Note path: {note_path}", "DEBUG", context=ctx)

        # Track if note was created (for telegram notification details)
        note_was_created = not note_path.exists()

        if note_was_created:
            # AC #8: Missing note → create from template, continue processing
            log(f"Note not found, creating from template", "WARN", context=ctx)
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
            elif meeting_type.startswith("co_"):
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
            else:
                # Unclassified meeting template
                template = f"""# {note_date} {event_title}

**Date:** {note_date}
**Meeting Type:** Unclassified
**Original Title:** {event_title}

⚠️ **Note:** This meeting was not automatically classified. Please review and add proper classification patterns.

## 📝 Meeting Summary
*Auto-generated from transcript analysis*

### 🎯 Key Discussion Points

### ✅ Action Items

### 📊 Updates & Metrics

### 🔗 Related Context

"""

            try:
                log(f"Writing template ({len(template)} bytes)", "DEBUG", context=ctx)
                note_path.write_text(template)
                log(f"✓ Created note from template: {note_filename}", "INFO", context=ctx)
            except Exception as e:
                log(f"Failed to create note", "ERROR", exc_info=e, context=ctx)
                cache.add_failed_match(meeting_id, "note_creation_failed", {"transcript_path": str(transcript_path), "error": str(e)})
                result["errors"].append("note_creation_failed")
                result["status"] = "failed"
                result["reason"] = "note_creation_failed"
                return result
        else:
            log(f"✓ Note already exists: {note_filename}", "INFO", context=ctx)

        result["stages_completed"].append("note_found")

        # Stage 6: Analyze transcript with AI (AC #4)
        ctx = {
            "meeting_id": meeting_id,
            "transcript": str(transcript_path),
            "person": meeting_identifier,
            "company": classification.get("company"),
            "meeting_type": classification.get("meeting_type")
        }

        log("Stage 5: Analyzing transcript with AI...", "INFO", context=ctx)

        analyze_cmd = [
            str(VENV_PYTHON),
            str(HELPERS_DIR / "krisp-analyze-transcript.py"),
            "--transcript", str(transcript_path),
            "--note", str(note_path),
            "--person", meeting_identifier or "Unknown",
            "--company", classification.get("company") or "Unknown",
            "--meeting-type", classification.get("meeting_type") or "1on1",
            "--date", note_date or "Unknown",
            "--json"
        ]

        log(f"Running AI analysis: --person {meeting_identifier} --meeting-type {classification.get('meeting_type')}", "DEBUG", context=ctx)

        try:
            analyze_result = subprocess.run(
                analyze_cmd,
                capture_output=True,
                text=True,
                timeout=120  # 2 minutes for AI processing
            )

            log(f"AI analysis completed with exit code: {analyze_result.returncode}", "DEBUG", context=ctx)

            if analyze_result.returncode != 0:
                # AC #8: AI failure → already retried in script, skip
                log(f"AI analysis failed: {analyze_result.stderr[:500]}", "ERROR", context=ctx)
                cache.add_failed_match(
                    meeting_id,
                    "ai_analysis_failed",
                    {"transcript_path": str(transcript_path), "error": analyze_result.stderr[:500]}
                )
                result["errors"].append("ai_analysis_failed")
                result["status"] = "failed"
                result["reason"] = "ai_analysis_failed"
                return result

            log(f"AI analysis output: {len(analyze_result.stdout)} bytes", "DEBUG", context=ctx)
            analysis = json.loads(analyze_result.stdout)
            log(f"✓ AI analysis complete: {len(analysis.get('discussion_highlights', []))} highlights, {len(analysis.get('action_items', {}))} action items", "INFO", context=ctx)
            result["stages_completed"].append("ai_analysis")

        except subprocess.TimeoutExpired:
            # AC #8: AI timeout → skip
            log("AI analysis timed out (>120s)", "ERROR", context=ctx)
            cache.add_failed_match(meeting_id, "ai_timeout", {"transcript_path": str(transcript_path)})
            result["errors"].append("ai_timeout")
            result["status"] = "failed"
            result["reason"] = "ai_timeout"
            return result
        except json.JSONDecodeError as e:
            # AC #8: Invalid JSON from AI → skip
            log(f"Invalid JSON from AI analysis", "ERROR", exc_info=e, context=ctx)
            log(f"Raw output: {analyze_result.stdout[:500]}", "DEBUG", context=ctx)
            cache.add_failed_match(meeting_id, "invalid_json", {"transcript_path": str(transcript_path)})
            result["errors"].append("invalid_json")
            result["status"] = "failed"
            result["reason"] = "invalid_json"
            return result
        except Exception as e:
            log("AI analysis failed unexpectedly", "ERROR", exc_info=e, context=ctx)
            cache.add_failed_match(meeting_id, "ai_unexpected_error", {"transcript_path": str(transcript_path), "error": str(e)})
            result["errors"].append(f"ai_unexpected_error: {str(e)}")
            result["status"] = "failed"
            result["reason"] = "ai_unexpected_error"
            return result

        # Stage 7: Update note (AC #5)
        ctx = {
            "meeting_id": meeting_id,
            "note_path": str(note_path),
            "note_filename": note_filename
        }

        log("Stage 6: Updating Obsidian note with AI analysis...", "INFO", context=ctx)

        transcript_rel_path = f"attachments/{note_date}-{meeting_identifier.lower().replace(' ', '-')}-transcript.txt"

        update_cmd = [
            str(VENV_PYTHON),
            str(HELPERS_DIR / "krisp-update-note.py"),
            "--note", str(note_path),
            "--transcript-path", transcript_rel_path,
            "--duration", "Unknown"  # TODO: Calculate from transcript
        ]

        log(f"Running note update: krisp-update-note.py --note {note_filename}", "DEBUG", context=ctx)
        log(f"Analysis payload: {len(json.dumps(analysis))} bytes", "DEBUG", context=ctx)

        try:
            update_result = subprocess.run(
                update_cmd,
                input=json.dumps(analysis),
                capture_output=True,
                text=True,
                timeout=10
            )

            log(f"Note update completed with exit code: {update_result.returncode}", "DEBUG", context=ctx)

            if update_result.returncode != 0:
                # AC #8: File I/O error → skip with permissions log
                log(f"Note update failed: {update_result.stderr[:500]}", "ERROR", context=ctx)
                cache.add_failed_match(
                    meeting_id,
                    "file_io_error",
                    {"transcript_path": str(transcript_path), "note_path": str(note_path), "error": update_result.stderr[:500]}
                )
                result["errors"].append("file_io_error")
                result["status"] = "failed"
                result["reason"] = "file_io_error"
                return result

            log(f"✓ Note updated successfully: {note_filename}", "INFO", context=ctx)
            result["stages_completed"].append("note_updated")

        except subprocess.TimeoutExpired:
            log("Note update timed out (>10s)", "ERROR", context=ctx)
            cache.add_failed_match(meeting_id, "note_update_timeout", {"transcript_path": str(transcript_path), "note_path": str(note_path)})
            result["errors"].append("note_update_timeout")
            result["status"] = "failed"
            result["reason"] = "note_update_timeout"
            return result
        except Exception as e:
            log("Note update failed unexpectedly", "ERROR", exc_info=e, context=ctx)
            cache.add_failed_match(meeting_id, "note_update_error", {"transcript_path": str(transcript_path), "error": str(e)})
            result["errors"].append(f"note_update_error: {str(e)}")
            result["status"] = "failed"
            result["reason"] = "note_update_error"
            return result

        # Stage 8: Organize transcript file (AC #6)
        ctx = {
            "meeting_id": meeting_id,
            "transcript_path": str(transcript_path),
            "meeting_identifier": meeting_identifier
        }

        log("Stage 7: Organizing transcript file...", "INFO", context=ctx)

        # Generate standardized filename
        source = meeting_meta['title'].split(' - ')[-1].split()[0].lower()  # Extract source (slack, discord, etc.)
        identifier_slug = meeting_identifier.lower().replace(' ', '-')
        organized_filename = f"{note_date}-{identifier_slug}-{source}-transcript.txt"

        log(f"Transcript filename: {organized_filename}", "DEBUG", context=ctx)

        # Create attachments directory (parent of Meetings folder)
        attachments_dir = meetings_folder.parent / "attachments"
        log(f"Creating/using attachments directory: {attachments_dir}", "DEBUG", context=ctx)
        attachments_dir.mkdir(parents=True, exist_ok=True)

        # Copy transcript (not move, in case of errors)
        organized_path = attachments_dir / organized_filename
        try:
            import shutil
            log(f"Copying transcript to: {organized_path}", "DEBUG", context=ctx)
            shutil.copy2(transcript_path, organized_path)
            log(f"✓ Organized transcript: {organized_filename}", "INFO", context=ctx)
            result["stages_completed"].append("transcript_organized")
        except Exception as e:
            log(f"Failed to organize transcript", "ERROR", exc_info=e, context=ctx)
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
        result["meeting_type"] = meeting_type  # For unclassified detection in Telegram notification
        result["event_title"] = event_title  # Original calendar title for prompt
        result["note_path"] = str(note_path)  # For Obsidian deep link in Telegram

        ctx = {
            "meeting_id": meeting_id,
            "note_filename": note_filename,
            "action": result["action"],
            "stages": len(result["stages_completed"])
        }
        log(f"✓ Successfully processed meeting: {result['action']} ({len(result['stages_completed'])} stages)", "INFO", context=ctx)
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

    # Exit with 0 for success OR skipped (skipped is not an error)
    sys.exit(0 if (result.get("success") or result.get("skipped")) else 1)


if __name__ == '__main__':
    main()
