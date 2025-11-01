#!/bin/bash
# Story 3.2 E2E Test Suite
# Tests all three acceptance criteria with comprehensive scenarios

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
PASSED=0
FAILED=0
WARNINGS=0

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo "================================================================"
echo "  Story 3.2: E2E Test Suite"
echo "  Testing: Todoist Focus Tasks, Popup Performance, Calendar Logic"
echo "================================================================"
echo ""

# ============================================================================
# AC #1: Todoist Focus Task Updates Main Widget
# ============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AC #1: Todoist Focus Task Updates"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_test "Verifying todoist.sh has event subscription"
if grep -q "todoist_focus_changed" ~/.config/sketchybar/plugins/todoist.sh; then
    log_pass "Event subscription found in todoist.sh"
else
    log_fail "Event subscription NOT found in todoist.sh"
fi

log_test "Verifying todoist_popup.sh click handler triggers event"
if grep -q "todoist_focus_changed" ~/.config/sketchybar/plugins/todoist_popup.sh; then
    log_pass "Event trigger found in todoist_popup.sh"
else
    log_fail "Event trigger NOT found in todoist_popup.sh"
fi

log_test "Verifying [WORKING] text indicator removed"
if grep -q '\[WORKING\]' ~/.config/sketchybar/plugins/todoist_popup.sh; then
    log_fail "[WORKING] text still present in todoist_popup.sh"
else
    log_pass "[WORKING] text successfully removed"
fi

log_test "Checking focus task cache file"
FOCUS_CACHE=~/.cache/sketchybar/todoist_working_task
if [[ -f "$FOCUS_CACHE" ]]; then
    TASK_ID=$(cat "$FOCUS_CACHE")
    log_pass "Focus task cache exists with task ID: $TASK_ID"
else
    log_warn "Focus task cache not yet created (expected on first use)"
fi

log_test "Verifying popup auto-close command"
if grep -q "popup.drawing=off" ~/.config/sketchybar/plugins/todoist_popup.sh; then
    log_pass "Auto-close popup command found"
else
    log_fail "Auto-close popup command NOT found"
fi

# ============================================================================
# AC #2: Todoist Popup Opens Instantly (<100ms)
# ============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AC #2: Todoist Popup Performance"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_test "Checking precache script exists and is executable"
PRECACHE_SCRIPT=~/.config/sketchybar/helpers/todoist-precache.sh
if [[ -x "$PRECACHE_SCRIPT" ]]; then
    log_pass "Precache script exists and is executable"
else
    log_fail "Precache script missing or not executable"
fi

log_test "Checking LaunchAgent is loaded"
if launchctl list | grep -q "todoist-precache"; then
    log_pass "LaunchAgent is loaded and running"
else
    log_fail "LaunchAgent NOT running"
fi

log_test "Verifying task cache file exists and is fresh"
CACHE_FILE=~/.cache/sketchybar/todoist_tasks_cache
if [[ -f "$CACHE_FILE" ]]; then
    CACHE_AGE=$(($(date +%s) - $(stat -f %m "$CACHE_FILE")))
    if [[ $CACHE_AGE -lt 300 ]]; then
        log_pass "Cache file exists and is fresh (${CACHE_AGE}s old)"
    else
        log_warn "Cache file exists but is stale (${CACHE_AGE}s old, expected <300s)"
    fi
else
    log_fail "Cache file does NOT exist"
fi

log_test "Validating cache format"
if grep -q "^SYNC_STATUS=" "$CACHE_FILE" && grep -q "^TASKS_START$" "$CACHE_FILE"; then
    SYNC_STATUS=$(grep "^SYNC_STATUS=" "$CACHE_FILE" | cut -d= -f2)
    if [[ "$SYNC_STATUS" == "success" ]]; then
        log_pass "Cache format valid with SYNC_STATUS=success"
    else
        log_warn "Cache format valid but SYNC_STATUS=$SYNC_STATUS"
    fi
else
    log_fail "Cache format invalid - missing required headers"
fi

log_test "Checking precache logs"
LOG_FILE=~/.config/sketchybar/logs/todoist-precache.log
if [[ -f "$LOG_FILE" ]]; then
    LAST_LOG=$(tail -1 "$LOG_FILE")
    if echo "$LAST_LOG" | grep -q "Successfully cached tasks"; then
        log_pass "Precache logs show successful sync"
    else
        log_warn "Last log entry: $LAST_LOG"
    fi
else
    log_fail "Precache log file NOT found"
fi

log_test "Verifying todoist_popup.sh reads from cache (not API)"
if grep -q "todoist_tasks_cache" ~/.config/sketchybar/plugins/todoist_popup.sh; then
    log_pass "todoist_popup.sh configured to read from cache"
else
    log_fail "todoist_popup.sh NOT reading from cache"
fi

log_test "Verifying LaunchAgent has EnvironmentVariables PATH"
PLIST=~/Library/LaunchAgents/com.user.todoist-precache.plist
if grep -q "EnvironmentVariables" "$PLIST" && grep -q "/opt/homebrew/bin" "$PLIST"; then
    log_pass "LaunchAgent has critical PATH configuration"
else
    log_fail "LaunchAgent missing EnvironmentVariables PATH (will fail silently)"
fi

# ============================================================================
# AC #3: Calendar Day Boundary Logic
# ============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AC #3: Calendar Day Boundary Logic"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_test "Checking check_meetings_today() function implementation"
if grep -q "khal list today today" ~/.config/sketchybar/plugins/meeting.sh; then
    log_pass "check_meetings_today() uses simplified khal list command"
else
    log_fail "check_meetings_today() NOT using simplified logic"
fi

log_test "Verifying day boundary check exists"
MEETING_SCRIPT=~/.config/sketchybar/plugins/meeting.sh
if grep -q "MEETING_DATE" "$MEETING_SCRIPT" && grep -q 'date +%Y-%m-%d' "$MEETING_SCRIPT"; then
    log_pass "Day boundary check logic found in meeting.sh"
else
    log_fail "Day boundary check logic NOT found"
fi

log_test "Checking for proper message array usage"
if grep -q "FREE_DAY_MESSAGES" "$MEETING_SCRIPT" && grep -q "END_OF_DAY_MESSAGES" "$MEETING_SCRIPT"; then
    log_pass "Message arrays (FREE_DAY_MESSAGES, END_OF_DAY_MESSAGES) present"
else
    log_fail "Message arrays NOT found"
fi

log_test "Verifying khal is installed and functional"
if command -v khal &> /dev/null; then
    if khal list today today &> /dev/null; then
        log_pass "khal is installed and functional"
    else
        log_warn "khal installed but no calendar data configured"
    fi
else
    log_fail "khal NOT installed"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "================================================================"
echo "  Test Summary"
echo "================================================================"
echo -e "${GREEN}Passed:${NC}   $PASSED"
echo -e "${RED}Failed:${NC}   $FAILED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All critical tests passed!${NC}"
    echo ""
    echo "Story 3.2 is ready for completion."
    echo "Next steps:"
    echo "  1. Create git commits by phase"
    echo "  2. Update CLAUDE.md with Todoist automation architecture"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    echo ""
    echo "Please review failed tests before marking story complete."
    exit 1
fi
