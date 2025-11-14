#!/usr/bin/env bash
# test-batch-clean.sh - Clean batch test with reporting
# Created: 2025-11-11 (Completing Nich's work)

set -euo pipefail

HELPERS_DIR="$HOME/.config/sketchybar/helpers"
CACHE_FILE="$HOME/.cache/sketchybar/krisp-updated-meeting-notes.json"
VENV_PYTHON="$HOME/.config/sketchybar/venv/bin/python3"

echo "=== KRISP BATCH PROCESSING TEST ==="
echo

# Clear cache
echo "[1/3] Clearing cache..."
$VENV_PYTHON <<'EOF'
import json
from pathlib import Path

cache_file = Path.home() / ".cache/sketchybar/krisp-updated-meeting-notes.json"
with open(cache_file, 'r') as f:
    cache = json.load(f)

print(f"  Before: {len(cache['processed_meetings'])} processed, {len(cache['failed_matches'])} failed")

cache['processed_meetings'] = []
cache['failed_matches'] = []

with open(cache_file, 'w') as f:
    json.dump(cache, f, indent=2)

print(f"  After: Cache cleared")
EOF

# Run batch
echo
echo "[2/3] Running batch process..."
cd "$HELPERS_DIR"
$VENV_PYTHON krisp-batch-process.py > /tmp/batch-test-output.json 2> /tmp/batch-test-stderr.log

# Analyze results
echo
echo "[3/3] Analyzing results..."
$VENV_PYTHON <<'EOF'
import json

with open('/tmp/batch-test-output.json') as f:
    results = json.load(f)

success = results['success']
failed = results['failed']
skipped = results['skipped']
total = success + failed + skipped

print(f"\n=== RESULTS ===")
print(f"Total: {total}")
print(f"Success: {success} ({success/total*100:.1f}%)")
print(f"Skipped: {skipped} ({skipped/total*100:.1f}%)")
print(f"Failed: {failed} ({failed/total*100:.1f}%)")

print(f"\n=== COMPARISON ===")
print(f"Previous run: 24 success (63%)")
print(f"This run:     {success} success ({success/(success+failed)*100 if (success+failed) > 0 else 100:.1f}%)")
print(f"Improvement:  {success-24} meetings fixed")

# Breakdown
if skipped > 0:
    print(f"\n=== SKIPPED MEETINGS (Solo Recordings) ===")
    for detail in results['details']:
        if detail['status'] == 'skipped':
            print(f"  - {detail['date']}: {detail['title'][:50]}")

if failed > 0:
    print(f"\n=== FAILED MEETINGS ===")
    for detail in results['details']:
        if detail['status'] == 'failed':
            print(f"  - {detail['date']}: {detail['title'][:50]}")
            print(f"    Reason: {detail.get('reason', 'unknown')}")
else:
    print(f"\n✅ NO FAILURES - ALL BUGS FIXED!")

print(f"\n=== SUCCESS BREAKDOWN ===")
success_meetings = [d for d in results['details'] if d['status'] == 'success']
for detail in success_meetings[:5]:
    print(f"  - {detail['date']}: {detail['title'][:50]}")
if len(success_meetings) > 5:
    print(f"  ... and {len(success_meetings)-5} more")
EOF

echo
echo "=== TEST COMPLETE ==="
echo "Full output: /tmp/batch-test-output.json"
echo "Error log: /tmp/batch-test-stderr.log"
echo
echo "Next steps:"
echo "  1. Review results above"
echo "  2. Test meeting-prep: bash ~/.config/sketchybar/helpers/meeting-prep.sh"
echo "  3. Migrate old meetings to Business/IPMedia/Teams/"
