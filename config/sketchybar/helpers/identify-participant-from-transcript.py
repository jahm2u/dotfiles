#!/usr/bin/env python3
"""
AI-Powered Participant Identification from Transcript
Analyzes meeting transcript to identify who Jeff is talking to.

Author: Amelia (Dev Agent)
Date: 2025-11-03
Purpose: Bypass slow calendar matching by using AI to identify participants directly
"""

import json
import sys
import os
import re
import subprocess
from pathlib import Path
from datetime import datetime, timedelta
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
OBSIDIAN_VAULT_PATH = Path(os.getenv("OBSIDIAN_VAULT_PATH", ""))
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
LOG_FILE = Path.home() / ".config/sketchybar/logs/participant-identification.log"

# Ensure log directory exists
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)


def log(message, level="INFO"):
    """Log message with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"[{timestamp}] [{level}] {message}"
    print(log_line, file=sys.stderr)
    with open(LOG_FILE, "a") as f:
        f.write(log_line + "\n")


def load_person_profiles():
    """
    Load PersonName.md files from vault for rich context.

    Scans:
    - Business/People/IPMedia
    - Business/People/CO/* (DT, EX, MT, PD, TP, etc.)
    - Personal/Family
    - Personal/Friends

    Returns dict: {
        'Ron': {'key_info': '...first 500 chars...', 'full_content': '...'},
        'Brighton': {...},
        ...
    }
    """
    profiles = {}

    if not OBSIDIAN_VAULT_PATH.exists():
        log(f"Vault path not found: {OBSIDIAN_VAULT_PATH}", "WARN")
        return profiles

    # Load IPMedia team profiles (including Inactive for backfill matching)
    ipmedia_path = OBSIDIAN_VAULT_PATH / "Business" / "People" / "IPMedia"
    if ipmedia_path.exists():
        for person_dir in ipmedia_path.iterdir():
            if person_dir.is_dir() and not person_dir.name.startswith('.'):
                profile_file = person_dir / f"{person_dir.name}.md"
                if profile_file.exists():
                    content = profile_file.read_text()
                    profiles[person_dir.name] = {
                        'full_content': content,
                        'key_info': content[:500]
                    }

    # Load CO (Cross-Organization) profiles - DT, EX, MT, PD, TP companies
    co_path = OBSIDIAN_VAULT_PATH / "Business" / "People" / "CO"
    if co_path.exists():
        for company_dir in co_path.iterdir():
            if company_dir.is_dir() and not company_dir.name.startswith('.'):
                for person_dir in company_dir.iterdir():
                    if person_dir.is_dir() and not person_dir.name.startswith('.'):
                        profile_file = person_dir / f"{person_dir.name}.md"
                        if profile_file.exists():
                            content = profile_file.read_text()
                            profiles[person_dir.name] = {
                                'full_content': content,
                                'key_info': content[:500],
                                'company': company_dir.name  # Track which company
                            }

    # Load Family profiles
    family_path = OBSIDIAN_VAULT_PATH / "Personal" / "Family"
    if family_path.exists():
        for person_dir in family_path.iterdir():
            if person_dir.is_dir() and not person_dir.name.startswith('.'):
                profile_file = person_dir / f"{person_dir.name}.md"
                if profile_file.exists():
                    content = profile_file.read_text()
                    profiles[person_dir.name] = {
                        'full_content': content,
                        'key_info': content[:500]
                    }

    # Load Friends profiles
    friends_path = OBSIDIAN_VAULT_PATH / "Personal" / "Friends"
    if friends_path.exists():
        for person_dir in friends_path.iterdir():
            if person_dir.is_dir() and not person_dir.name.startswith('.'):
                profile_file = person_dir / f"{person_dir.name}.md"
                if profile_file.exists():
                    content = profile_file.read_text()
                    profiles[person_dir.name] = {
                        'full_content': content,
                        'key_info': content[:500]
                    }

    return profiles


def load_khal_meeting_context(meeting_date):
    """
    Load khal calendar events from pre-generated JSON file.

    JSON file should be generated once before backfill using:
        python3 generate-khal-context.py

    Args:
        meeting_date: Date string (YYYY-MM-DD) of the transcript

    Returns: {
        'events': [...all events...],
        'events_near_target': [...events on meeting_date...],
        'status': 'success' | 'failed'
    }
    """
    khal_json_file = Path.home() / ".cache/sketchybar/khal-context-60d.json"

    try:
        if not khal_json_file.exists():
            log(f"khal context JSON not found: {khal_json_file}", "WARN")
            log("Run: python3 generate-khal-context.py to create it", "WARN")
            return {'events': [], 'events_near_target': [], 'status': 'not_found'}

        # Load pre-generated JSON
        with open(khal_json_file) as f:
            context = json.load(f)

        # Extract events for target date using pre-indexed lookup
        events_by_date = context.get('events_by_date', {})
        events_near_target = events_by_date.get(meeting_date, [])

        return {
            'events': context.get('events', []),
            'events_near_target': events_near_target,
            'status': 'success',
            'total_events': context.get('total_events', 0)
        }

    except json.JSONDecodeError as e:
        log(f"Invalid khal context JSON: {str(e)}", "WARN")
        return {'events': [], 'events_near_target': [], 'status': 'invalid_json'}
    except Exception as e:
        log(f"Error loading khal context: {str(e)}", "WARN")
        return {'events': [], 'events_near_target': [], 'status': 'error'}


def discover_known_people():
    """
    Scan vault structure to build list of known people.

    Returns dict with structure:
    {
        'family': ['Brighton', 'Evelyn', 'Mom', ...],
        'work': {'IPMedia': ['Ron', 'Evans', ...], 'DT': [...], 'EX': [...], ...},
        'friends': ['PersonName', ...]
    }
    """
    known_people = {
        'family': [],
        'work': {},
        'friends': []
    }

    if not OBSIDIAN_VAULT_PATH.exists():
        log(f"Vault path not found: {OBSIDIAN_VAULT_PATH}", "WARN")
        return known_people

    # Scan Family folder
    family_path = OBSIDIAN_VAULT_PATH / "Personal" / "Family"
    if family_path.exists():
        for folder in family_path.iterdir():
            if folder.is_dir() and not folder.name.startswith('.'):
                known_people['family'].append(folder.name)

    # Scan IPMedia (including Inactive for backfill matching)
    ipmedia_path = OBSIDIAN_VAULT_PATH / "Business" / "People" / "IPMedia"
    if ipmedia_path.exists():
        known_people['work']['IPMedia'] = []
        for person_folder in ipmedia_path.iterdir():
            if person_folder.is_dir() and not person_folder.name.startswith('.'):
                known_people['work']['IPMedia'].append(person_folder.name)

    # Scan CO (Cross-Organization) companies
    co_path = OBSIDIAN_VAULT_PATH / "Business" / "People" / "CO"
    if co_path.exists():
        for company_folder in co_path.iterdir():
            if company_folder.is_dir() and not company_folder.name.startswith('.'):
                company_name = company_folder.name
                known_people['work'][company_name] = []

                for person_folder in company_folder.iterdir():
                    if person_folder.is_dir() and not person_folder.name.startswith('.'):
                        known_people['work'][company_name].append(person_folder.name)

    # Scan Friends folder
    friends_path = OBSIDIAN_VAULT_PATH / "Personal" / "Friends"
    if friends_path.exists():
        for folder in friends_path.iterdir():
            if folder.is_dir() and not folder.name.startswith('.'):
                known_people['friends'].append(folder.name)

    return known_people


def count_speakers(transcript_text):
    """
    Count unique speakers in transcript.

    Transcript format: "Speaker Name | HH:MM"

    Returns: {
        'speaker_count': 3,
        'speakers': ['Jeff Hamersly', 'Ron', 'Evans'],
        'is_1on1': False
    }
    """
    # Extract speaker names from timestamp markers (must have HH:MM format after pipe)
    pattern = r'^([^|\n]+?)\s*\|\s*\d{2}:\d{2}'
    speaker_matches = re.findall(pattern, transcript_text, re.MULTILINE)

    # Normalize names (strip whitespace)
    speakers = {s.strip() for s in speaker_matches if s.strip()}

    return {
        'speaker_count': len(speakers),
        'speakers': sorted(list(speakers)),  # Sorted for consistency
        'is_1on1': len(speakers) == 2
    }


def estimate_meeting_duration(transcript_text):
    """
    Estimate meeting duration from transcript content.
    Returns duration in minutes.
    """
    # Count timestamp markers (format: "Speaker | HH:MM")
    timestamp_pattern = r'\|\s*(\d{2}):(\d{2})'
    timestamps = re.findall(timestamp_pattern, transcript_text)

    if len(timestamps) < 2:
        # Fallback: estimate from character count
        # Rough estimate: 150 words per minute, 5 chars per word
        chars = len(transcript_text)
        words = chars / 5
        minutes = words / 150
        return max(1, int(minutes))

    # Parse first and last timestamps
    try:
        first_hour, first_min = int(timestamps[0][0]), int(timestamps[0][1])
        last_hour, last_min = int(timestamps[-1][0]), int(timestamps[-1][1])

        first_total_mins = first_hour * 60 + first_min
        last_total_mins = last_hour * 60 + last_min

        duration = last_total_mins - first_total_mins

        # Handle wrap around midnight (rare but possible)
        if duration < 0:
            duration += 24 * 60

        return max(1, duration)
    except:
        # Fallback
        return max(1, len(transcript_text) // 1000)


def build_ai_prompt(transcript_text, meeting_date, meeting_time, known_people, person_profiles, speaker_info, khal_context=None):
    """Build AI prompt for participant identification with rich context"""

    # Build profile summaries with rich context
    profile_summaries = []
    for person, info in person_profiles.items():
        profile_summaries.append(f"{person}:\n{info['key_info']}\n")

    profile_context = "\n".join(profile_summaries) if profile_summaries else "No detailed profiles available"

    # Format speaker information
    speaker_context = f"""
SPEAKERS DETECTED IN TRANSCRIPT:
- Total speakers: {speaker_info['speaker_count']}
- Names: {', '.join(speaker_info['speakers'])}
- Is 1-on-1: {'Yes (2 speakers)' if speaker_info['is_1on1'] else 'No (team meeting)'}
"""

    # Format khal calendar context if available
    calendar_context = ""
    if khal_context and khal_context['status'] == 'success':
        events_on_date = khal_context.get('events_near_target', [])
        if events_on_date:
            calendar_context = f"""
CALENDAR EVENTS ON {meeting_date} (High Confidence Context):
"""
            for event in events_on_date[:10]:  # Show up to 10 events
                time_str = event.get('time', 'All-day')
                calendar_context += f"- {time_str}: {event['title']}\n"

            calendar_context += """
Use these calendar events to match the transcript date/time.
If the meeting time matches a calendar event, that event title provides strong context for identification.
Recurring meeting patterns (weekly, daily) indicate high confidence.
"""
        else:
            calendar_context = f"\nNo calendar events found on {meeting_date}.\n"

    # Truncate transcript if too long (keep first 3000 chars for context)
    transcript_sample = transcript_text[:3000]
    if len(transcript_text) > 3000:
        transcript_sample += "\n\n[... transcript continues ...]"

    prompt = f"""You are analyzing a meeting transcript to identify the PRIMARY participant and classify the meeting type.

{speaker_context}
{calendar_context}

TRANSCRIPT EXCERPT:
{transcript_sample}

MEETING METADATA:
- Date: {meeting_date}
- Time: {meeting_time}

KNOWN PEOPLE WITH DETAILED CONTEXT:

{profile_context}

TASK:
1. If this is a 1-on-1 (2 speakers): Identify the PRIMARY person Jeff is meeting with
2. If this is a team meeting (3+ speakers): Identify the MOST RELEVANT participant from the list above
3. Determine meeting type intelligently:
   - 'family' if family member (regardless of speaker count)
   - '1on1' if 2 speakers and work-related
   - 'team' if 3+ speakers (team meetings, planning sessions, etc.)
   - 'board' if discussing board-level topics (financials, strategy, governance)
   - 'company' if 6+ speakers or company-wide topics
4. Provide confidence: high (90%+), medium (70-89%), low (<70%)
5. Explain your reasoning briefly

IMPORTANT:
- Use speaker count AND conversation context to determine meeting type
- Match participant names to the KNOWN PEOPLE list above (exact name match)
- For team meetings, identify the most relevant participant (meeting organizer or primary contributor)
- Use the detailed profile information to understand roles and meeting patterns
- Board meetings discuss executive topics (financials, strategy, governance) - not just based on attendees
- Weekly exec meetings with 2 people are '1on1' type, not 'board'
- If you cannot confidently match, return confidence: low and participant: "Unknown"

Return ONLY valid JSON in this exact format:
{{
    "participant": "Ron",
    "meeting_type": "board",
    "confidence": "high",
    "reasoning": "3 speakers detected (Jeff, Ron, Evans). Ron and Evans both present indicates board meeting. Ron is CFO and this discusses quarterly financials per his profile."
}}"""

    return prompt


def identify_participant(transcript_text, meeting_date, meeting_time):
    """
    Use AI to identify meeting participant from transcript.

    Returns dict:
    {
        'participant': 'Brighton',
        'meeting_type': 'family|1on1|team|board|company',
        'confidence': 'high|medium|low',
        'reasoning': '...',
        'folder_path': '/path/to/person/folder' (if found),
        'category': 'family|work|friends|unknown',
        'speaker_count': 2,
        'speakers': ['Jeff Hamersly', 'Brighton'],
        'is_1on1': True
    }
    """

    if not OPENAI_API_KEY:
        log("OPENAI_API_KEY not set", "ERROR")
        return {
            'participant': 'Unknown',
            'meeting_type': '1on1',
            'confidence': 'low',
            'reasoning': 'OpenAI API key not configured',
            'folder_path': None,
            'category': 'unknown',
            'speaker_count': 0,
            'speakers': [],
            'is_1on1': False
        }

    # Count speakers first
    speaker_info = count_speakers(transcript_text)
    log(f"Speaker analysis: {speaker_info['speaker_count']} speakers - {', '.join(speaker_info['speakers'])}")

    # Discover known people
    known_people = discover_known_people()
    log(f"Known people: {len(known_people['family'])} family, "
        f"{sum(len(v) for v in known_people['work'].values())} work, "
        f"{len(known_people['friends'])} friends")

    # Load person profiles for rich context
    person_profiles = load_person_profiles()
    log(f"Loaded {len(person_profiles)} person profiles with detailed context")

    # Load khal calendar context for 60-day window (30 back + 30 forward)
    khal_context = load_khal_meeting_context(meeting_date)
    if khal_context['status'] == 'success':
        events_count = len(khal_context.get('events_near_target', []))
        log(f"✓ khal context loaded: {events_count} events on {meeting_date}")
    else:
        log(f"khal context unavailable: {khal_context['status']}", "WARN")

    # Build prompt with all context including calendar
    prompt = build_ai_prompt(transcript_text, meeting_date, meeting_time, known_people, person_profiles, speaker_info, khal_context)

    # Call OpenAI with dynamic token limit based on complexity
    try:
        client = OpenAI(api_key=OPENAI_API_KEY)

        # Dynamic token sizing: more speakers = more context needed
        max_tokens = 200 if speaker_info['is_1on1'] else 400

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a meeting transcript analyzer. Return only valid JSON."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.3,
            max_completion_tokens=max_tokens,
            safety_identifier="dotfiles-meeting-prep"
        )

        result_text = response.choices[0].message.content.strip()

        # Parse JSON response
        # Remove markdown code blocks if present
        result_text = re.sub(r'^```json\s*', '', result_text)
        result_text = re.sub(r'\s*```$', '', result_text)

        result = json.loads(result_text)

        # Validate required fields
        if not all(k in result for k in ['participant', 'meeting_type', 'confidence', 'reasoning']):
            raise ValueError("Missing required fields in AI response")

        # Find folder path
        participant_name = result['participant']
        folder_path = None
        category = 'unknown'

        if participant_name != "Unknown":
            # Check family
            if participant_name in known_people['family']:
                folder_path = str(OBSIDIAN_VAULT_PATH / "Personal" / "Family" / participant_name)
                category = 'family'

            # Check work - handle IPMedia vs CO companies correctly
            else:
                if participant_name in known_people['work'].get('IPMedia', []):
                    # IPMedia: Business/People/IPMedia/PersonName
                    folder_path = str(OBSIDIAN_VAULT_PATH / "Business" / "People" / "IPMedia" / participant_name)
                    category = 'work'
                else:
                    # CO companies: Business/People/CO/{Company}/PersonName
                    co_path = OBSIDIAN_VAULT_PATH / "Business" / "People" / "CO"
                    if co_path.exists():
                        for company_folder in co_path.iterdir():
                            if company_folder.is_dir() and not company_folder.name.startswith('.'):
                                for person_folder in company_folder.iterdir():
                                    if person_folder.is_dir() and person_folder.name == participant_name:
                                        folder_path = str(person_folder)
                                        category = 'work'
                                        break
                                if folder_path:
                                    break

            # Check friends
            if not folder_path and participant_name in known_people['friends']:
                folder_path = str(OBSIDIAN_VAULT_PATH / "Personal" / "Friends" / participant_name)
                category = 'friends'

        # Add speaker information to result
        result['folder_path'] = folder_path
        result['category'] = category
        result['speaker_count'] = speaker_info['speaker_count']
        result['speakers'] = speaker_info['speakers']
        result['is_1on1'] = speaker_info['is_1on1']

        log(f"Identified: {participant_name} ({category}, {result['confidence']} confidence, {result['speaker_count']} speakers)")

        return result

    except json.JSONDecodeError as e:
        log(f"Failed to parse AI response: {str(e)}", "ERROR")
        log(f"Raw response: {result_text[:200]}", "ERROR")
        return {
            'participant': 'Unknown',
            'meeting_type': '1on1',
            'confidence': 'low',
            'reasoning': f'AI response parsing failed: {str(e)}',
            'folder_path': None,
            'category': 'unknown',
            'speaker_count': speaker_info['speaker_count'],
            'speakers': speaker_info['speakers'],
            'is_1on1': speaker_info['is_1on1']
        }
    except Exception as e:
        log(f"AI identification failed: {str(e)}", "ERROR")
        return {
            'participant': 'Unknown',
            'meeting_type': '1on1',
            'confidence': 'low',
            'reasoning': f'Error: {str(e)}',
            'folder_path': None,
            'category': 'unknown',
            'speaker_count': speaker_info['speaker_count'],
            'speakers': speaker_info['speakers'],
            'is_1on1': speaker_info['is_1on1']
        }


def main():
    """CLI interface for testing"""
    import argparse

    parser = argparse.ArgumentParser(description='Identify meeting participant from transcript')
    parser.add_argument('--transcript', required=True, help='Path to transcript file')
    parser.add_argument('--date', help='Meeting date (YYYY-MM-DD)')
    parser.add_argument('--time', help='Meeting time (HH:MM)')
    parser.add_argument('--json', action='store_true', help='Output JSON only')

    args = parser.parse_args()

    # Read transcript
    transcript_path = Path(args.transcript)
    if not transcript_path.exists():
        print(f"Error: Transcript not found: {transcript_path}", file=sys.stderr)
        sys.exit(1)

    transcript_text = transcript_path.read_text()

    # Estimate duration
    duration_mins = estimate_meeting_duration(transcript_text)

    # Check minimum duration (3 minutes)
    if duration_mins < 3:
        result = {
            'participant': 'Skip',
            'meeting_type': 'unknown',
            'confidence': 'high',
            'reasoning': f'Meeting too short ({duration_mins} minutes), likely a recording glitch',
            'folder_path': None,
            'category': 'skip',
            'duration_minutes': duration_mins
        }
    else:
        # Identify participant
        result = identify_participant(
            transcript_text,
            args.date or 'unknown',
            args.time or 'unknown'
        )
        result['duration_minutes'] = duration_mins

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"Participant: {result['participant']}")
        print(f"Category: {result['category']}")
        print(f"Meeting Type: {result['meeting_type']}")
        print(f"Confidence: {result['confidence']}")
        print(f"Duration: {result['duration_minutes']} minutes")
        print(f"Folder: {result['folder_path'] or 'Not found'}")
        print(f"Reasoning: {result['reasoning']}")

    sys.exit(0)


if __name__ == '__main__':
    main()
