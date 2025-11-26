#!/Users/v/.config/sketchybar/venv/bin/python3
"""
Meeting History Analyzer
Analyzes previous meetings using OpenAI to extract context and continuity.
"""

import argparse
import glob
import json
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any

from dotenv import load_dotenv
from openai import OpenAI


def load_environment():
    """Load environment variables from .env file."""
    # Search for .env in multiple locations
    env_locations = [
        os.path.expanduser("~/dotfiles/.env"),
        os.path.expanduser("~/.env"),
        os.path.expanduser("~/repos/02_personal/dotfiles/.env"),
    ]

    for env_path in env_locations:
        if os.path.exists(env_path):
            load_dotenv(env_path)
            return

    raise FileNotFoundError("Could not find .env file in any expected location")


def get_meeting_files(person_folder: str, limit: int = 5) -> List[str]:
    """
    Get the last N meeting files from person's Meetings folder.

    Args:
        person_folder: Path to person folder
        limit: Maximum number of meetings to retrieve

    Returns:
        List of meeting file paths, sorted by date (oldest first for chronological reading)
    """
    meetings_dir = os.path.join(person_folder, "Meetings")

    if not os.path.isdir(meetings_dir):
        return []

    # Find all markdown files with YYYY-MM-DD prefix
    pattern = os.path.join(meetings_dir, "????-??-??*.md")
    meeting_files = glob.glob(pattern)

    # Sort by filename descending to get most recent
    meeting_files.sort(reverse=True)

    # Take the N most recent, then reverse to get oldest-first chronological order
    recent_meetings = meeting_files[:limit]
    recent_meetings.reverse()  # Now oldest first

    return recent_meetings


def read_meeting_content(file_paths: List[str]) -> str:
    """
    Read and concatenate meeting file contents.

    Args:
        file_paths: List of meeting file paths

    Returns:
        Concatenated meeting content with separators
    """
    content_parts = []

    for file_path in file_paths:
        filename = os.path.basename(file_path)
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
                content_parts.append(f"--- Meeting: {filename} ---\n{content}\n")
        except Exception as e:
            print(f"Warning: Could not read {filename}: {e}", file=sys.stderr)
            continue

    return "\n".join(content_parts)


def get_cross_meeting_context(vault_path: str, scope: str, lookback_days: int = 7) -> str:
    """
    Scan all meetings matching scope from the last N days for cross-meeting context.

    This is used for exec meetings where the leader needs context from across
    the organization (e.g., all IPMedia meetings from past week).

    Args:
        vault_path: Path to Obsidian vault root
        scope: Company/org scope (e.g., "IPMedia", "TP", "MT")
        lookback_days: How many days back to scan (default: 7)

    Returns:
        Concatenated meeting content from all matching meetings, with metadata headers
    """
    from datetime import timedelta

    # Calculate cutoff date
    cutoff_date = datetime.now() - timedelta(days=lookback_days)
    cutoff_str = cutoff_date.strftime("%Y-%m-%d")

    # Build path to scope's people directory
    scope_path = os.path.join(vault_path, "Business", "People", scope)

    if not os.path.isdir(scope_path):
        print(f"Warning: Scope directory not found: {scope_path}", file=sys.stderr)
        return ""

    # Find all person folders
    person_folders = []
    for item in os.listdir(scope_path):
        item_path = os.path.join(scope_path, item)
        if os.path.isdir(item_path) and not item.startswith('.'):
            meetings_dir = os.path.join(item_path, "Meetings")
            if os.path.isdir(meetings_dir):
                person_folders.append((item, meetings_dir))

    # Collect recent meetings across all people
    recent_meetings = []
    for person_name, meetings_dir in person_folders:
        # Find meeting files newer than cutoff
        pattern = os.path.join(meetings_dir, "????-??-??*.md")
        meeting_files = glob.glob(pattern)

        for meeting_file in meeting_files:
            # Extract date from filename
            filename = os.path.basename(meeting_file)
            date_match = filename[:10]  # YYYY-MM-DD

            if date_match >= cutoff_str:
                recent_meetings.append({
                    'person': person_name,
                    'date': date_match,
                    'path': meeting_file
                })

    # Sort by date (oldest first for chronological context)
    recent_meetings.sort(key=lambda m: m['date'])

    # Read and concatenate meeting content
    content_parts = []
    for meeting in recent_meetings:
        try:
            with open(meeting['path'], 'r', encoding='utf-8') as f:
                content = f.read()
                header = f"--- {meeting['date']} Meeting with {meeting['person']} ---"
                content_parts.append(f"{header}\n{content}\n")
        except Exception as e:
            print(f"Warning: Could not read {meeting['path']}: {e}", file=sys.stderr)
            continue

    if not content_parts:
        return ""

    summary = f"=== Cross-Meeting Context: {len(recent_meetings)} meetings from {scope} in last {lookback_days} days ===\n\n"
    return summary + "\n".join(content_parts)


