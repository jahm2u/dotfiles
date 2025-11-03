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
            model="gpt-5-mini",
            messages=[
                {"role": "system", "content": "You are a meeting continuity assistant. Analyze meeting notes and extract actionable insights."},
                {"role": "user", "content": prompt}
            ],
            response_format={"type": "json_object"},
            temperature=0.3,
            max_tokens=3000
        )

        analysis = json.loads(response.choices[0].message.content)
        return analysis

    except Exception as e:
        print(f"Error calling OpenAI API: {e}", file=sys.stderr)
        raise


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
