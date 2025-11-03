#!/usr/bin/env python3
"""
Smart Krisp Transcript Backfill
Processes downloaded transcripts using AI for participant identification and analysis.
Bypasses slow calendar matching by analyzing transcript content directly.

Author: Amelia (Dev Agent)
Date: 2025-11-03
Replaces: Calendar-based matching approach (too slow with 8000+ khal events)
Performance: ~10 seconds per transcript vs 2+ minutes with calendar matching
"""

import json
import sys
import os
import re
import subprocess
from pathlib import Path
from datetime import datetime
from openai import OpenAI
from dotenv import load_dotenv

# Load environment
env_paths = [
    Path.home() / "repos/02_personal/dotfiles/.env",
    Path.home() / "dotfiles/.env",
    Path(__file__).parent.parent / ".env",
]
for env_path in env_paths:
    if env_path.exists():
        load_dotenv(env_path)
        break

# Configuration
TRANSCRIPTS_DIR = Path.home() / ".config/sketchybar/krisp-transcripts"
CACHE_DIR = Path.home() / ".cache/sketchybar"
BACKFILL_CACHE = CACHE_DIR / "krisp-backfill-progress.json"
LOG_FILE = Path.home() / ".config/sketchybar/logs/krisp-backfill.log"
UNCLASSIFIED_DIR = Path(os.getenv("OBSIDIAN_VAULT_PATH", "")) / "Meetings" / "Unclassified"

OBSIDIAN_VAULT_PATH = Path(os.getenv("OBSIDIAN_VAULT_PATH", ""))
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
VENV_PYTHON = Path.home() / ".config/sketchybar/venv/bin/python3"

# Ensure directories
CACHE_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
UNCLASSIFIED_DIR.mkdir(parents=True, exist_ok=True)


def log(message, level="INFO"):
    """Log with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"[{timestamp}] [{level}] {message}"
    print(log_line)
    with open(LOG_FILE, "a") as f:
        f.write(log_line + "\n")


def load_progress():
    """Load backfill progress"""
    if BACKFILL_CACHE.exists():
        with open(BACKFILL_CACHE) as f:
            return json.load(f)
    return {
        'started_at': datetime.now().isoformat(),
        'processed': [],
        'skipped': [],
        'unclassified': [],
        'failed': [],
        'stats': {'by_person': {}, 'by_category': {}}
    }


def save_progress(progress):
    """Save progress atomically"""
    temp = BACKFILL_CACHE.with_suffix('.tmp')
    with open(temp, 'w') as f:
        json.dump(progress, f, indent=2)
    temp.replace(BACKFILL_CACHE)


def parse_transcript_metadata(filename):
    """
    Extract metadata from transcript filename.
    Format: krisp-transcript-{meeting_id}.txt

    Returns: {'id': 'abc123...', 'file': Path}
    """
    match = re.match(r'krisp-transcript-([a-f0-9]+)\.txt', filename)
    if match:
        return {
            'id': match.group(1),
            'file': TRANSCRIPTS_DIR / filename
        }
    return None


def load_meeting_metadata_from_queue(meeting_id):
    """
    Load date/time from pending queue file instead of guessing.

    Returns: {'date': 'YYYY-MM-DD', 'time': 'HH:MM', 'title': '...'}
    """
    queue_file = CACHE_DIR / "krisp-pending-downloads.json"

    if not queue_file.exists():
        return {'date': 'unknown', 'time': 'unknown', 'title': ''}

    try:
        queue_data = json.loads(queue_file.read_text())

        for meeting in queue_data.get('meetings', []):
            if meeting['id'] == meeting_id:
                # Parse time from title: "03:59 PM - Slack meeting October 31"
                title = meeting.get('title', '')
                time_match = re.match(r'(\d{1,2}):(\d{2})\s+(AM|PM)', title)

                if time_match:
                    hour, minute, period = time_match.groups()
                    hour_int = int(hour)
                    if period == 'PM' and hour_int != 12:
                        hour_int += 12
                    elif period == 'AM' and hour_int == 12:
                        hour_int = 0
                    time_str = f"{hour_int:02d}:{minute}"
                else:
                    time_str = 'unknown'

                return {
                    'date': meeting.get('date', 'unknown'),
                    'time': time_str,
                    'title': title
                }

    except Exception as e:
        log(f"Failed to load metadata from queue: {str(e)}", "WARN")

    return {'date': 'unknown', 'time': 'unknown', 'title': ''}


def calculate_token_limit(transcript_length):
    """
    Scale tokens dynamically based on transcript size.

    Short meetings get fewer tokens, long meetings get more.
    """
    if transcript_length < 5000:
        return 1000
    elif transcript_length < 15000:
        return 2000
    elif transcript_length < 30000:
        return 3000
    else:
        return 4000


def generate_team_meeting_title(transcript_text, speakers, date, participant):
    """
    Generate descriptive title for team meetings using AI.

    Returns: "2024-10-20 Team Meeting - Age Verification Strategy"
    """
    if not OPENAI_API_KEY:
        return f"{date} Team Meeting"

    try:
        client = OpenAI(api_key=OPENAI_API_KEY)

        prompt = f"""Generate a concise meeting title (max 5-6 words for topic).

