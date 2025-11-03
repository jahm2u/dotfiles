#!/usr/bin/env python3
"""
Meeting Note Generator
Generates pre-filled meeting notes using AI analysis and templates.
"""

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path

from dotenv import load_dotenv
from openai import OpenAI


def load_environment():
    """Load environment variables from .env file."""
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


def get_template_path(meeting_type: str, vault_path: str) -> str:
    """
    Get template file path based on meeting type.

    Args:
        meeting_type: Type from classification (ipmedia_1on1, co_*_meeting, etc.)
        vault_path: Path to Obsidian vault

    Returns:
        Path to template file
    """
    # Default to 1on1 template
    template_name = "1on1-template.md"

    if "co_" in meeting_type and "_meeting" in meeting_type:
        template_name = "company-meeting-template.md"
    elif "team_" in meeting_type:
        template_name = "team-meeting-template.md"

    # Try multiple template locations
    template_locations = [
        os.path.join(vault_path, "bmad", "vault-ops", "templates", template_name),
        os.path.join(vault_path, "Templates", template_name),
        os.path.join(vault_path, "templates", template_name),
    ]

    for template_path in template_locations:
        if os.path.exists(template_path):
            return template_path

    # Return first location as default (will error later if not found)
    return template_locations[0]


def load_template(template_path: str) -> str:
    """Load template content."""
    try:
        with open(template_path, 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        # Return basic default template (Employee-First format)
        return """# {{date}} 1-on-1 with {{participant}}

## {{participant}}'s Agenda (Start here)

### What's on your mind today?


### Where are you stuck? What support do you need from me?
{{predicted_blockers}}

## Jeff's Agenda

### Critical Follow-ups (Accountability)
{{critical_items}}

### Strategic Discussion
{{questions}}

## Meeting Outcomes

### Decisions Made


### Action Items


### Next Meeting Topics












































## Post-Meeting Summary
_This section will be auto-filled from meeting transcript_

### Key Discussion Points

### Commitments Tracking

### Follow-up Required

"""


def generate_meeting_prep_content(continuity: dict, classification: dict, template_content: str) -> dict:
    """
    Generate Meeting Prep section content using two-stage OpenAI refinement.

    Stage 1: Already done by analyze-meeting-history.py (raw data extraction)
    Stage 2: Refine raw data into polished, prioritized, checkbox-ready content

    Args:
        continuity: Analysis from analyze-meeting-history.py
        classification: Classification from classify-meeting.py
        template_content: Template file content (for context-aware generation)

    Returns:
        dict with prep section content
    """
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise ValueError("OPENAI_API_KEY not set in environment")

    client = OpenAI(api_key=api_key)

    participant = classification.get("participant", "unknown")
    company = classification.get("company", "unknown")

    # Serialize continuity data for GPT to refine
    continuity_json = json.dumps(continuity, indent=2)

    prompt = f"""You are preparing Jeff Hamersly for a 1-on-1 meeting with {participant} from {company}.

Transform raw meeting analysis into a CLEAN, NON-REPETITIVE meeting agenda. Jeff hates redundancy.

RAW ANALYSIS DATA:
{continuity_json}

CRITICAL RULES - READ CAREFULLY:
1. **ZERO REPETITION** - Each topic appears ONCE in the most appropriate section. If "Update backlog" is in Critical, it CANNOT appear in Questions, Topics, or Follow-ups.
2. **Critical = Blockers + Very Overdue (100+ days)** - Only truly urgent items here.
3. **Questions = NEW discussion angles** - NOT "status updates" on critical items. Ask about NEW topics, future plans, opinions.
4. **Topics = High-level themes** - NOT specific action items already in Critical.
5. **Follow-ups = Recent items NOT in Critical** - Only include if < 30 days old AND not already mentioned above.
6. **Checkboxes everywhere** - Use `- [ ]` format.

Generate JSON:

{{
  "predicted_blockers": "Checkbox list of 2-3 likely blockers based on analysis. Predict what {participant} is probably stuck on right now based on overdue items, active blockers, and recurring problem areas. Format: '[ ] [Specific blocker description]'. Be specific, not generic.",

  "critical_items": "Checkbox list of very overdue accountability items (100+ days) that Jeff needs to follow up on. Format as questions: '[ ] [Item] (X days) - Status?'. These are Jeff's accountability questions. If item appears here, it MUST NOT appear in predicted_blockers.",

  "questions": "Checkbox list of 3-5 strategic, open-ended questions for discussion. Focus on future planning, opinions, new concerns. DO NOT ask status updates on critical_items. Make them thoughtful and specific to the context.",

  "context": "1-2 sentences summarizing last meeting outcome."
}}

BAD EXAMPLE (has repetition):
{{
  "critical_items": "- [ ] Update backlog (174 days)",
  "questions": "- [ ] Status on backlog?",  ← WRONG! Backlog already in critical
  "followups": "- [ ] Update backlog - 174 days"  ← WRONG! Already in critical
}}

GOOD EXAMPLE (zero repetition):
{{
  "predicted_blockers": "- [ ] Waiting on Daniel's input for infrastructure roadmap alignment\\n- [ ] Lack of team capacity to complete overdue backlog items\\n- [ ] Need prioritization guidance on RFC vs migration work",
  "critical_items": "- [ ] SD user access backlog update (174 days) - Status?\\n- [ ] RFC for image limits (174 days) - Status?",
  "questions": "- [ ] What's your vision for team structure in Q1?\\n- [ ] How should we prioritize infrastructure debt vs new features?\\n- [ ] What would make your job easier right now?",
  "context": "Last meeting: aligned on infrastructure priorities. Marcus committed to backlog update."
}}

NOW GENERATE - REMEMBER: Each item appears ONCE ONLY. Predict specific blockers based on the data."""

    try:
        response = client.chat.completions.create(
            model="gpt-5-mini",
            messages=[
                {"role": "system", "content": "You are an expert meeting prep assistant. You prioritize ruthlessly, eliminate repetition, and generate checkbox-ready content."},
                {"role": "user", "content": prompt}
            ],
            response_format={"type": "json_object"},
            temperature=0.5,
            max_tokens=2500
        )

        content = json.loads(response.choices[0].message.content)
        return content

    except Exception as e:
        print(f"Error calling OpenAI API: {e}", file=sys.stderr)
        # Return default content with checkboxes
        return {
            "predicted_blockers": "- [ ] Need clarity on priorities\n- [ ] Waiting on dependencies from other teams",
            "critical_items": "- [ ] Review open action items from previous meetings",
            "questions": "- [ ] What are your top priorities this week?\n- [ ] Any blockers I can help with?\n- [ ] How is [ongoing project] progressing?",
            "context": "First meeting - establish rapport and understand goals."
        }


def calculate_next_meeting_date(meeting_patterns: dict, current_date: str) -> str:
    """Calculate next meeting date based on frequency pattern."""
    frequency_days = meeting_patterns.get("frequency_days", 7)

    from datetime import datetime, timedelta

    current = datetime.strptime(current_date, "%Y-%m-%d")
    next_meeting = current + timedelta(days=frequency_days)

    return next_meeting.strftime("%Y-%m-%d")


def generate_wikilink(path: str, display: str = None) -> str:
    """Generate Obsidian wikilink format."""
    if display:
        return f"[[{path}|{display}]]"
    return f"[[{path}]]"


def determine_save_path(classification: dict, person_folder: str, date: str, vault_path: str) -> str:
    """
    Determine where to save the meeting note based on classification.

    Args:
        classification: Classification from classify-meeting.py
        person_folder: Path to person folder
        date: Meeting date (YYYY-MM-DD)
        vault_path: Obsidian vault path

    Returns:
        Absolute path where note should be saved
    """
    meeting_type = classification.get("meeting_type", "unknown")
    company = classification.get("company", "unknown")
    participant = classification.get("participant", "unknown")

    if "1on1" in meeting_type:
        # 1-on-1: {person_folder}/Meetings/{date} 1on1.md
        meetings_dir = os.path.join(person_folder, "Meetings")
        os.makedirs(meetings_dir, exist_ok=True)
        return os.path.join(meetings_dir, f"{date} 1on1.md")

    elif "co_" in meeting_type and "_meeting" in meeting_type:
        # Company: Business/CO/{Company}/Meetings/{date} {Company} Weekly.md
        meetings_dir = os.path.join(vault_path, "Business", "CO", company, "Meetings")
        os.makedirs(meetings_dir, exist_ok=True)
        return os.path.join(meetings_dir, f"{date} {company} Weekly.md")

    elif "team_" in meeting_type:
        # Team: Business/People/IPMedia/Teams/{Team}/{date} {Team} Meeting.md
        team_name = meeting_type.replace("ipmedia_team_", "").replace("_", " ").title()
        meetings_dir = os.path.join(vault_path, "Business", "People", "IPMedia", "Teams", team_name)
        os.makedirs(meetings_dir, exist_ok=True)
        return os.path.join(meetings_dir, f"{date} {team_name} Meeting.md")

    else:
        # Default to person folder
        meetings_dir = os.path.join(person_folder, "Meetings")
        os.makedirs(meetings_dir, exist_ok=True)
        return os.path.join(meetings_dir, f"{date} Meeting.md")


def main():
    parser = argparse.ArgumentParser(description="Generate meeting note")
    parser.add_argument("--classification", required=True, help="JSON classification")
    parser.add_argument("--person-folder", required=True, help="Path to person folder")
    parser.add_argument("--continuity", required=True, help="JSON continuity analysis")
    parser.add_argument("--date", help="Meeting date (YYYY-MM-DD), default: today")

    args = parser.parse_args()

    try:
        # Load environment
        load_environment()

        vault_path = os.getenv("OBSIDIAN_VAULT_PATH")
        if not vault_path:
            raise ValueError("OBSIDIAN_VAULT_PATH not set in environment")

        # Parse inputs
        classification = json.loads(args.classification)
        continuity = json.loads(args.continuity)

        meeting_date = args.date or datetime.now().strftime("%Y-%m-%d")
        participant = classification.get("participant", "Unknown")

        # Load template
        template_path = get_template_path(classification["meeting_type"], vault_path)
        template_content = load_template(template_path)

        # Generate prep content with AI (two-stage refinement)
        prep_content = generate_meeting_prep_content(continuity, classification, template_content)

        # Calculate next meeting date
        next_meeting = calculate_next_meeting_date(
            continuity.get("meeting_patterns", {}),
            meeting_date
        )

        # Replace template variables
        note_content = template_content.replace("{{date}}", meeting_date)
        note_content = note_content.replace("{{participant}}", participant)
        note_content = note_content.replace("{{company}}", classification.get("company", ""))
        note_content = note_content.replace("{{next_meeting}}", next_meeting)

        # Replace prep sections (ensure all values are strings)
        def ensure_string(value):
            """Convert value to string, handling lists and None."""
            if value is None:
                return ""
            if isinstance(value, list):
                return "\n".join([f"- {item}" if not str(item).startswith("-") else str(item) for item in value])
            return str(value)

        note_content = note_content.replace("{{predicted_blockers}}", ensure_string(prep_content.get("predicted_blockers", "")))
        note_content = note_content.replace("{{critical_items}}", ensure_string(prep_content.get("critical_items", "")))
        note_content = note_content.replace("{{questions}}", ensure_string(prep_content.get("questions", "")))
        note_content = note_content.replace("{{context}}", ensure_string(prep_content.get("context", "")))

        # Determine save path
        save_path = determine_save_path(classification, args.person_folder, meeting_date, vault_path)

        # Write file
        with open(save_path, 'w', encoding='utf-8') as f:
            f.write(note_content)

        # Return result
        result = {
            "file_path": os.path.relpath(save_path, vault_path),
            "full_path": save_path,
            "date": meeting_date,
            "success": True
        }

        print(json.dumps(result, indent=2))
        sys.exit(0)

    except Exception as e:
        error_result = {
            "error": str(e),
            "file_path": "",
            "full_path": "",
            "date": "",
            "success": False
        }
        print(json.dumps(error_result, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
