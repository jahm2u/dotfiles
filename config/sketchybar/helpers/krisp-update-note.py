#!/usr/bin/env python3
"""
Krisp Note Updater
Updates Obsidian meeting notes with AI analysis results by filling post-meeting sections.

Author: Jeff Hamersly
Date: 2025-11-02
Story: 4-3 - AI Analysis & Note Integration
"""

import argparse
import json
import sys
import re
import time
from pathlib import Path
from datetime import datetime

LOG_FILE = Path.home() / ".config/sketchybar/logs/krisp-automation.log"
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)


def log(message, level="INFO"):
    """Log message to file and stderr"""
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"[{timestamp}] [{level}] {message}"
    print(log_line, file=sys.stderr)
    with open(LOG_FILE, "a") as f:
        f.write(log_line + "\n")


def update_meeting_note(note_path, analysis, transcript_rel_path, metadata):
    """
    Update meeting note with AI analysis by filling post-meeting sections (AC #5).

    Instead of appending a new section, this fills out the existing post-meeting
    sections that were created by Story 4-1's meeting prep workflow.

    Args:
        note_path: Path to meeting note file
        analysis: Dict with discussion_highlights, action_items, topics_next_time, related_context
        transcript_rel_path: Relative path to transcript for wikilink
        metadata: Dict with meeting_duration, processed_at

    Returns: True on success, False on failure
    """
    try:
        # Read existing note
        note_content = Path(note_path).read_text()

        # Build formatted post-meeting content
        formatted_content = build_post_meeting_content(analysis, transcript_rel_path, metadata)

        # Find and replace post-meeting sections
        updated_content = fill_post_meeting_sections(note_content, formatted_content)

        # Write atomically (temp file + rename)
        temp_path = Path(note_path).with_suffix('.tmp')
        temp_path.write_text(updated_content)
        temp_path.replace(note_path)

        log(f"✓ Updated note: {note_path}")
        return True

    except Exception as e:
        log(f"Failed to update note: {str(e)}", "ERROR")
        return False


def build_post_meeting_content(analysis, transcript_rel_path, metadata):
    """
    Build formatted markdown content for post-meeting sections (append strategy).

    Returns: Dict mapping section names to formatted content with separators
    """
    content = {}
    processed = metadata.get('processed_at', datetime.now().strftime('%Y-%m-%d %H:%M'))

    # Add timestamp separator for appended content
    separator = f"\n\n---\n**🤖 AI-Generated from Transcript** (Added: {processed})\n"

    # Map discussion_highlights to "Notes During Meeting" section
    if analysis.get('discussion_highlights'):
        highlights = '\n'.join(f"- {h}" for h in analysis['discussion_highlights'])
        content['notes_during_meeting'] = separator + highlights

    # Action Items (maps directly to "Action Items" section)
    if analysis.get('action_items'):
        action_lines = []
        for person, items in analysis['action_items'].items():
            if items:
                action_lines.append(f"\n**{person}:**")
                for item in items:
                    action_lines.append(f"- [ ] {item}")
        content['action_items'] = separator + '\n'.join(action_lines)

    # Topics Next Time (can be added as follow-up items)
    if analysis.get('topics_next_time'):
        topics_text = "**Topics to Revisit:**\n" + '\n'.join(f"- {t}" for t in analysis['topics_next_time'])
        content['topics_next_time'] = separator + topics_text

    # Related Context (maps to Related Documents section)
    if analysis.get('related_context') and analysis['related_context']:
        context = '\n'.join(f"- {link}" for link in analysis['related_context'])
        content['related_context'] = separator + context

    # Executive-specific sections
    if analysis.get('key_insights'):
        insights = '\n'.join(f"- {insight}" for insight in analysis['key_insights'])
        content['key_insights'] = separator + insights

    if analysis.get('decisions'):
        decisions = '\n'.join(f"- {decision}" for decision in analysis['decisions'])
        content['decisions'] = separator + decisions

    if analysis.get('blockers'):
        blockers = '\n'.join(f"- {blocker}" for blocker in analysis['blockers'])
        content['blockers'] = separator + blockers

    if analysis.get('growth_development'):
        growth = '\n'.join(f"- {item}" for item in analysis['growth_development'])
        content['growth_development'] = separator + growth

    if analysis.get('business_impact'):
        impact = '\n'.join(f"- {item}" for item in analysis['business_impact'])
        content['business_impact'] = separator + impact

    # Transcript reference (goes at end of note, not in a section)
    if transcript_rel_path:
        duration = metadata.get('meeting_duration', 'Unknown')
        transcript_section = f"""---
**Original Transcript:** [[{transcript_rel_path}|View Transcript]]
**Meeting Duration:** {duration}
**Transcript Processed:** {processed}"""
        content['transcript_reference'] = transcript_section

    return content


