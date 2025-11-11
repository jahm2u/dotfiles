#!/Users/v/.config/sketchybar/venv/bin/python3
"""
End-to-end test for Ron's meeting workflow with cross-context
Tests both meeting prep creation and transcript processing
"""
import os
import sys
import json
import shutil
from pathlib import Path
from datetime import datetime

# Test configuration
VAULT_PATH = "/Users/v/Library/Mobile Documents/iCloud~md~obsidian/Documents/U"
RON_FOLDER = f"{VAULT_PATH}/Business/People/IPMedia/Ron"
TEST_DATE = "2025-11-13"  # Future date to avoid conflicts
TEST_NOTE_PATH = f"{RON_FOLDER}/Meetings/{TEST_DATE} 1on1 with Ron.md"

def cleanup():
    """Remove test file if it exists"""
    if os.path.exists(TEST_NOTE_PATH):
        os.remove(TEST_NOTE_PATH)
        print(f"✓ Cleaned up test file: {TEST_NOTE_PATH}")

def test_meeting_prep_creation():
    """Test 1: Create meeting note with cross-meeting context"""
    print("\n" + "="*80)
    print("TEST 1: Meeting Prep Creation with Cross-Context")
    print("="*80)

    # Prepare classification
    classification = {
        "meeting_title": "Jeff / Ron Weekly Meeting",
        "meeting_type": "one-on-one",
        "company": "IPMedia",
        "participant": "Ron",
        "person_folder": RON_FOLDER
    }

    # Prepare continuity (empty for first meeting simulation)
    continuity = {
        "open_action_items": [],
        "recurring_topics": [],
        "active_blockers": [],
        "unresolved_threads": [],
        "suggested_agenda": {
            "must_discuss": ["Q4 financial review"],
            "should_discuss": ["Team expansion plans"],
            "could_discuss": ["Office space"]
        },
        "meeting_patterns": {
            "frequency_days": 7,
            "last_meeting_date": "2025-11-06"
        }
    }

    # Call generate-meeting-note.py
    import subprocess
    cmd = [
        str(Path.home() / ".config/sketchybar/venv/bin/python3"),
        str(Path(__file__).parent / "generate-meeting-note.py"),
        "--classification", json.dumps(classification),
        "--person-folder", RON_FOLDER,
        "--continuity", json.dumps(continuity),
        "--date", TEST_DATE
    ]

    print(f"\nExecuting: generate-meeting-note.py")
    print(f"  Classification: {classification['participant']} - {classification['company']}")
    print(f"  Person folder: {RON_FOLDER}")
    print(f"  Expected: Cross-context from last 7 days of IPMedia meetings")

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)

    if result.returncode != 0:
        print(f"\n❌ FAILED: generate-meeting-note.py returned {result.returncode}")
        print(f"STDOUT:\n{result.stdout}")
        print(f"STDERR:\n{result.stderr}")
        return False

    # Parse result
    try:
        output = json.loads(result.stdout)
        if not output.get('success'):
            print(f"❌ FAILED: {output.get('message', 'Unknown error')}")
            return False

        print(f"\n✅ SUCCESS: Meeting note created")
        print(f"   File: {output['file_path']}")
        print(f"   Full path: {output['full_path']}")

        # Verify file exists and read it
        if os.path.exists(TEST_NOTE_PATH):
            with open(TEST_NOTE_PATH, 'r') as f:
                content = f.read()

            # Check for key elements
            checks = [
                ("YAML frontmatter", "meeting_type: \"EXEC\"" in content or "meeting_type: EXEC" in content),
                ("Cross-context section", "Company-Wide Context" in content),
                ("Participant name", "Ron" in content),
                ("Date", TEST_DATE in content),
            ]

            print("\n   Content checks:")
            all_passed = True
            for check_name, passed in checks:
                status = "✓" if passed else "✗"
                print(f"   {status} {check_name}")
                if not passed:
                    all_passed = False

            # Show snippet of cross-context section
            if "Company-Wide Context" in content:
                lines = content.split('\n')
                context_idx = next(i for i, line in enumerate(lines) if "Company-Wide Context" in line)
                snippet = '\n'.join(lines[context_idx:context_idx+10])
                print(f"\n   Cross-context snippet:\n{snippet[:300]}...")

            return all_passed
        else:
            print(f"❌ FAILED: Note file was not created at {TEST_NOTE_PATH}")
            return False

    except Exception as e:
        print(f"❌ FAILED: Error parsing output: {e}")
        print(f"STDOUT: {result.stdout}")
        return False


