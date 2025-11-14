#!/usr/bin/env python3
"""
Krisp Transcript AI Analysis
Analyzes meeting transcripts using OpenAI GPT-4o-mini and fills out post-meeting sections in existing notes.

Author: Jeff Hamersly
Date: 2025-11-02
Story: 4-3 - AI Analysis & Note Integration
"""

import argparse
import json
import sys
import os
import time
from pathlib import Path
from openai import OpenAI
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


def log(message, level="INFO"):
    """Log message to file and stderr"""
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"[{timestamp}] [{level}] {message}"
    print(log_line, file=sys.stderr)
    with open(LOG_FILE, "a") as f:
        f.write(log_line + "\n")


def analyze_transcript_with_note(transcript_path, note_path, meeting_context, max_retries=3):
    """
    Analyze transcript and fill out post-meeting section in existing note (AC #4).

    Args:
        transcript_path: Path to transcript file
        note_path: Path to existing meeting note
        meeting_context: Dict with person_name, company, meeting_type, date
        max_retries: Max retry attempts with exponential backoff

    Returns: Dict with filled post-meeting sections or None on failure
    """
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        log("OPENAI_API_KEY not set in environment", "ERROR")
        return None

    # Read transcript
    try:
        transcript_text = Path(transcript_path).read_text()
    except Exception as e:
        log(f"Failed to read transcript: {str(e)}", "ERROR")
        return None

    # Read existing note
    try:
        note_text = Path(note_path).read_text()
    except Exception as e:
        log(f"Failed to read note: {str(e)}", "ERROR")
        return None

    # Build AI prompt - different for executive meetings
    is_executive = meeting_context.get('meeting_type') == 'ipmedia_executive'

    if is_executive:
        # Enhanced prompt for Ron/executive meetings
        prompt = f"""You are analyzing an executive 1on1 meeting transcript between a CEO (Ron) and CTO (Jeff Hamersly).

**Meeting Context:**
- CEO: {meeting_context['person_name']}
- CTO: Jeff Hamersly
- Company: {meeting_context['company']}
- Date: {meeting_context['date']}

**Existing Meeting Note:**
```
{note_text}
```

**Meeting Transcript:**
```
{transcript_text}
```

**Instructions:**
This is a strategic executive meeting. Fill out ALL the post-meeting sections comprehensively based on the transcript:

1. **Discussion Highlights** - Extract 5-8 key points covering all major topics discussed
2. **Action Items** - All specific tasks with owners (use [[PersonName]] format)
3. **Key Insights & Quotes** - 3-5 significant insights or memorable quotes from the discussion
4. **Decisions Made** - Clear decisions reached during the meeting
5. **Blockers Identified** - Any obstacles, challenges, or issues raised
6. **Growth & Development** - Topics related to team growth, hiring, development
7. **Business Impact** - Strategic business implications, metrics, or outcomes discussed
8. **Topics to Review Next Time** - 3-5 follow-up topics for next meeting
9. **Related Context** - Obsidian wikilinks to projects/people mentioned

Output ONLY a JSON object with these fields:
{{
  "discussion_highlights": ["point 1 covering topic A", "point 2 covering topic B", "..."],
  "action_items": {{
    "[[{meeting_context['person_name']}]]": ["task 1", "task 2"],
    "[[Jeff Hamersly]]": ["task 1"]
  }},
  "key_insights": ["insight 1", "quote: '...'", "..."],
  "decisions": ["decision 1", "decision 2"],
  "blockers": ["blocker 1 with context", "blocker 2"],
  "growth_development": ["hiring for X role", "team Y needs Z"],
  "business_impact": ["metric X changed", "strategic implication Y"],
  "topics_next_time": ["topic 1", "topic 2", "topic 3"],
  "related_context": ["[[Project/Name]]", "[[Team/Name]]"]
}}

IMPORTANT:
- Cover ALL topics from the transcript, not just a few
- Extract specific details and context for each item
- Avoid repetition - each point should cover a distinct topic
- Be comprehensive - this is an important strategic meeting"""
    else:
        # Standard prompt for regular 1on1s
        prompt = f"""You are analyzing a meeting transcript to fill out the post-meeting sections of a meeting note.

**Meeting Context:**
- Participants: {meeting_context['person_name']}, Jeff Hamersly
- Company: {meeting_context['company']}
- Meeting Type: {meeting_context['meeting_type']}
- Date: {meeting_context['date']}

**Existing Meeting Note:**
```
{note_text}
```

**Meeting Transcript:**
```
{transcript_text}
```

**Instructions:**
The meeting note above has empty post-meeting sections that need to be filled out. Based on the transcript, please fill in:

1. **Discussion Highlights** - 3-5 main points discussed
2. **Action Items Captured** - Specific tasks with owners (use [[PersonName]] format for Obsidian wikilinks)
3. **Topics to Review Next Time** - 2-4 follow-up topics for next meeting
4. **Related Context** - Obsidian wikilinks to related projects/people mentioned (if any)

Output ONLY a JSON object with these fields:
{{
  "discussion_highlights": ["point 1", "point 2", "point 3"],
  "action_items": {{
    "[[PersonName]]": ["task 1", "task 2"],
    "[[Jeff Hamersly]]": ["task 1"]
  }},
  "topics_next_time": ["topic 1", "topic 2"],
  "related_context": ["[[Project/Name]]", "[[Person/Name]]"]
}}

Be specific and actionable. Extract actual commitments from the transcript."""

    # Retry logic with exponential backoff (AC #4, #8)
    client = OpenAI(api_key=api_key)

    for attempt in range(max_retries):
        try:
            timeout = 30 if attempt == 0 else 60  # Increase timeout on retries

            log(f"Calling OpenAI API (attempt {attempt + 1}/{max_retries})...")

            # Executive meetings need more tokens for comprehensive analysis
            max_tokens = 3000 if is_executive else 1500

            response = client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {"role": "system", "content": "You are a meeting analysis assistant that extracts structured information from transcripts."},
                    {"role": "user", "content": prompt}
                ],
                temperature=0.3,
                max_completion_tokens=max_tokens,
                timeout=timeout
            )

            # Extract JSON from response
            content = response.choices[0].message.content.strip()

            # Remove markdown code blocks if present
            if content.startswith("```"):
                content = content.split("```")[1]
                if content.startswith("json"):
                    content = content[4:]
                content = content.strip()

            analysis = json.loads(content)

            # Validate structure based on meeting type
            if is_executive:
                required_fields = ['discussion_highlights', 'action_items', 'key_insights',
                                 'decisions', 'blockers', 'growth_development', 'business_impact', 'topics_next_time']
            else:
                required_fields = ['discussion_highlights', 'action_items', 'topics_next_time']

            if not all(field in analysis for field in required_fields):
                raise ValueError(f"Missing required fields in analysis: {required_fields}")

            log("✓ OpenAI analysis successful")

            # Log API usage
            usage = response.usage
            log(f"API usage: {usage.prompt_tokens} prompt + {usage.completion_tokens} completion = {usage.total_tokens} tokens")
            cost = (usage.prompt_tokens * 0.00015 + usage.completion_tokens * 0.0006) / 1000
            log(f"Estimated cost: ${cost:.4f}")

            return analysis

        except json.JSONDecodeError as e:
            log(f"Failed to parse AI response as JSON: {str(e)}", "ERROR")
            log(f"Raw response: {content[:500]}", "ERROR")

            if attempt < max_retries - 1:
                delay = 2 ** attempt  # 2s, 4s, 8s
                log(f"Retrying in {delay} seconds...", "WARN")
                time.sleep(delay)
            else:
                log("Max retries exceeded for JSON parsing", "ERROR")
                return None

        except Exception as e:
            log(f"OpenAI API error: {str(e)}", "ERROR")

            if attempt < max_retries - 1:
                delay = 2 ** attempt  # 2s, 4s, 8s
                log(f"Retrying in {delay} seconds...", "WARN")
                time.sleep(delay)
            else:
                log("Max retries exceeded for API call", "ERROR")
                return None

    return None