def fill_post_meeting_sections(note_content, formatted_content):
    """
    Append AI-generated content to post-meeting sections (Option 2: Append strategy).

    Strategy: Find section headers and append the new content after existing content,
    preserving any manual notes. Adds timestamp separator to distinguish AI content.

    Expected sections (works with both template types):
    - ### 🎯 Discussion Highlights (or similar variants)
    - ### ✅ Action Items Captured (or "Action Items")
    - ### 💡 Topics to Review Next Time (or similar)
    - ### 🔗 Related Context

    Returns: Updated note content
    """
    updated = note_content

    # Define section patterns for appending
    # Pattern: Match header + content up to (but not including) next ### header
    # We'll append to the existing content rather than replace it
    sections = [
        {
            'pattern': r'(### Notes During Meeting)\s*\n((?:(?!^###).)*)',
            'replacement': formatted_content.get('notes_during_meeting', ''),
            'key': 'notes_during_meeting'
        },
        {
            'pattern': r'(### Action Items)\s*\n((?:(?!^###).)*)',
            'replacement': formatted_content.get('action_items', ''),
            'key': 'action_items'
        },
        {
            'pattern': r'(### Key Insights & Quotes)\s*\n((?:(?!^###).)*)',
            'replacement': formatted_content.get('key_insights', ''),
            'key': 'key_insights'
        },
        {
            'pattern': r'(### Decisions Made)\s*\n((?:(?!^###).)*)',
            'replacement': formatted_content.get('decisions', ''),
            'key': 'decisions'
        },
        {
            'pattern': r'(### Blockers Identified)\s*\n((?:(?!^###).)*)',
            'replacement': formatted_content.get('blockers', ''),
            'key': 'blockers'
        },
        {
            'pattern': r'(### Growth & Development)\s*\n((?:(?!^###).)*)',
            'replacement': formatted_content.get('growth_development', ''),
            'key': 'growth_development'
        },
        {
            'pattern': r'(### Business Impact)\s*\n((?:(?!^###).)*)',
            'replacement': formatted_content.get('business_impact', ''),
            'key': 'business_impact'
        },
        {
            'pattern': r'(### Related Documents)\s*\n((?:(?!^###).)*)',
            'replacement': formatted_content.get('related_context', ''),
            'key': 'related_context'
        },
    ]

    # Append to each section - pattern matches header + existing content
    for section in sections:
        if section['replacement']:
            # Append strategy: (header)(newline)(existing_content)(new_content)(newline)
            updated = re.sub(
                section['pattern'],
                lambda m: m.group(1) + '\n' + m.group(2).rstrip() + section['replacement'] + '\n',
                updated,
                flags=re.MULTILINE | re.DOTALL
            )

    # Add topics for next time at the end (before transcript reference)
    if formatted_content.get('topics_next_time'):
        if 'Topics to Revisit:' not in updated:
            updated += '\n\n' + formatted_content['topics_next_time']

    # Add transcript reference at the end if not already present
    if formatted_content.get('transcript_reference'):
        if 'Original Transcript:' not in updated:
            updated += '\n\n' + formatted_content['transcript_reference']

    return updated


def main():
    parser = argparse.ArgumentParser(
        description='Update Obsidian meeting note with AI analysis'
    )
    parser.add_argument(
        '--note',
        required=True,
        help='Path to meeting note file'
    )
    parser.add_argument(
        '--analysis',
        required=False,
        help='Path to analysis JSON file (use "-" to read from stdin)'
    )
    parser.add_argument(
        '--transcript-path',
        help='Relative path to transcript for wikilink (e.g., attachments/2024-11-02-kyle-slack-transcript.txt)'
    )
    parser.add_argument(
        '--duration',
        default='Unknown',
        help='Meeting duration (e.g., "45 minutes")'
    )

    args = parser.parse_args()

    # Load analysis from stdin, file, or direct JSON string
    try:
        if args.analysis is None or args.analysis == '-':
            # Read from stdin
            analysis = json.load(sys.stdin)
        elif Path(args.analysis).is_file():
            # Read from file
            analysis = json.loads(Path(args.analysis).read_text())
        else:
            # Try parsing as direct JSON string (for small payloads)
            analysis = json.loads(args.analysis)
    except Exception as e:
        log(f"Failed to load analysis: {str(e)}", "ERROR")
        sys.exit(1)

    # Metadata
    metadata = {
        'meeting_duration': args.duration,
        'processed_at': datetime.now().strftime('%Y-%m-%d %H:%M')
    }

    # Update note
    success = update_meeting_note(
        args.note,
        analysis,
        args.transcript_path,
        metadata
    )

    if success:
        print(f"✓ Note updated: {args.note}")
        sys.exit(0)
    else:
        print("✗ Failed to update note", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