Meeting Date: {date}
Participants: {', '.join(speakers)}
Primary Participant: {participant}

Transcript excerpt (first 1000 chars):
{transcript_text[:1000]}

Based on the content, determine:
1. Meeting type: Team Meeting, Planning Meeting, Board Meeting, or Technical Discussion
2. Main topic (3-5 words): What was primarily discussed?

Return ONLY in format: "Meeting Type - Main Topic"
Examples:
- "Team Meeting - Q3 Planning"
- "Board Meeting - Financial Review"
- "Planning Meeting - Product Roadmap"
- "Technical Discussion - Infrastructure"

Be specific and actionable. No dates, just type and topic."""

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.3,
            max_completion_tokens=30
        )

        title_suffix = response.choices[0].message.content.strip()

        # Clean up any quotes or extra formatting
        title_suffix = title_suffix.strip('"').strip("'")

        return f"{date} {title_suffix}"

    except Exception as e:
        log(f"Failed to generate team meeting title: {str(e)}", "WARN")
        return f"{date} Team Meeting"


def identify_participant(transcript_text, date, time):
    """
    Call participant identification script.
    Returns identification result dict.
    """
    script_path = Path(__file__).parent / "identify-participant-from-transcript.py"

    # Write transcript to temp file
    temp_transcript = CACHE_DIR / f"temp-transcript-{os.getpid()}.txt"
    temp_transcript.write_text(transcript_text)

    try:
        result = subprocess.run(
            [
                str(VENV_PYTHON),
                str(script_path),
                "--transcript", str(temp_transcript),
                "--date", date,
                "--time", time,
                "--json"
            ],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode == 0:
            return json.loads(result.stdout)
        else:
            log(f"Participant identification failed: {result.stderr}", "ERROR")
            return None

    finally:
        temp_transcript.unlink(missing_ok=True)


def analyze_transcript(transcript_path, person_name, meeting_type, date):
    """
    Run AI analysis on transcript using existing script.
    Returns analysis dict.
    """
    script_path = Path(__file__).parent / "krisp-analyze-transcript.py"

    # Create temp note file for analysis
    temp_note = CACHE_DIR / f"temp-note-{os.getpid()}.md"
    temp_note.write_text("# Meeting Note\n\n")

    try:
        result = subprocess.run(
            [
                str(VENV_PYTHON),
                str(script_path),
                "--transcript", str(transcript_path),
                "--note", str(temp_note),
                "--person", person_name,
                "--company", "unknown",
                "--meeting-type", meeting_type,
                "--date", date,
                "--json"
            ],
            capture_output=True,
            text=True,
            timeout=60
        )

        if result.returncode == 0:
            return json.loads(result.stdout)
        else:
            log(f"AI analysis failed: {result.stderr}", "ERROR")
            return None

    finally:
        temp_note.unlink(missing_ok=True)


def create_meeting_note(person_folder, person_name, date, time, analysis, transcript_rel_path, duration_mins):
    """
    Create 1-on-1 meeting note in person's Meetings folder.
    Returns note path.
    """
    meetings_folder = Path(person_folder) / "Meetings"
    meetings_folder.mkdir(parents=True, exist_ok=True)

    # Generate filename: YYYY-MM-DD-HH-MM.md
    time_clean = time.replace(":", "-")
    note_filename = f"{date}-{time_clean}.md"
    note_path = meetings_folder / note_filename

    # Build note content
    content = f"""# Meeting with {person_name}

