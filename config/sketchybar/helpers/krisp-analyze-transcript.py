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
        # Note: Cross-meeting context happens in PREP (meeting-prep.sh), not here
        # This just analyzes what was DISCUSSED in this meeting
        prompt = f"""You are analyzing an executive 1on1 meeting transcript.

**Meeting Context:**
- Participants: {meeting_context['person_name']}, Jeff Hamersly
- Company: {meeting_context['company']}
- Date: {meeting_context['date']}

**Meeting Transcript:**
```
{transcript_text}
```

**Instructions:**
Analyze this executive meeting transcript and extract comprehensive post-meeting information:

1. **Discussion Highlights** - Extract 5-8 key points covering ALL major topics discussed
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
        # Standard prompt for regular 1on1s - comprehensive analysis
        prompt = f"""You are analyzing a meeting transcript to create comprehensive post-meeting documentation.

**Meeting Context:**
- Participants: {meeting_context['person_name']}, Jeff Hamersly
- Company: {meeting_context['company']}
- Meeting Type: {meeting_context['meeting_type']}
- Date: {meeting_context['date']}

**Meeting Transcript:**
```
{transcript_text}
```

**Instructions:**
Analyze this meeting thoroughly. This was a meaningful conversation - capture ALL the substance, not just surface-level points.

Extract the following with DEPTH and DETAIL:

1. **Discussion Highlights** - Extract 6-12 substantive points covering EVERY major topic discussed. Include:
   - What was the issue/topic?
   - What perspectives were shared?
   - What was the conclusion or current state?

2. **Action Items** - ALL specific tasks, commitments, or follow-ups mentioned (use [[PersonName]] format)
   - Include both explicit commitments and implied next steps
   - Be specific about what needs to be done

3. **Key Insights & Quotes** - 3-6 significant insights, observations, or memorable quotes
   - Include direct quotes when impactful
   - Capture wisdom or realizations from the conversation

4. **Decisions Made** - Any decisions reached, even tentative ones

5. **Blockers Identified** - Obstacles, frustrations, challenges discussed

6. **Topics to Review Next Time** - 3-6 follow-up topics for future meetings

7. **Related Context** - Obsidian wikilinks to projects/people mentioned

Output ONLY a JSON object:
{{
  "discussion_highlights": ["detailed point 1 with context", "detailed point 2", ...],
  "action_items": {{
    "[[{meeting_context['person_name']}]]": ["specific task 1", "specific task 2"],
    "[[Jeff Hamersly]]": ["task 1"]
  }},
  "key_insights": ["insight or quote 1", "insight 2"],
  "decisions": ["decision 1"],
  "blockers": ["blocker with context"],
  "topics_next_time": ["topic 1", "topic 2", "topic 3"],
  "related_context": ["[[Project/Name]]", "[[Person/Name]]"]
}}

IMPORTANT: Be THOROUGH. A 30-minute conversation has many discussion points - capture them all."""

    # Retry logic with exponential backoff (AC #4, #8)
    client = OpenAI(api_key=api_key)

    # Dynamic token scaling based on transcript size
    # Longer meetings = richer discussions = need more output tokens
    transcript_chars = len(transcript_text)
    transcript_kb = transcript_chars / 1024

    if transcript_kb >= 60:       # 60KB+ = very long meeting (1+ hour)
        base_tokens = 12000
    elif transcript_kb >= 40:     # 40-60KB = long meeting (45+ min)
        base_tokens = 10000
    elif transcript_kb >= 25:     # 25-40KB = medium meeting (30+ min)
        base_tokens = 8000
    elif transcript_kb >= 15:     # 15-25KB = shorter meeting (15-30 min)
        base_tokens = 6000
    else:                         # <15KB = quick sync
        base_tokens = 4000

    # Executive meetings get 25% bonus for comprehensive strategic analysis
    max_tokens = int(base_tokens * 1.25) if is_executive else base_tokens

    log(f"Transcript size: {transcript_kb:.1f}KB → max_tokens={max_tokens} (executive={is_executive})")

    for attempt in range(max_retries):
        try:
            timeout = 60 if transcript_kb < 40 else 120  # Longer timeout for big transcripts

            log(f"Calling OpenAI API (attempt {attempt + 1}/{max_retries})...")

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

            # Validate structure - all meetings now get comprehensive analysis
            required_fields = ['discussion_highlights', 'action_items', 'topics_next_time']
            # Optional fields that enhance the analysis (don't fail if missing)
            optional_fields = ['key_insights', 'decisions', 'blockers', 'growth_development', 'business_impact', 'related_context']

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
