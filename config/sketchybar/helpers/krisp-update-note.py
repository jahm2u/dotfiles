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
    Build formatted markdown content for post-meeting sections.

    Returns: Dict mapping section names to formatted content
    """
    content = {}

    # Discussion Highlights
    if analysis.get('discussion_highlights'):
        highlights = '\n'.join(f"- {h}" for h in analysis['discussion_highlights'])
        content['discussion_highlights'] = highlights

    # Action Items
    if analysis.get('action_items'):
        action_lines = []
        for person, items in analysis['action_items'].items():
            if items:
                action_lines.append(f"\n**{person}:**")
                for item in items:
                    action_lines.append(f"- [ ] {item}")
        content['action_items'] = '\n'.join(action_lines)

    # Topics Next Time
    if analysis.get('topics_next_time'):
        topics = '\n'.join(f"- {t}" for t in analysis['topics_next_time'])
        content['topics_next_time'] = topics

    # Related Context
    if analysis.get('related_context') and analysis['related_context']:
        context = '\n'.join(f"- {link}" for link in analysis['related_context'])
        content['related_context'] = context

    # Transcript reference
    if transcript_rel_path:
        duration = metadata.get('meeting_duration', 'Unknown')
        processed = metadata.get('processed_at', datetime.now().strftime('%Y-%m-%d %H:%M'))
        transcript_section = f"""---
**Original Transcript:** [[{transcript_rel_path}|View Transcript]]
**Meeting Duration:** {duration}
**Transcript Processed:** {processed}"""
        content['transcript_reference'] = transcript_section

    return content


def fill_post_meeting_sections(note_content, formatted_content):
    """
    Fill empty post-meeting sections in the note with formatted content.

    Strategy: Find section headers and replace the content between them with
    the new formatted content.

    Expected sections in Story 4-1 template:
    - ### 🎯 Discussion Highlights
    - ### ✅ Action Items Captured
    - ### 💡 Topics to Review Next Time
    - ### 🔗 Related Context

    Returns: Updated note content
    """
    updated = note_content

    # Define section patterns and replacements
    # Pattern explanation: Match header + content up to (but not including) next ### header
    # Use negative lookahead to ensure we don't match lines starting with ###
    sections = [
        {
            'pattern': r'(### 🎯 Discussion Highlights)\s*\n((?:(?!^###).)*)',
            'replacement': formatted_content.get('discussion_highlights', ''),
            'key': 'discussion_highlights'
        },
        {
            'pattern': r'(### ✅ Action Items Captured)\s*\n((?:(?!^###).)*)',
            'replacement': formatted_content.get('action_items', ''),
            'key': 'action_items'
        },
        {
            'pattern': r'(### 💡 Topics to Review Next Time)\s*\n((?:(?!^###).)*)',
            'replacement': formatted_content.get('topics_next_time', ''),
            'key': 'topics_next_time'
        },
        {
            'pattern': r'(### 🔗 Related Context)\s*\n((?:(?!^###).)*)',
            'replacement': formatted_content.get('related_context', ''),
            'key': 'related_context'
        },
    ]

    # Replace each section - pattern matches header + old content (stops at next ###)
    for section in sections:
        if section['replacement']:
            # Replace with: (header)(newline)(new_content)(newline)
            updated = re.sub(
                section['pattern'],
                lambda m: m.group(1) + '\n\n' + section['replacement'] + '\n',
                updated,
                flags=re.MULTILINE | re.DOTALL
            )

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
        required=True,
        help='Path to analysis JSON file or JSON string'
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

    # Load analysis (either from file or JSON string)
    try:
        if Path(args.analysis).exists():
            analysis = json.loads(Path(args.analysis).read_text())
        else:
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
