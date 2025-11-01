#!/bin/bash
# Comprehensive Test Suite for Todoist Completion Toggle Feature
# Tests: API toggle, session state, visual rendering, error handling

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR="$HOME/.config/sketchybar"
CACHE_DIR="$HOME/.cache/sketchybar"
TOGGLE_SCRIPT="$CONFIG_DIR/helpers/todoist-toggle-complete.sh"
POPUP_SCRIPT="$CONFIG_DIR/plugins/todoist_popup.sh"
SESSION_FILE="$CACHE_DIR/todoist_completed_tasks_session"

# Test utilities
print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

pass() {
    ((TESTS_PASSED++))
    ((TESTS_RUN++))
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
    echo -e "${RED}✗${NC} $1"
    if [[ -n "${2:-}" ]]; then
        echo -e "  ${YELLOW}Details:${NC} $2"
    fi
}

# Cleanup function
cleanup_test_files() {
    rm -f "$SESSION_FILE.test" 2>/dev/null || true
    rm -f "$SESSION_FILE.backup" 2>/dev/null || true
}

# Test 1: File Existence and Permissions
test_file_existence() {
    print_header "TEST 1: File Existence and Permissions"

    if [[ -f "$TOGGLE_SCRIPT" ]]; then
        pass "todoist-toggle-complete.sh exists"
    else
        fail "todoist-toggle-complete.sh not found" "Expected: $TOGGLE_SCRIPT"
        return
    fi

    if [[ -x "$TOGGLE_SCRIPT" ]]; then
        pass "todoist-toggle-complete.sh is executable"
    else
        fail "todoist-toggle-complete.sh is not executable" "Run: chmod +x $TOGGLE_SCRIPT"
    fi

    if [[ -f "$POPUP_SCRIPT" ]]; then
        pass "todoist_popup.sh exists"
    else
        fail "todoist_popup.sh not found" "Expected: $POPUP_SCRIPT"
        return
    fi

    if [[ -x "$POPUP_SCRIPT" ]]; then
        pass "todoist_popup.sh is executable"
    else
        fail "todoist_popup.sh is not executable" "Run: chmod +x $POPUP_SCRIPT"
    fi
}