**Date:** {date}
**Time:** {time}
**Duration:** {duration_mins} minutes
**Type:** {analysis.get('meeting_type', '1on1')}

---

## 🎯 Discussion Highlights

{format_list(analysis.get('discussion_highlights', []))}

## ✅ Action Items Captured

{format_action_items(analysis.get('action_items', {}))}

## 💡 Topics to Review Next Time

{format_list(analysis.get('topics_next_time', []))}

## 🔗 Related Context

{format_list(analysis.get('related_context', []))}

---

**Original Transcript:** [[{transcript_rel_path}|View Transcript]]
**Processed:** {datetime.now().strftime('%Y-%m-%d %H:%M')}
**Source:** Krisp AI Transcript (backfilled)
"""

    note_path.write_text(content)
    log(f"Created 1-on-1 note: {note_path.name}")

    return str(note_path)


def create_team_meeting_note(meeting_title, date, time, speakers, analysis, transcript_path, duration_mins):
    """
    Create team meeting note in Business/IPMedia/Meetings folder.
    Returns note path.
    """
    team_meetings_folder = OBSIDIAN_VAULT_PATH / "Business" / "IPMedia" / "Meetings"
    team_meetings_folder.mkdir(parents=True, exist_ok=True)

    # Filename from generated title
    note_filename = f"{meeting_title}.md"
    note_path = team_meetings_folder / note_filename

    # Build attendees list
    attendees_list = "\n".join(f"- [[{speaker}]]" for speaker in speakers)

    # Build note content
    content = f"""# {meeting_title}

**Date:** {date}
**Time:** {time}
**Duration:** {duration_mins} minutes
**Type:** Team Meeting

## Attendees

{attendees_list}

---

## 🎯 Discussion Highlights

{format_list(analysis.get('discussion_highlights', []))}

## ✅ Action Items Captured

{format_action_items(analysis.get('action_items', {}))}

## 💡 Topics to Review Next Time

{format_list(analysis.get('topics_next_time', []))}

## 🔗 Related Context

{format_list(analysis.get('related_context', []))}

---

**Original Transcript:** `{transcript_path.name}`
**Processed:** {datetime.now().strftime('%Y-%m-%d %H:%M')}
**Source:** Krisp AI Transcript (backfilled)
"""

    note_path.write_text(content)
    log(f"Created team meeting note: {note_path.name}")

    return str(note_path)


def format_list(items):
    """Format list items as markdown bullets"""
    if not items:
        return "*No items captured*"
    return "\n".join(f"- {item}" for item in items)


def format_action_items(items_dict):
    """Format action items grouped by person"""
    if not items_dict:
        return "*No action items*"

    lines = []
    for person, items in items_dict.items():
        if items:
            lines.append(f"\n**{person}:**")
            lines.extend(f"- [ ] {item}" for item in items)

    return "\n".join(lines) if lines else "*No action items*"


def move_transcript_to_person_folder(transcript_path, person_folder):
    """
    Move transcript to person's attachments folder.
    Returns new path.
    """
    attachments_folder = Path(person_folder) / "attachments"
    attachments_folder.mkdir(parents=True, exist_ok=True)

    new_path = attachments_folder / transcript_path.name

    # Copy instead of move to preserve original
    import shutil
    shutil.copy2(transcript_path, new_path)

    log(f"Copied transcript to: {attachments_folder.name}/{transcript_path.name}")

    return str(new_path)


def process_transcript(transcript_file, progress):
    """
    Process a single transcript through the full pipeline.
    Returns status: 'processed', 'skipped', 'unclassified', 'failed'
    """
    meeting_id = parse_transcript_metadata(transcript_file.name)['id']
    log(f"\n{'='*60}")
    log(f"Processing: {transcript_file.name}")

    # Load transcript
    transcript_text = transcript_file.read_text()

    # Load metadata from queue instead of parsing transcript
    metadata = load_meeting_metadata_from_queue(meeting_id)
    date = metadata['date']
    time = metadata['time']

    log(f"Date: {date}, Time: {time}")

    # Step 1: Identify participant
    identification = identify_participant(transcript_text, date, time)

    if not identification:
        log("Failed to identify participant", "ERROR")
        progress['failed'].append({
            'id': meeting_id,
            'file': transcript_file.name,
            'reason': 'Identification failed'
        })
        return 'failed'

    # Step 2: Check if should skip (too short)
    if identification['category'] == 'skip':
        log(f"Skipping: {identification['reasoning']}")
        progress['skipped'].append({
            'id': meeting_id,
            'file': transcript_file.name,
            'duration_minutes': identification['duration_minutes'],
            'reason': identification['reasoning']
        })
        return 'skipped'

    participant = identification['participant']
    confidence = identification['confidence']
    category = identification['category']
    folder_path = identification['folder_path']

    log(f"Identified: {participant} ({category}, {confidence} confidence)")
    log(f"Reasoning: {identification['reasoning'][:100]}...")

    # Step 3: Handle low confidence / unknown participants
    if confidence == 'low' or participant == 'Unknown' or not folder_path:
        log("Low confidence or unknown participant - saving to unclassified", "WARN")

        # Save to unclassified folder
        unclassified_note = UNCLASSIFIED_DIR / f"{date}-{time.replace(':', '-')}-{meeting_id[:8]}.md"

        content = f"""# Unclassified Meeting