def test_transcript_update():
    """Test 2: Update meeting note with fake transcript"""
    print("\n" + "="*80)
    print("TEST 2: Transcript Processing & Note Update")
    print("="*80)

    # Check if note exists from previous test
    if not os.path.exists(TEST_NOTE_PATH):
        print("❌ SKIPPED: Test note doesn't exist (run Test 1 first)")
        return False

    # Create fake analysis (what would come from AI)
    analysis = {
        "discussion_highlights": [
            "Discussed Q4 financial performance - revenue up 15%",
            "Team expansion approved for engineering team (3 new hires)",
            "Office lease renewal decision postponed to December"
        ],
        "action_items": {
            "Ron": [
                "Review budget allocation for new hires by Nov 20",
                "Schedule board meeting for Q4 review"
            ],
            "Jeff": [
                "Prepare engineering team structure proposal",
                "Coordinate with HR on hiring timeline"
            ]
        },
        "topics_next_time": [
            "Finalize office space decision",
            "Review December board agenda"
        ],
        "related_context": [
            "[[2025-11-06 1on1 with Ron|Previous meeting notes]]"
        ]
    }

    # Call krisp-update-note.py
    import subprocess
    cmd = [
        str(Path.home() / ".config/sketchybar/venv/bin/python3"),
        str(Path(__file__).parent / "krisp-update-note.py"),
        "--note", TEST_NOTE_PATH,
        "--analysis", "-",
        "--transcript-path", "Ron/attachments/2025-11-13-transcript.txt",
        "--duration", "42 minutes"
    ]

    print(f"\nExecuting: krisp-update-note.py")
    print(f"  Note: {TEST_NOTE_PATH}")
    print(f"  Analysis items: {len(analysis['discussion_highlights'])} highlights, "
          f"{sum(len(v) for v in analysis['action_items'].values())} actions")

    result = subprocess.run(
        cmd,
        input=json.dumps(analysis),
        capture_output=True,
        text=True,
        timeout=30
    )

    if result.returncode != 0:
        print(f"\n❌ FAILED: krisp-update-note.py returned {result.returncode}")
        print(f"STDOUT:\n{result.stdout}")
        print(f"STDERR:\n{result.stderr}")
        return False

    print(f"\n✅ SUCCESS: Note updated with transcript analysis")

    # Verify updates
    with open(TEST_NOTE_PATH, 'r') as f:
        updated_content = f.read()

    # Check for appended content
    checks = [
        ("AI-generated marker", "🤖 AI-Generated from Transcript" in updated_content),
        ("Discussion highlights", "revenue up 15%" in updated_content),
        ("Action items", "Review budget allocation" in updated_content),
        ("Transcript reference", "Original Transcript:" in updated_content),
        ("Duration", "42 minutes" in updated_content),
    ]

    print("\n   Update checks:")
    all_passed = True
    for check_name, passed in checks:
        status = "✓" if passed else "✗"
        print(f"   {status} {check_name}")
        if not passed:
            all_passed = False

    return all_passed


def main():
    """Run all tests"""
    print("\n" + "="*80)
    print("RON'S MEETING WORKFLOW - END-TO-END TEST")
    print("="*80)
    print(f"Test date: {TEST_DATE}")
    print(f"Test note: {TEST_NOTE_PATH}")

    # Cleanup any previous test
    cleanup()

    results = {}

    # Test 1: Meeting prep with cross-context
    try:
        results['prep'] = test_meeting_prep_creation()
    except Exception as e:
        print(f"\n❌ Test 1 crashed: {e}")
        import traceback
        traceback.print_exc()
        results['prep'] = False

    # Test 2: Transcript update
    try:
        results['transcript'] = test_transcript_update()
    except Exception as e:
        print(f"\n❌ Test 2 crashed: {e}")
        import traceback
        traceback.print_exc()
        results['transcript'] = False

    # Summary
    print("\n" + "="*80)
    print("TEST SUMMARY")
    print("="*80)
    print(f"  Meeting Prep Creation:  {'✅ PASS' if results.get('prep') else '❌ FAIL'}")
    print(f"  Transcript Processing:  {'✅ PASS' if results.get('transcript') else '❌ FAIL'}")
    print()

    if all(results.values()):
        print("✅ ALL TESTS PASSED")
        print(f"\nTest file created at: {TEST_NOTE_PATH}")
        print("You can inspect it manually, then run cleanup() to remove it")
        return 0
    else:
        print("❌ SOME TESTS FAILED")
        return 1


if __name__ == "__main__":
    sys.exit(main())
