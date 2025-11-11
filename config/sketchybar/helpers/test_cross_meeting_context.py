#!/Users/v/.config/sketchybar/venv/bin/python3
"""
Test cross-meeting context scanner
"""
import os
import sys
import glob
from pathlib import Path
from datetime import datetime, timedelta


def get_cross_meeting_context(vault_path: str, scope: str, lookback_days: int = 7) -> str:
    """
    Scan all meetings matching scope from the last N days for cross-meeting context.
    """
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


def test_cross_meeting_context():
    """Test that we can scan recent meetings from IPMedia"""
    vault_path = "/Users/v/Library/Mobile Documents/iCloud~md~obsidian/Documents/U"

    print("Testing cross-meeting context scanner...")
    print(f"Vault path: {vault_path}")
    print()

    # Test with 7-day lookback for IPMedia
    context = get_cross_meeting_context(vault_path, "IPMedia", lookback_days=7)

    if not context:
        print("❌ No meetings found in last 7 days")
        return False

    print(f"✓ Found context ({len(context)} chars)")
    print()

    # Show first few lines
    lines = context.split('\n')
    print("Preview (first 20 lines):")
    print("=" * 80)
    for line in lines[:20]:
        print(line)
    print("=" * 80)
    print()

    # Count meetings
    meeting_count = context.count("--- 202")  # Count date headers
    print(f"✓ Found {meeting_count} meetings")

    # Test with longer lookback
    context_30 = get_cross_meeting_context(vault_path, "IPMedia", lookback_days=30)
    meeting_count_30 = context_30.count("--- 202")
    print(f"✓ With 30-day lookback: {meeting_count_30} meetings")

    # Test with non-existent scope
    context_bad = get_cross_meeting_context(vault_path, "NonExistent", lookback_days=7)
    if context_bad == "":
        print("✓ Gracefully handles non-existent scope")

    print()
    print("✅ Cross-meeting context scanner working!")
    return True


if __name__ == "__main__":
    try:
        success = test_cross_meeting_context()
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"❌ Test failed: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