**Date:** {date}
**Time:** {time}
**Duration:** {identification['duration_minutes']} minutes
**Confidence:** {confidence}

---

## AI Analysis

**Participant Guess:** {participant}
**Reasoning:** {identification['reasoning']}

**Meeting Type:** {identification['meeting_type']}

---

## Transcript Excerpt

```
{transcript_text[:1000]}
...
```

**Full Transcript:** `{transcript_file.name}`

---

*This meeting needs manual classification. Review the transcript and move to the appropriate person folder.*
"""

        unclassified_note.write_text(content)

        progress['unclassified'].append({
            'id': meeting_id,
            'file': transcript_file.name,
            'date': date,
            'time': time,
            'participant_guess': participant,
            'confidence': confidence,
            'note': str(unclassified_note)
        })

        return 'unclassified'

    # Step 4: Run AI analysis
    log("Running AI analysis...")
    analysis = analyze_transcript(
        transcript_file,
        participant,
        identification['meeting_type'],
        date
    )

    if not analysis:
        log("AI analysis failed", "ERROR")
        progress['failed'].append({
            'id': meeting_id,
            'file': transcript_file.name,
            'reason': 'AI analysis failed'
        })
        return 'failed'

    # Step 5: Create meeting note - route based on meeting type
    speaker_count = identification['speaker_count']
    speakers = identification['speakers']
    is_1on1 = identification['is_1on1']

    if is_1on1:
        # 1-on-1 meeting → save to person folder
        log(f"Routing: 1-on-1 meeting → {folder_path}")

        # Move transcript to person folder
        new_transcript_path = move_transcript_to_person_folder(transcript_file, folder_path)
        transcript_rel_path = f"attachments/{transcript_file.name}"

        note_path = create_meeting_note(
            folder_path,
            participant,
            date,
            time,
            analysis,
            transcript_rel_path,
            identification['duration_minutes']
        )

    else:
        # Team meeting (3+ speakers) → save to Business/IPMedia/Meetings/
        log(f"Routing: Team meeting ({speaker_count} speakers) → Business/IPMedia/Meetings/")

        # Generate descriptive title using AI
        meeting_title = generate_team_meeting_title(
            transcript_text,
            speakers,
            date,
            participant
        )

        # Create team meeting note (uses full transcript path, not moved)
        note_path = create_team_meeting_note(
            meeting_title,
            date,
            time,
            speakers,
            analysis,
            transcript_file,  # Pass Path object
            identification['duration_minutes']
        )

        new_transcript_path = str(transcript_file)  # Kept in original location
        log(f"✓ Created team meeting: {meeting_title}")

    # Step 6: Update progress
    progress['processed'].append({
        'id': meeting_id,
        'file': transcript_file.name,
        'participant': participant,
        'category': category,
        'date': date,
        'time': time,
        'note_path': note_path,
        'transcript_path': new_transcript_path,
        'duration_minutes': identification['duration_minutes'],
        'confidence': confidence
    })

    # Update stats
    if participant not in progress['stats']['by_person']:
        progress['stats']['by_person'][participant] = 0
    progress['stats']['by_person'][participant] += 1

    if category not in progress['stats']['by_category']:
        progress['stats']['by_category'][category] = 0
    progress['stats']['by_category'][category] += 1

    log(f"✓ Processed successfully: {participant} - {note_path}")

    return 'processed'


def main():
    """Main backfill execution"""
    import argparse

    parser = argparse.ArgumentParser(description='Smart Krisp transcript backfill')
    parser.add_argument('--limit', type=int, help='Max transcripts to process')
    parser.add_argument('--reset', action='store_true', help='Reset progress and start fresh')
    parser.add_argument('--dry-run', action='store_true', help='Preview only, no processing')

    args = parser.parse_args()

    log("="*60)
    log("KRISP SMART BACKFILL STARTING")
    log("="*60)

    # Reset if requested
    if args.reset and BACKFILL_CACHE.exists():
        BACKFILL_CACHE.unlink()
        log("Progress reset")

    # Load progress
    progress = load_progress()

    # Get all transcript files
    all_transcripts = sorted(TRANSCRIPTS_DIR.glob("krisp-transcript-*.txt"))

    log(f"Found {len(all_transcripts)} total transcripts")

    # Filter already processed
    processed_ids = {p['id'] for p in progress['processed']}
    skipped_ids = {s['id'] for s in progress['skipped']}
    unclassified_ids = {u['id'] for u in progress['unclassified']}
    failed_ids = {f['id'] for f in progress['failed']}

    done_ids = processed_ids | skipped_ids | unclassified_ids | failed_ids

    to_process = [
        t for t in all_transcripts
        if parse_transcript_metadata(t.name)['id'] not in done_ids
    ]

    log(f"Already processed: {len(done_ids)}")
    log(f"Remaining: {len(to_process)}")

    if args.limit:
        to_process = to_process[:args.limit]
        log(f"Limited to: {args.limit}")

    if not to_process:
        log("No transcripts to process")
        print_summary(progress)
        sys.exit(0)

    # Dry run preview
    if args.dry_run:
        log("DRY RUN - Preview mode")
        for i, t in enumerate(to_process, 1):
            log(f"{i}. {t.name}")
        sys.exit(0)

    # Process transcripts
    log(f"\nProcessing {len(to_process)} transcripts...")

    for idx, transcript_file in enumerate(to_process, 1):
        log(f"\n[{idx}/{len(to_process)}]")

        try:
            status = process_transcript(transcript_file, progress)

            # Save progress after each transcript
            save_progress(progress)

            log(f"Status: {status}")

        except KeyboardInterrupt:
            log("Interrupted by user", "WARN")
            save_progress(progress)
            sys.exit(1)

        except Exception as e:
            log(f"Unexpected error: {str(e)}", "ERROR")
            import traceback
            log(traceback.format_exc(), "ERROR")

            # Mark as failed
            meeting_id = parse_transcript_metadata(transcript_file.name)['id']
            progress['failed'].append({
                'id': meeting_id,
                'file': transcript_file.name,
                'reason': str(e)
            })
            save_progress(progress)

    log("\n" + "="*60)
    log("BACKFILL COMPLETE")
    log("="*60)

    print_summary(progress)


def print_summary(progress):
    """Print final summary"""
    print("\n" + "="*60)
    print("BACKFILL SUMMARY")
    print("="*60)

    print(f"\n✅ Processed: {len(progress['processed'])}")
    print(f"⏭️  Skipped (too short): {len(progress['skipped'])}")
    print(f"❓ Unclassified: {len(progress['unclassified'])}")
    print(f"❌ Failed: {len(progress['failed'])}")

    if progress['stats']['by_person']:
        print("\nBy Person:")
        for person, count in sorted(progress['stats']['by_person'].items(), key=lambda x: -x[1]):
            print(f"  {person}: {count}")

    if progress['stats']['by_category']:
        print("\nBy Category:")
        for category, count in sorted(progress['stats']['by_category'].items()):
            print(f"  {category}: {count}")

    if progress['unclassified']:
        print(f"\nUnclassified meetings saved to:")
        print(f"  {UNCLASSIFIED_DIR}")

    if progress['failed']:
        print(f"\nFailed transcripts:")
        for f in progress['failed']:
            print(f"  {f['file']}: {f['reason']}")

    print("\n" + "="*60)


if __name__ == '__main__':
    main()
