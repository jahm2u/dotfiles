#!/bin/bash

# Test script for calendar error handling and graceful degradation (AC#8)
# This script provides documented test procedures for error scenarios

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync-calendars.sh"
LOG_FILE="$SCRIPT_DIR/../logs/calendar-sync.log"
CACHE_DIR="$HOME/.cache/sketchybar"
STATUS_FILE="$CACHE_DIR/last_sync_status"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Calendar Error Handling Test Suite ==="
echo ""

# Test 1: Network Failure
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Network Error Handling"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "MANUAL TEST PROCEDURE:"
echo "1. Disconnect network: Turn off Wi-Fi or disconnect Ethernet"
echo "2. Run: bash $SYNC_SCRIPT"
echo "3. Expected results:"
echo "   - Script logs ERROR with curl exit code (6=DNS, 7=connection failed, 28=timeout)"
echo "   - Script continues (doesn't crash)"
echo "   - Script completes with exit code 1 or 2"
echo "   - Log file shows: 'Failed to download' with network error details"
echo "4. Reconnect network"
echo ""
echo -e "${YELLOW}Run this test manually, then press Enter to continue...${NC}"
read -r

# Test 2: Invalid Calendar URL
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Invalid URL Handling"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "MANUAL TEST PROCEDURE:"
echo "1. Edit .env file and add: CALENDAR_URL_TEST=https://invalid.nonexistent.url/calendar.ics"
echo "2. Run: bash $SYNC_SCRIPT"
echo "3. Expected results:"
echo "   - Script logs ERROR for the invalid URL"
echo "   - Other valid calendars continue processing"
echo "   - Script completes with exit code 1 (partial failure)"
echo "   - Log shows: 'Failed to download test: DNS resolution failed (curl exit 6)'"
echo "4. Remove test URL from .env"
echo ""
echo -e "${YELLOW}Run this test manually, then press Enter to continue...${NC}"
read -r

# Test 3: Malformed .ics Data
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Parse Error Handling"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "MANUAL TEST PROCEDURE:"
echo "1. Create invalid .ics file:"
echo "   echo 'INVALID CALENDAR DATA' > /tmp/test-invalid.ics"
echo "2. Start local HTTP server:"
echo "   cd /tmp && python3 -m http.server 8888 &"
echo "   SERVER_PID=\$!"
echo "3. Edit .env: CALENDAR_URL_TEST=http://localhost:8888/test-invalid.ics"
echo "4. Run: bash $SYNC_SCRIPT"
echo "5. Expected results:"
echo "   - Script logs ERROR: 'Invalid calendar file for test (missing VCALENDAR header)'"
echo "   - Log includes: 'File may be HTML error page or corrupted data'"
echo "   - Other calendars continue processing"
echo "6. Cleanup:"
echo "   kill \$SERVER_PID"
echo "   rm /tmp/test-invalid.ics"
echo "   Remove test URL from .env"
echo ""
echo -e "${YELLOW}Run this test manually, then press Enter to continue...${NC}"
read -r

# Test 4: khal Database Lock (Concurrent Access)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: khal Database Lock Handling"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "MANUAL TEST PROCEDURE:"
echo "1. Start khal interactive in one terminal:"
echo "   khal interactive"
echo "2. In another terminal, run sync:"
echo "   bash $SYNC_SCRIPT"
echo "3. Expected results:"
echo "   - Script logs ERROR or WARN about khal import failure"
echo "   - Script continues (doesn't hang)"
echo "   - Exit code reflects failure state"
echo "4. Close khal interactive and retry sync"
echo ""
echo -e "${YELLOW}Run this test manually, then press Enter to continue...${NC}"
read -r

# Test 5: Widget Fallback Display
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Widget Fallback Behavior"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "MANUAL TEST PROCEDURE:"
echo "1. Run successful sync first:"
echo "   bash $SYNC_SCRIPT"
echo "2. Verify meeting widget shows current state"
echo "3. Cause sync failure (disconnect network)"
echo "4. Run sync again:"
echo "   bash $SYNC_SCRIPT"
echo "5. Query widget state:"
echo "   sketchybar --query meeting"
echo "6. Expected results:"
echo "   - Widget displays with clock icon (󰁡)"
echo "   - Label shows cached meeting data with '(stale)' suffix"
echo "   - OR shows 'Sync Failed (HH:MM)' with last sync time"
echo "7. Reconnect network"
echo ""
echo -e "${YELLOW}Run this test manually, then press Enter to continue...${NC}"
read -r

# Test 6: Widget Recovery After Sync Success
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: Widget Recovery After Success"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "MANUAL TEST PROCEDURE:"
echo "1. Start in failed state (from Test 5)"
echo "2. Reconnect network"
echo "3. Run successful sync:"
echo "   bash $SYNC_SCRIPT"
echo "4. Query widget state:"
echo "   sketchybar --query meeting"
echo "5. Expected results:"
echo "   - Widget updates immediately (calendar_synced event triggered)"
echo "   - Clock icon (󰁡) replaced with normal icon (󰃭 or 󰁅)"
echo "   - '(stale)' suffix removed from label"
echo "   - Fresh meeting data displayed"
echo ""
echo -e "${YELLOW}Run this test manually, then press Enter to continue...${NC}"
read -r

# Test 7: Sketchybar Stability Through Errors
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 7: Sketchybar Stability Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "MANUAL TEST PROCEDURE:"
echo "1. Run all error scenarios above in sequence"
echo "2. After each test, verify:"
echo "   - Sketchybar process still running: pgrep sketchybar"
echo "   - Meeting widget still visible in menu bar"
echo "   - Widget responds to clicks"
echo "   - No crash logs in Console.app"
echo "3. Expected results:"
echo "   - Sketchybar remains stable through all error scenarios"
echo "   - No process crashes or hangs"
echo "   - Widget continues updating on schedule"
echo ""
echo -e "${YELLOW}Run this test manually, then press Enter to continue...${NC}"
read -r

# Display sync status and log summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Current System State"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ -f "$STATUS_FILE" ]]; then
    echo "Last Sync Status:"
    cat "$STATUS_FILE"
    echo ""
else
    echo "No sync status file found at: $STATUS_FILE"
    echo ""
fi

if [[ -f "$LOG_FILE" ]]; then
    echo "Recent Log Entries (last 10 lines):"
    tail -10 "$LOG_FILE"
    echo ""
else
    echo "No log file found at: $LOG_FILE"
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Suite Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "NEXT STEPS:"
echo "1. Review log file for error patterns: $LOG_FILE"
echo "2. Check cache files in: $CACHE_DIR"
echo "3. Verify widget display in Sketchybar menu bar"
echo "4. Run production sync: bash $SYNC_SCRIPT"
echo ""
echo "NOTE: All tests are manual as they require network manipulation"
echo "      and real-time observation of system behavior."
