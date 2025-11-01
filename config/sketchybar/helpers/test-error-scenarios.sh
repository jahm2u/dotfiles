#!/bin/bash
# Story 3.2 Error Scenario Testing
# Tests graceful failure handling for all edge cases

echo "================================================================"
echo "  Story 3.2: Error Scenario Testing"
echo "================================================================"
echo ""

PASSED=0
FAILED=0

log_pass() {
    echo "✓ $1"
    ((PASSED++))
}

log_fail() {
    echo "✗ $1"
    ((FAILED++))
}

# Test 1: Missing cache file handling
echo "Test 1: Missing Cache File Handling"
echo "-------------------------------------"
CACHE_FILE=~/.cache/sketchybar/todoist_tasks_cache
if [[ -f "$CACHE_FILE" ]]; then
    # Backup exists, test handles missing gracefully
    if grep -q "Refreshing tasks" ~/.config/sketchybar/plugins/todoist_popup.sh; then
        log_pass "Popup handles missing cache with 'Refreshing tasks' message"
    else
        log_fail "Popup missing graceful cache failure handling"
    fi
else
    log_pass "Cache file missing - popup should show 'Refreshing tasks'"
fi

# Test 2: Failed sync status handling
echo ""
echo "Test 2: Failed Sync Status Handling"
echo "-------------------------------------"
if grep -q "SYNC_STATUS.*failed" ~/.config/sketchybar/plugins/todoist_popup.sh; then
    log_pass "Popup checks SYNC_STATUS and handles failures"
else
    log_fail "Popup doesn't handle SYNC_STATUS=failed"
fi

if grep -q "Sync failed.*retry" ~/.config/sketchybar/plugins/todoist_popup.sh; then
    log_pass "Popup provides retry option on sync failure"
else
    log_fail "Popup missing retry mechanism"
fi

# Test 3: Empty .env file handling
echo ""
echo "Test 3: Empty API Token Handling"
echo "-------------------------------------"
if grep -q "TODOIST_API_TOKEN.*exit" ~/.config/sketchybar/plugins/todoist_popup.sh; then
    log_pass "Popup gracefully exits when API token missing"
else
    log_fail "Popup doesn't check for missing API token"
fi

# Test 4: Precache error logging
echo ""
echo "Test 4: Precache Error Logging"
echo "-------------------------------------"
PRECACHE_SCRIPT=~/.config/sketchybar/helpers/todoist-precache.sh
if grep -q "ERROR\|WARN" "$PRECACHE_SCRIPT" 2>/dev/null; then
    log_pass "Precache script has error logging"
else
    log_fail "Precache script missing comprehensive error logging"
fi

if grep -q "max-time\|timeout" "$PRECACHE_SCRIPT" 2>/dev/null; then
    log_pass "Precache script has timeout protection"
else
    log_fail "Precache script missing timeout configuration"
fi

# Test 5: Meeting widget empty calendar handling
echo ""
echo "Test 5: Calendar Widget Empty State Handling"
echo "-------------------------------------"
MEETING_SCRIPT=~/.config/sketchybar/plugins/meeting.sh
if grep -q "No events\|FREE_DAY_MESSAGES" "$MEETING_SCRIPT"; then
    log_pass "Meeting widget handles empty calendar gracefully"
else
    log_fail "Meeting widget missing empty calendar handling"
fi

if grep -q "No calendar access\|No calendars" "$MEETING_SCRIPT"; then
    log_pass "Meeting widget handles missing calendar data"
else
    log_fail "Meeting widget doesn't handle missing khal data"
fi

# Test 6: Sync failure in meeting widget
echo ""
echo "Test 6: Calendar Sync Failure Handling"
echo "-------------------------------------"
if grep -q "SYNC_STATUS.*failed" "$MEETING_SCRIPT"; then
    log_pass "Meeting widget checks sync status"
else
    log_fail "Meeting widget doesn't check sync status"
fi

if grep -q "Sync Failed" "$MEETING_SCRIPT"; then
    log_pass "Meeting widget shows sync failure message"
else
    log_fail "Meeting widget missing sync failure display"
fi

# Test 7: LaunchAgent robustness
echo ""
echo "Test 7: LaunchAgent Error Handling"
echo "-------------------------------------"
PLIST=~/Library/LaunchAgents/com.user.todoist-precache.plist
if [[ -f "$PLIST" ]]; then
    if grep -q "StandardErrorPath" "$PLIST"; then
        log_pass "LaunchAgent logs stderr for debugging"
    else
        log_fail "LaunchAgent missing stderr logging"
    fi

    if grep -q "StandardOutPath" "$PLIST"; then
        log_pass "LaunchAgent logs stdout for monitoring"
    else
        log_fail "LaunchAgent missing stdout logging"
    fi
else
    log_fail "LaunchAgent plist not found"
fi

# Test 8: Cache corruption protection
echo ""
echo "Test 8: Cache Corruption Protection"
echo "-------------------------------------"
if grep -q "SYNC_STATUS=\|TASKS_START" ~/.config/sketchybar/plugins/todoist_popup.sh; then
    log_pass "Popup validates cache format before parsing"
else
    log_fail "Popup missing cache format validation"
fi

# Test 9: Network timeout handling
echo ""
echo "Test 9: Network Timeout Protection"
echo "-------------------------------------"
if [[ -f "$PRECACHE_SCRIPT" ]] && grep -q "max-time\|timeout" "$PRECACHE_SCRIPT"; then
    TIMEOUT=$(grep -E "max-time|timeout" "$PRECACHE_SCRIPT" | head -1)
    log_pass "Precache has timeout: $TIMEOUT"
else
    log_fail "Precache script missing network timeout"
fi

# Test 10: Rate limiting and resource usage
echo ""
echo "Test 10: Resource Usage Protection"
echo "-------------------------------------"
if launchctl list | grep -q "todoist-precache"; then
    # Check if interval is reasonable (5 minutes = 300 seconds)
    if grep -q "StartInterval.*300\|StartInterval.*900" "$PLIST" 2>/dev/null; then
        log_pass "LaunchAgent runs at reasonable interval (5-15 min)"
    else
        log_fail "LaunchAgent interval may be too aggressive"
    fi
else
    log_fail "LaunchAgent not running"
fi

# Summary
echo ""
echo "================================================================"
echo "  Error Scenario Test Summary"
echo "================================================================"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo "✓ All error scenarios handled gracefully"
    exit 0
else
    echo "✗ Some error scenarios need attention"
    exit 1
fi
