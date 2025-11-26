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
import os
from pathlib import Path
from datetime import datetime
from openai import OpenAI

LOG_FILE = Path.home() / ".config/sketchybar/logs/krisp-automation.log"
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)


def log(message, level="INFO"):
    """Log message to file and stderr"""
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"[{timestamp}] [{level}] {message}"
    print(log_line, file=sys.stderr)
    with open(LOG_FILE, "a") as f:
        f.write(log_line + "\n")


def detect_meeting_type_from_path(note_path):
    """
    Detect meeting type from note file path.

    Returns: 'append' for 1on1/executive (user takes notes),
             'replace' for team/KPI (transcript-only)
    """
    path_str = str(note_path).lower()

    # Team meetings: /Teams/{TeamName}/Meetings/
    # KPI meetings: /Teams/Bi/Meetings/ and filename contains "KPI"
    if '/teams/' in path_str:
        log(f"Detected team/KPI meeting from path (replace mode): {note_path}")
        return 'replace'

    # Ron executive meetings: /People/IPMedia/Ron/
    if '/people/ipmedia/ron/' in path_str:
        log(f"Detected executive meeting from path (append mode): {note_path}")
        return 'append'

    # 1-on-1 meetings: /People/{Company}/{Person}/Meetings/ and filename contains "1on1"
    if '1on1' in path_str or 'meeting.md' in path_str:
        log(f"Detected 1-on-1 meeting from path (append mode): {note_path}")
        return 'append'

    # Default to append for safety (preserve user notes)
    log(f"Unknown meeting type, defaulting to append mode: {note_path}")
    return 'append'


def extract_frontmatter(note_content):
    """
    Extract YAML frontmatter from note.

    Returns: (frontmatter_text, body_content)
             If no frontmatter, returns ('', note_content)
    """
    if not note_content.startswith('---\n'):
        log("No frontmatter found in note (doesn't start with ---)")
        return '', note_content

    # Find closing ---
    parts = note_content.split('---\n', 2)
    if len(parts) >= 3:
        frontmatter = f"---\n{parts[1]}---\n"
        body = parts[2]
        log(f"Extracted frontmatter ({len(frontmatter)} chars) and body ({len(body)} chars)")
        return frontmatter, body
    else:
        log("Frontmatter appears incomplete (no closing ---), treating as no frontmatter", "WARN")
        return '', note_content


def merge_with_gpt(old_content, analysis, transcript_text, template_content):
    """
    Use GPT to intelligently merge old note content with new transcript content.

    For team/KPI meetings where user doesn't take notes - GPT rewrites the entire
    note body based on the template, incorporating both old and new information.

    Args:
        old_content: Existing note body (without frontmatter)
        analysis: Dict with extracted info from transcript
        transcript_text: Raw transcript text
        template_content: Template to guide output structure

    Returns: Merged note body content
    """
    log("=== Starting GPT merge ===")
    log(f"Input sizes - Old content: {len(old_content)} chars, Transcript: {len(transcript_text)} chars, Template: {len(template_content)} chars")

    try:
        api_key = os.getenv('OPENAI_API_KEY')
        if not api_key:
            log("OPENAI_API_KEY not found in environment", "ERROR")
            return f"{old_content}\n\n---\n**⚠️ Auto-update failed: Missing API key** - Check logs\n"

        log(f"OpenAI API key found (length: {len(api_key)})")
        client = OpenAI(api_key=api_key)

        # Truncate transcript for prompt (keep first 2000 chars)
        transcript_preview = transcript_text[:2000]
        if len(transcript_text) > 2000:
            transcript_preview += f"... (truncated, full length: {len(transcript_text)} chars)"

        prompt = f"""You are updating a team meeting note with new transcript content.

OLD NOTE CONTENT:
{old_content}

NEW TRANSCRIPT ANALYSIS:
{json.dumps(analysis, indent=2)}

RAW TRANSCRIPT:
{transcript_preview}

TEMPLATE STRUCTURE TO FOLLOW:
{template_content}

INSTRUCTIONS:
1. Merge the old note content with the new transcript information
2. Follow the template structure exactly
3. DO NOT include frontmatter (YAML between --- markers)
4. Preserve any important context from the old note
5. Add new information from the transcript to appropriate sections
6. Output should be a complete, well-structured meeting note body

Output the complete merged note body:"""

        prompt_length = len(prompt)
        log(f"Prompt constructed: {prompt_length} chars (~{prompt_length // 4} tokens)")
        log(f"Calling OpenAI GPT-4o-mini (temp=0.7, max_tokens=2000)...")

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are an expert at synthesizing meeting notes from transcripts and existing content."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.7,
            max_tokens=2000
        )

        merged_content = response.choices[0].message.content.strip()

        # Log usage stats if available
        if hasattr(response, 'usage') and response.usage:
            log(f"✓ GPT merge completed - Output: {len(merged_content)} chars")
            log(f"  Token usage - Prompt: {response.usage.prompt_tokens}, Completion: {response.usage.completion_tokens}, Total: {response.usage.total_tokens}")
            log(f"  Cost estimate: ~${(response.usage.total_tokens / 1000) * 0.0015:.4f}")
        else:
            log(f"✓ GPT merge completed - Output: {len(merged_content)} chars (usage stats unavailable)")

        # Validate output
        if not merged_content:
            log("GPT returned empty content", "WARN")
            return f"{old_content}\n\n---\n**⚠️ Auto-update produced empty content** - See logs\n"

        if merged_content.startswith('---'):
            log("GPT included frontmatter despite instructions (will be prepended anyway)", "WARN")

        return merged_content

    except Exception as e:
        log(f"GPT merge failed with exception: {type(e).__name__}: {str(e)}", "ERROR")
        import traceback
        log(f"Traceback: {traceback.format_exc()}", "ERROR")
        # Fallback: return old content with error note
        return f"{old_content}\n\n---\n**⚠️ Auto-update failed: {type(e).__name__}** - See logs for details\n"