def analyze_with_openai(meeting_content: str, classification: Dict[str, Any]) -> Dict[str, Any]:
    """
    Analyze meeting history using OpenAI GPT-4o-mini.

    Args:
        meeting_content: Concatenated meeting notes
        classification: Meeting classification details

    Returns:
        Analysis result with action items, topics, blockers, etc.
    """
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise ValueError("OPENAI_API_KEY not set in environment")

    client = OpenAI(api_key=api_key)

    participant = classification.get("participant", "unknown")
    company = classification.get("company", "unknown")

    prompt = f"""You are analyzing progressive meeting notes between Jeff Hamersly and {participant} ({company}).

CRITICAL INSTRUCTIONS - Read Carefully:

1. **Meeting Order**: The notes below are in CHRONOLOGICAL ORDER (oldest → newest). Read them like a story.

2. **Track Completion**: As you read chronologically, CHECK if action items from earlier meetings were:
   - Completed in later meetings (mentioned as done, shipped, resolved)
   - Discussed as ongoing progress
   - Never mentioned again (assume still open)

3. **Only Report OPEN Items**:
   - Do NOT include action items that were completed/resolved in later meetings
   - Only include items that are STILL OPEN based on the full chronological context
   - If an item was resolved, you can mention it briefly in "suggested_agenda" as "Follow up on [completed item] - how's it working?"

4. **Prioritize Recent Context**:
   - The MOST RECENT meeting (at the bottom) reflects current priorities
   - Earlier meetings show the progression and what led to current state

Meeting Notes (chronological - oldest to newest):
{meeting_content}

Your task: Extract ONLY the truly open/unresolved items and current context for the next meeting.

Provide a JSON response with the following structure:
{{
  "open_action_items": [
    {{
      "description": "Action item description (ONLY if still open/unresolved)",
      "owner": "Person responsible",
      "source_meeting": "YYYY-MM-DD meeting date",
      "days_open": estimated days since assigned,
      "priority": "high|medium|low"
    }}
  ],
  "recurring_topics": [
    {{
      "topic": "Topic name",
      "frequency": "How often it appears",
      "trend": "Getting better/worse/stable"
    }}
  ],
  "active_blockers": [
    {{
      "blocker": "What's blocking",
      "blocking": "What it's blocking",
      "impact": "Impact description",
      "resolution": "Potential resolution"
    }}
  ],
  "unresolved_threads": [
    {{
      "topic": "Unresolved question/topic",
      "raised_date": "YYYY-MM-DD",
      "context": "Brief context"
    }}
  ],
  "suggested_agenda": {{
    "must_discuss": ["Critical item 1", "Critical item 2"],
    "should_discuss": ["Important item 1", "Important item 2"],
    "could_discuss": ["Optional item 1", "Optional item 2"]
  }},
  "meeting_patterns": {{
    "frequency_days": estimated days between meetings,
    "last_meeting_date": "YYYY-MM-DD"
  }}
}}

Focus on actionable insights. If no information is available for a section, return an empty array or object.
"""

    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a meeting continuity assistant. Analyze meeting notes and extract actionable insights."},
                {"role": "user", "content": prompt}
            ],
            response_format={"type": "json_object"},
            temperature=0.3,
            max_completion_tokens=16000
        )

        # Check for refusal
        if hasattr(response.choices[0].message, 'refusal') and response.choices[0].message.refusal:
            raise ValueError(f"Model refused to respond: {response.choices[0].message.refusal}")

        raw_content = response.choices[0].message.content
        if not raw_content:
            raise ValueError("API returned empty response")

        analysis = json.loads(raw_content)
        return analysis

    except Exception as e:
        print(f"Error calling OpenAI API: {e}", file=sys.stderr)
        raise


