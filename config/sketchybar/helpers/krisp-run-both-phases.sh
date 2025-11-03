#!/usr/bin/env bash
#
# Krisp Two-Phase Automation
# Runs both discovery and processing phases in sequence.
#
# Usage:
#   bash krisp-run-both-phases.sh [OPTIONS]
#
# Options:
#   --max-pages N       Max pages to discover (default: 60)
#   --limit N           Max meetings to download (default: all pending)
#   --target-date DATE  Stop discovery at this date (YYYY-MM-DD)
#   --reset-progress    Clear download progress and start fresh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PYTHON="$HOME/.config/sketchybar/venv/bin/python3"

# Default values
MAX_PAGES=60
LIMIT=""
TARGET_DATE=""
RESET_PROGRESS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --max-pages)
            MAX_PAGES="$2"
            shift 2
            ;;
        --limit)
            LIMIT="--limit $2"
            shift 2
            ;;
        --target-date)
            TARGET_DATE="--target-date $2"
            shift 2
            ;;
        --reset-progress)
            RESET_PROGRESS="--reset-progress"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "=== Krisp Two-Phase Automation ==="
echo ""

# Phase 1: Discovery
echo "Phase 1: Discovering meetings..."
$VENV_PYTHON "$SCRIPT_DIR/krisp-discover-meetings.py" \
    --max-pages "$MAX_PAGES" \
    $TARGET_DATE

if [ $? -ne 0 ]; then
    echo "❌ Phase 1 failed - discovery error"
    exit 1
fi

echo ""
echo "✓ Phase 1 complete"
echo ""

# Phase 2: Processing
echo "Phase 2: Downloading transcripts..."
$VENV_PYTHON "$SCRIPT_DIR/krisp-process-queue.py" \
    $LIMIT \
    $RESET_PROGRESS

if [ $? -ne 0 ]; then
    echo "❌ Phase 2 failed - processing error"
    exit 1
fi

echo ""
echo "✓ Phase 2 complete"
echo ""
echo "=== All phases complete ==="