def reconcile_prep_action_items(note_content, analysis):
    """
    Reconcile PREP section action items based on meeting discussion (AC #6 - Second Pass).

    Finds unchecked items in "Open Items from Last Time" or "Context" section,
    checks if they were discussed/completed in the transcript analysis, and updates status.

    Args:
        note_content: Full note content after AI sections filled
        analysis: Dict with discussion_highlights, action_items, etc.

    Returns:
        Updated note content with reconciled checkboxes
    """
    log("=== Starting Action Item Reconciliation ===")

    # Find the Context/Open Items section
    # Pattern matches lines like: "- [ ] Item description - Status?"
    prep_section_pattern = r'(### Open Items from Last Time\n|### Open Strategic Items\n)(.*?)(?=\n### |\n## |\n---|\Z)'
    match = re.search(prep_section_pattern, note_content, re.DOTALL)

    if not match:
        log("No prep action items section found, skipping reconciliation")
        return note_content

    prep_section = match.group(2)
    log(f"Found prep section: {len(prep_section)} chars")

    # Extract unchecked items
    unchecked_pattern = r'- \[ \] (.+?)(?:\n|$)'
    unchecked_items = re.findall(unchecked_pattern, prep_section)

    if not unchecked_items:
        log("No unchecked items found in prep section")
        return note_content

    log(f"Found {len(unchecked_items)} unchecked prep items to reconcile")

    # Build context from analysis for comparison
    discussion_text = ""
    if analysis.get('discussion_highlights'):
        highlights = analysis['discussion_highlights']
        if isinstance(highlights, list):
            discussion_text += "\n".join(str(h) for h in highlights)
        else:
            discussion_text += str(highlights)

    if analysis.get('action_items'):
        items = analysis['action_items']
        if isinstance(items, dict):
            for owner, tasks in items.items():
                if isinstance(tasks, list):
                    discussion_text += "\n" + "\n".join(str(t) for t in tasks)
        elif isinstance(items, list):
            discussion_text += "\n" + "\n".join(str(i) for i in items)

    if not discussion_text:
        log("No discussion content to compare against, skipping reconciliation")
        return note_content

    # Use simple keyword matching (avoid extra API call)
    # This is a conservative approach - only marks items mentioned
    updated_content = note_content

    for item in unchecked_items:
        # Extract key words from item (3+ char words, ignore common words)
        item_words = set(
            word.lower() for word in re.findall(r'\b\w{3,}\b', item)
            if word.lower() not in {'status', 'update', 'check', 'review', 'from', 'with', 'the', 'and', 'for'}
        )

        # Check if any key words appear in discussion
        discussion_lower = discussion_text.lower()
        matches = [word for word in item_words if word in discussion_lower]

        if len(matches) >= 2 or (len(matches) == 1 and len(item_words) <= 2):
            # Item was likely discussed - add annotation
            old_line = f"- [ ] {item}"
            new_line = f"- [ ] {item} *(discussed in meeting)*"

            if old_line in updated_content:
                updated_content = updated_content.replace(old_line, new_line, 1)
                log(f"✓ Annotated item as discussed: {item[:50]}...")

    log("=== Action Item Reconciliation Complete ===")
    return updated_content