# Test 2: Environment Configuration
test_env_configuration() {
    print_header "TEST 2: Environment Configuration"

    ENV_FILE=""
    for possible_location in \
        "$HOME/dotfiles/.env" \
        "$HOME/repos/02_personal/dotfiles/.env" \
        "$HOME/.config/sketchybar/../../.env"
    do
        if [[ -f "$possible_location" ]]; then
            ENV_FILE="$possible_location"
            break
        fi
    done

    if [[ -n "$ENV_FILE" ]]; then
        pass ".env file found at: $ENV_FILE"
    else
        fail ".env file not found" "Checked: ~/dotfiles/.env, ~/repos/02_personal/dotfiles/.env"
        return
    fi

    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    fi

    if [[ -n "${TODOIST_API_TOKEN:-}" ]]; then
        TOKEN_LENGTH=${#TODOIST_API_TOKEN}
        pass "TODOIST_API_TOKEN is set (length: $TOKEN_LENGTH)"
    else
        fail "TODOIST_API_TOKEN not set in .env" "Add: TODOIST_API_TOKEN=your_token_here"
    fi
}

# Test 3: Session State Management
test_session_state_management() {
    print_header "TEST 3: Session State Management"

    # Backup existing session file
    if [[ -f "$SESSION_FILE" ]]; then
        cp "$SESSION_FILE" "$SESSION_FILE.backup"
    fi

    # Create test session file
    TEST_SESSION="$SESSION_FILE.test"
    mkdir -p "$(dirname "$TEST_SESSION")"

    # Test: Add task ID
    echo "12345" > "$TEST_SESSION"
    if grep -q "^12345$" "$TEST_SESSION"; then
        pass "Can write task ID to session file"
    else
        fail "Failed to write task ID to session file"
    fi

    # Test: Add multiple task IDs
    echo "67890" >> "$TEST_SESSION"
    echo "11111" >> "$TEST_SESSION"

    LINE_COUNT=$(wc -l < "$TEST_SESSION" | tr -d ' ')
    if [[ "$LINE_COUNT" == "3" ]]; then
        pass "Can append multiple task IDs"
    else
        fail "Multiple task IDs not appended correctly" "Expected 3 lines, got $LINE_COUNT"
    fi

    # Test: Remove specific task ID
    grep -v "^67890$" "$TEST_SESSION" > "${TEST_SESSION}.tmp"
    mv "${TEST_SESSION}.tmp" "$TEST_SESSION"

    if ! grep -q "^67890$" "$TEST_SESSION" 2>/dev/null; then
        pass "Can remove specific task ID from session"
    else
        fail "Failed to remove task ID from session"
    fi

    # Test: Verify remaining tasks
    if grep -q "^12345$" "$TEST_SESSION" && grep -q "^11111$" "$TEST_SESSION"; then
        pass "Other task IDs remain intact after removal"
    else
        fail "Session file corrupted after removal operation"
    fi

    # Cleanup
    rm -f "$TEST_SESSION" "${TEST_SESSION}.tmp"

    # Restore backup
    if [[ -f "$SESSION_FILE.backup" ]]; then
        mv "$SESSION_FILE.backup" "$SESSION_FILE"
    fi
}

# Test 4: Script Input Validation
test_script_input_validation() {
    print_header "TEST 4: Script Input Validation"

    # Test: No arguments
    OUTPUT=$("$TOGGLE_SCRIPT" 2>&1 || true)
    if echo "$OUTPUT" | grep -q "Error: Task ID required"; then
        pass "Script rejects missing task ID"
    else
        fail "Script should reject missing task ID" "Got: $OUTPUT"
    fi

    # Test: Empty task ID
    OUTPUT=$("$TOGGLE_SCRIPT" "" "active" 2>&1 || true)
    if echo "$OUTPUT" | grep -q "Error: Task ID required"; then
        pass "Script rejects empty task ID"
    else
        fail "Script should reject empty task ID" "Got: $OUTPUT"
    fi
}

# Test 5: API Endpoint Selection
test_api_endpoint_selection() {
    print_header "TEST 5: API Endpoint Logic"

    # We can't make real API calls in tests, but we can verify the script logic
    # by checking the script content

    if grep -q "tasks/.*close" "$TOGGLE_SCRIPT"; then
        pass "Script uses /close endpoint for completion"
    else
        fail "Script missing /close endpoint logic"
    fi

    if grep -q "tasks/.*reopen" "$TOGGLE_SCRIPT"; then
        pass "Script uses /reopen endpoint for reopening"
    else
        fail "Script missing /reopen endpoint logic"
    fi

    # Verify state-based branching
    if grep -q 'if.*CURRENT_STATE.*completed' "$TOGGLE_SCRIPT"; then
        pass "Script has state-based endpoint selection"
    else
        fail "Script missing state-based logic"
    fi
}

# Test 6: Popup Integration Points
test_popup_integration() {
    print_header "TEST 6: Popup Integration Points"

    # Check for session file usage
    if grep -q "COMPLETED_TASKS_FILE" "$POPUP_SCRIPT"; then
        pass "Popup script defines COMPLETED_TASKS_FILE variable"
    else
        fail "Popup script missing COMPLETED_TASKS_FILE variable"
    fi

    # Check for completion state detection
    if grep -q "IS_COMPLETED" "$POPUP_SCRIPT"; then
        pass "Popup script has completion state detection"
    else
        fail "Popup script missing completion state detection"
    fi

    # Check for strikethrough rendering
    if grep -q "sed.*̶" "$POPUP_SCRIPT"; then
        pass "Popup script has strikethrough rendering logic"
    else
        fail "Popup script missing strikethrough rendering"
    fi

    # Check for completion toggle click handler
    if grep -q "todoist-toggle-complete.sh" "$POPUP_SCRIPT"; then
        pass "Popup script has click handler for completion toggle"
    else
        fail "Popup script missing completion toggle handler"
    fi

    # Check for COMPLETION_STATE variable
    if grep -q "COMPLETION_STATE" "$POPUP_SCRIPT"; then
        pass "Popup script tracks completion state for API calls"
    else
        fail "Popup script missing COMPLETION_STATE tracking"
    fi
}

# Test 7: Visual State Logic
test_visual_state_logic() {
    print_header "TEST 7: Visual State Logic"

    # Test completed state styling
    if grep -q "IS_COMPLETED.*true" "$POPUP_SCRIPT" && \
       grep -q "TASK_LABEL_COLOR.*6e738d" "$POPUP_SCRIPT"; then
        pass "Completed tasks use grey color"
    else
        fail "Completed task styling incomplete"
    fi

    # Test filled circle for completed
    if grep -q "TASK_ICON.*●" "$POPUP_SCRIPT"; then
        pass "Completed tasks use filled circle icon"
    else
        fail "Missing filled circle icon for completed tasks"
    fi

    # Test working task highlight
    if grep -q "WORKING_TASK_ID" "$POPUP_SCRIPT" && \
       grep -q "TASK_BG.*YELLOW" "$POPUP_SCRIPT"; then
        pass "Working tasks have yellow background"
    else
        fail "Working task highlight not properly configured"
    fi
}

# Test 8: Precache Trigger
test_precache_trigger() {
    print_header "TEST 8: Precache Integration"

    if grep -q "todoist-precache.sh" "$TOGGLE_SCRIPT"; then
        pass "Toggle script triggers precache refresh"
    else
        fail "Toggle script missing precache trigger"
    fi

    # Check for background execution
    if grep -q "todoist-precache.sh.*&" "$TOGGLE_SCRIPT"; then
        pass "Precache refresh runs in background"
    else
        fail "Precache refresh not backgrounded (will block UI)"
    fi
}

# Test 9: Error Handling
test_error_handling() {
    print_header "TEST 9: Error Handling"

    # Check for HTTP code validation
    if grep -q 'HTTP_CODE.*204.*200' "$TOGGLE_SCRIPT"; then
        pass "Script validates HTTP response codes"
    else
        fail "Script missing HTTP response validation"
    fi

    # Check for API token validation
    if grep -q 'TODOIST_API_TOKEN.*not found' "$TOGGLE_SCRIPT"; then
        pass "Script validates API token existence"
    else
        fail "Script missing API token validation"
    fi

    # Check for error exit codes
    if grep -q 'exit 1' "$TOGGLE_SCRIPT"; then
        pass "Script uses proper exit codes for errors"
    else
        fail "Script missing error exit codes"
    fi
}

# Test 10: Cache Directory Creation
test_cache_directory() {
    print_header "TEST 10: Cache Directory Handling"

    if grep -q "mkdir -p" "$TOGGLE_SCRIPT"; then
        pass "Toggle script creates cache directory if needed"
    else
        fail "Toggle script missing cache directory creation"
    fi

    # Verify cache directory exists
    if [[ -d "$CACHE_DIR" ]]; then
        pass "Cache directory exists at: $CACHE_DIR"
    else
        fail "Cache directory does not exist" "Will be created on first use"
    fi
}

# Run all tests
main() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║  TODOIST COMPLETION TOGGLE - COMPREHENSIVE TEST SUITE        ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    cleanup_test_files

    test_file_existence
    test_env_configuration
    test_session_state_management
    test_script_input_validation
    test_api_endpoint_selection
    test_popup_integration
    test_visual_state_logic
    test_precache_trigger
    test_error_handling
    test_cache_directory

    # Print summary
    print_header "TEST SUMMARY"
    echo -e "Total Tests:  ${BLUE}${TESTS_RUN}${NC}"
    echo -e "Passed:       ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Failed:       ${RED}${TESTS_FAILED}${NC}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  ALL TESTS PASSED! ✓${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        exit 0
    else
        echo -e "\n${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}  TESTS FAILED: ${TESTS_FAILED}/${TESTS_RUN} ✗${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        exit 1
    fi

    cleanup_test_files
}

# Run tests
main "$@"