def main():
    parser = argparse.ArgumentParser(
        description='Analyze transcript with AI and fill out meeting note'
    )
    parser.add_argument(
        '--transcript',
        required=True,
        help='Path to transcript file'
    )
    parser.add_argument(
        '--note',
        required=True,
        help='Path to existing meeting note'
    )
    parser.add_argument(
        '--person',
        required=True,
        help='Person name (e.g., "Kyle Smith")'
    )
    parser.add_argument(
        '--company',
        required=True,
        help='Company name (e.g., "IPMedia")'
    )
    parser.add_argument(
        '--meeting-type',
        required=True,
        help='Meeting type (1on1, company, team)'
    )
    parser.add_argument(
        '--date',
        required=True,
        help='Meeting date (YYYY-MM-DD)'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output result as JSON'
    )

    args = parser.parse_args()

    meeting_context = {
        'person_name': args.person,
        'company': args.company,
        'meeting_type': args.meeting_type,
        'date': args.date
    }

    result = analyze_transcript_with_note(
        args.transcript,
        args.note,
        meeting_context
    )

    if result:
        if args.json:
            print(json.dumps(result, indent=2))
        else:
            print("✓ Analysis successful")
            print(f"\nDiscussion Highlights ({len(result['discussion_highlights'])}):")
            for highlight in result['discussion_highlights']:
                print(f"  • {highlight}")

            print(f"\nAction Items:")
            for person, items in result['action_items'].items():
                print(f"  {person}:")
                for item in items:
                    print(f"    - {item}")

            print(f"\nTopics Next Time ({len(result['topics_next_time'])}):")
            for topic in result['topics_next_time']:
                print(f"  • {topic}")

            if 'related_context' in result and result['related_context']:
                print(f"\nRelated Context:")
                for link in result['related_context']:
                    print(f"  • {link}")

        sys.exit(0)
    else:
        print("✗ Analysis failed", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