def update_meeting_note(note_path, analysis, transcript_rel_path, metadata, transcript_text=None, template_path=None):
    """
    Update meeting note with AI analysis by filling post-meeting sections (AC #5).

    Strategy depends on meeting type:
    - 1on1/Executive: APPEND to sections (user takes notes during meeting)
    - Team/KPI: REPLACE via GPT merge (intelligently combine old + new)

    Args:
        note_path: Path to meeting note file
        analysis: Dict with discussion_highlights, action_items, topics_next_time, related_context
        transcript_rel_path: Relative path to transcript for wikilink
        metadata: Dict with meeting_duration, processed_at
        transcript_text: Raw transcript text (for GPT merge in replace mode)
        template_path: Path to template file (for GPT merge structure guidance)

    Returns: True on success, False on failure
    """
    log("=== Update Meeting Note Started ===")
    log(f"Note path: {note_path}")
    log(f"Transcript rel path: {transcript_rel_path}")
    log(f"Metadata: {metadata}")
    log(f"Has transcript text: {bool(transcript_text)} (length: {len(transcript_text) if transcript_text else 0})")
    log(f"Has template path: {bool(template_path)} (path: {template_path if template_path else 'None'})")

    try:
        # Read existing note
        if not Path(note_path).exists():
            log(f"Note file does not exist: {note_path}", "ERROR")
            return False

        note_content = Path(note_path).read_text()
        log(f"Read existing note: {len(note_content)} chars")

        # Detect meeting type from path
        update_mode = detect_meeting_type_from_path(note_path)
        log(f"Update mode determined: {update_mode}")

        if update_mode == 'replace' and transcript_text and template_path:
            # Replace mode: Use GPT to merge old content + new transcript
            log("✓ Conditions met for GPT merge strategy (replace mode + transcript + template)")
            log(f"  - Update mode: replace")
            log(f"  - Transcript provided: {len(transcript_text)} chars")
            log(f"  - Template path: {template_path}")

            # Extract frontmatter and body
            frontmatter, old_body = extract_frontmatter(note_content)

            # Load template content
            if not Path(template_path).exists():
                log(f"Template file not found: {template_path}", "WARN")
                template_content = ""
            else:
                template_content = Path(template_path).read_text()
                log(f"Loaded template: {len(template_content)} chars from {Path(template_path).name}")

            # Call GPT to merge
            new_body = merge_with_gpt(old_body, analysis, transcript_text, template_content)
            log(f"GPT merge returned: {len(new_body)} chars")

            # Reconstruct note: frontmatter + new body
            if frontmatter:
                updated_content = frontmatter + '\n' + new_body
                log(f"Reconstructed note: frontmatter ({len(frontmatter)} chars) + body ({len(new_body)} chars)")
            else:
                updated_content = new_body
                log(f"No frontmatter to preserve, using body only ({len(new_body)} chars)")

        else:
            # Append mode: Use existing section-by-section append logic
            log("Using append strategy for 1on1/executive meeting")
            if update_mode == 'replace':
                log("  Note: Replace mode requested but missing transcript_text or template_path", "WARN")
                log(f"    - Has transcript_text: {bool(transcript_text)}")
                log(f"    - Has template_path: {bool(template_path)}")

            # Build formatted post-meeting content
            formatted_content = build_post_meeting_content(analysis, transcript_rel_path, metadata, update_mode)
            log(f"Built formatted content: {len(formatted_content)} sections")

            # Find and replace post-meeting sections
            updated_content = fill_post_meeting_sections(note_content, formatted_content, update_mode)
            log(f"Filled sections: {len(updated_content)} chars")

        # Reconcile PREP section action items (second pass)
        # Only for append mode where user has PREP sections with action items
        if update_mode == 'append':
            updated_content = reconcile_prep_action_items(updated_content, analysis)

        # Write atomically (temp file + rename)
        temp_path = Path(note_path).with_suffix('.tmp')
        log(f"Writing to temp file: {temp_path}")
        temp_path.write_text(updated_content)
        temp_path.replace(note_path)
        log(f"Renamed temp file to final: {note_path}")

        log(f"✓ Successfully updated note ({update_mode} mode): {note_path}")
        log(f"  Final size: {len(updated_content)} chars")
        return True

    except Exception as e:
        log(f"Failed to update note: {type(e).__name__}: {str(e)}", "ERROR")
        import traceback
        log(f"Traceback: {traceback.format_exc()}", "ERROR")
        return False