def load_meeting_config(person_folder: str) -> Dict[str, Any]:
    """
    Load person-specific meeting configuration from .meeting-config.json

    Args:
        person_folder: Path to person's folder (e.g., Business/People/IPMedia/Ron)

    Returns: Dict with config or empty dict if not found
    """
    config_path = os.path.join(person_folder, ".meeting-config.json")

    if not os.path.exists(config_path):
        return {}

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
        print(f"✓ Loaded meeting config: use_cross_meeting_context={config.get('use_cross_meeting_context', False)}", file=sys.stderr)
        return config
    except Exception as e:
        print(f"Warning: Failed to load meeting config: {e}", file=sys.stderr)
        return {}


def main():
    parser = argparse.ArgumentParser(description="Analyze meeting history")
    parser.add_argument("--person-folder", required=True, help="Path to person folder")
    parser.add_argument("--classification", required=True, help="JSON classification from classify-meeting.py")
    parser.add_argument("--max-meetings", type=int, default=5, help="Maximum meetings to analyze")

    args = parser.parse_args()

    try:
        # Load environment
        load_environment()

        # Parse classification
        classification = json.loads(args.classification)

        # Load meeting config (for executive meetings with cross-context)
        meeting_config = load_meeting_config(args.person_folder)

        # Get meeting files
        meeting_files = get_meeting_files(args.person_folder, args.max_meetings)

        if not meeting_files:
            # No previous meetings - return empty analysis
            empty_analysis = {
                "open_action_items": [],
                "recurring_topics": [],
                "active_blockers": [],
                "unresolved_threads": [],
                "suggested_agenda": {
                    "must_discuss": ["Initial meeting - establish rapport and understand goals"],
                    "should_discuss": ["Background and context", "Expectations and working style"],
                    "could_discuss": ["Future meeting cadence"]
                },
                "meeting_patterns": {
                    "frequency_days": 0,
                    "last_meeting_date": None
                }
            }
            print(json.dumps(empty_analysis, indent=2))
            sys.exit(0)

        # Read meeting content
        meeting_content = read_meeting_content(meeting_files)

        # Add cross-meeting context for executive meetings if enabled
        if meeting_config.get('use_cross_meeting_context', False):
            print("✓ Cross-meeting context enabled - loading recent company meetings", file=sys.stderr)

            # Get vault path from OBSIDIAN_VAULT_PATH env var
            vault_path = os.getenv('OBSIDIAN_VAULT_PATH')
            if vault_path:
                scope = meeting_config.get('context_scope', 'IPMedia')
                lookback_days = meeting_config.get('context_lookback_days', 7)

                cross_context = get_cross_meeting_context(vault_path, scope, lookback_days)

                if cross_context:
                    print(f"  → Added context from {scope} meetings (last {lookback_days} days)", file=sys.stderr)
                    meeting_content += "\n\n" + cross_context
                else:
                    print(f"  → No cross-meeting context found for {scope}", file=sys.stderr)
            else:
                print("  → Warning: OBSIDIAN_VAULT_PATH not set, skipping cross-context", file=sys.stderr)

        # Analyze with OpenAI
        analysis = analyze_with_openai(meeting_content, classification)

        # Output result
        print(json.dumps(analysis, indent=2))
        sys.exit(0)

    except Exception as e:
        error_result = {
            "error": str(e),
            "open_action_items": [],
            "recurring_topics": [],
            "active_blockers": [],
            "unresolved_threads": [],
            "suggested_agenda": {
                "must_discuss": [],
                "should_discuss": [],
                "could_discuss": []
            },
            "meeting_patterns": {
                "frequency_days": 0,
                "last_meeting_date": None
            }
        }
        print(json.dumps(error_result, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