def build_post_meeting_content(analysis, transcript_rel_path, metadata, update_mode='append'):
    """
    Build formatted markdown content for post-meeting sections.

    Args:
        update_mode: 'append' (add separator + preserve existing) or 'replace' (clean replacement)

    Returns: Dict mapping section names to formatted content
    """
    content = {}
    processed = metadata.get('processed_at', datetime.now().strftime('%Y-%m-%d %H:%M'))

    # Add timestamp separator only for append mode
    if update_mode == 'append':
        separator = f"\n\n---\n**🤖 AI-Generated from Transcript** (Added: {processed})\n"
    else:
        # Replace mode: Clean content without separator (transcript is the source)
        separator = "\n"

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


def fill_post_meeting_sections(note_content, formatted_content, update_mode='append'):
    """
    Update AI-generated content in post-meeting sections.

    Strategy depends on update_mode:
    - 'append': Find section headers and append after existing content (for 1on1/executive)
    - 'replace': Replace section content entirely (for team/KPI meetings)

    Expected sections (works with both template types):
    - ### 🎯 Discussion Highlights (or similar variants)
    - ### ✅ Action Items Captured (or "Action Items")
    - ### 💡 Topics to Review Next Time (or similar)
    - ### 🔗 Related Context

    Returns: Updated note content
    """
    updated = note_content

    # Define section patterns
    # Pattern: Match header + content up to next header (## or ###) or end of file
    # Uses lazy quantifier .*? with explicit boundary conditions
    sections = [
        {
            'pattern': r'(### Notes During Meeting\n)(.*?)(?=\n### |\n## |\Z)',
            'replacement': formatted_content.get('notes_during_meeting', ''),
            'key': 'notes_during_meeting'
        },
        {
            'pattern': r'(### Action Items\n)(.*?)(?=\n### |\n## |\Z)',
            'replacement': formatted_content.get('action_items', ''),
            'key': 'action_items'
        },
        {
            'pattern': r'(### Key Insights & Quotes\n)(.*?)(?=\n### |\n## |\Z)',
            'replacement': formatted_content.get('key_insights', ''),
            'key': 'key_insights'
        },
        {
            'pattern': r'(### Decisions Made\n)(.*?)(?=\n### |\n## |\Z)',
            'replacement': formatted_content.get('decisions', ''),
            'key': 'decisions'
        },
        {
            'pattern': r'(### Blockers Identified\n)(.*?)(?=\n### |\n## |\Z)',
            'replacement': formatted_content.get('blockers', ''),
            'key': 'blockers'
        },
        {
            'pattern': r'(### Growth & Development\n)(.*?)(?=\n### |\n## |\Z)',
            'replacement': formatted_content.get('growth_development', ''),
            'key': 'growth_development'
        },
        {
            'pattern': r'(### Business Impact\n)(.*?)(?=\n### |\n## |\Z)',
            'replacement': formatted_content.get('business_impact', ''),
            'key': 'business_impact'
        },
        {
            'pattern': r'(### Related Documents\n)(.*?)(?=\n### |\n## |\n---|\Z)',
            'replacement': formatted_content.get('related_context', ''),
            'key': 'related_context'
        },
    ]

    # Update each section based on mode
    for section in sections:
        if section['replacement']:
            key = section['key']  # Capture for closure

            if update_mode == 'append':
                # Append strategy: preserve existing content + add AI content
                # Idempotency: Skip if AI content already exists in section

                def make_append_func(replacement, section_key):
                    def append_if_no_ai_content(m):
                        existing_content = m.group(2)
                        if '🤖 AI-Generated from Transcript' in existing_content:
                            log(f"Skipping {section_key} - AI content already exists (idempotency)", "INFO")
                            return m.group(1) + existing_content
                        else:
                            return m.group(1) + existing_content.rstrip() + replacement + '\n'
                    return append_if_no_ai_content

                updated = re.sub(
                    section['pattern'],
                    make_append_func(section['replacement'], key),
                    updated,
                    flags=re.DOTALL
                )
            else:
                # Replace strategy: replace section content entirely
                def make_replace_func(replacement):
                    def replace_content(m):
                        return m.group(1) + replacement.lstrip() + '\n'
                    return replace_content

                updated = re.sub(
                    section['pattern'],
                    make_replace_func(section['replacement']),
                    updated,
                    flags=re.DOTALL
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
    parser.add_argument(
        '--transcript-text',
        help='Raw transcript text (for GPT merge in replace mode)'
    )
    parser.add_argument(
        '--template-path',
        help='Path to template file (for GPT structure guidance)'
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
        metadata,
        transcript_text=args.transcript_text,
        template_path=args.template_path
    )

    if success:
        print(f"✓ Note updated: {args.note}")
        sys.exit(0)
    else:
        print("✗ Failed to update note", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
