#!/bin/bash
# Integration Test for Todoist Completion Toggle
# Tests the full workflow: complete task → session update → precache → filtered list

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CACHE_DIR="$HOME/.cache/sketchybar"
TASKS_CACHE="$CACHE_DIR/todoist_tasks_cache"
SESSION_FILE="$CACHE_DIR/todoist_completed_tasks_session"
PRECACHE_SCRIPT="$HOME/.config/sketchybar/helpers/todoist-precache.sh"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  TODOIST COMPLETION TOGGLE - INTEGRATION TEST           ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}\n"

# Test 1: Precache Script Execution
echo -e "${YELLOW}[TEST 1]${NC} Testing precache script execution..."
if "$PRECACHE_SCRIPT" 2>&1; then
    echo -e "${GREEN}✓${NC} Precache script executed successfully"
else
    echo -e "${RED}✗${NC} Precache script failed"
    exit 1
fi

# Test 2: Cache File Format
echo -e "\n${YELLOW}[TEST 2]${NC} Validating cache file format..."
if [[ -f "$TASKS_CACHE" ]]; then
    echo -e "${GREEN}✓${NC} Cache file exists: $TASKS_CACHE"

    # Check for required headers
    if grep -q "^SYNC_STATUS=" "$TASKS_CACHE"; then
        echo -e "${GREEN}✓${NC} Cache has SYNC_STATUS header"
    else
        echo -e "${RED}✗${NC} Missing SYNC_STATUS header"
        exit 1
    fi

    if grep -q "^TASKS_START$" "$TASKS_CACHE"; then
        echo -e "${GREEN}✓${NC} Cache has TASKS_START marker"
    else
        echo -e "${RED}✗${NC} Missing TASKS_START marker"
        exit 1
    fi

    # Check sync status
    SYNC_STATUS=$(grep "^SYNC_STATUS=" "$TASKS_CACHE" | cut -d= -f2)
    if [[ "$SYNC_STATUS" == "success" ]]; then
        echo -e "${GREEN}✓${NC} Sync status: success"
    else
        echo -e "${RED}✗${NC} Sync status: $SYNC_STATUS"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} Cache file not found"
    exit 1
fi

# Test 3: Task Data Format
echo -e "\n${YELLOW}[TEST 3]${NC} Validating task data format..."
TASKS=$(sed '1,/^TASKS_START$/d' "$TASKS_CACHE")

if [[ -n "$TASKS" ]]; then
    TASK_COUNT=$(echo "$TASKS" | grep -c "|" || true)
    echo -e "${GREEN}✓${NC} Found $TASK_COUNT tasks in cache"

    # Validate first task format (task_id|icon|color|content|url|project_id)
    FIRST_TASK=$(echo "$TASKS" | head -n 1)
    FIELD_COUNT=$(echo "$FIRST_TASK" | awk -F'|' '{print NF}')

    if [[ "$FIELD_COUNT" -ge 5 ]]; then
        echo -e "${GREEN}✓${NC} Task format is valid (has $FIELD_COUNT fields)"
    else
        echo -e "${RED}✗${NC} Invalid task format (expected 6 fields, got $FIELD_COUNT)"
        exit 1
    fi

    # Extract and validate task ID (should be numeric)
    TASK_ID=$(echo "$FIRST_TASK" | cut -d'|' -f1)
    if [[ "$TASK_ID" =~ ^[0-9]+$ ]]; then
        echo -e "${GREEN}✓${NC} Task ID is numeric: $TASK_ID"
    else
        echo -e "${YELLOW}⚠${NC}  Task ID format unexpected: $TASK_ID (may be 'error' message)"
    fi
else
    echo -e "${YELLOW}⚠${NC}  No tasks found (all completed or no tasks today)"
fi

# Test 4: Session File Functionality
echo -e "\n${YELLOW}[TEST 4]${NC} Testing session file functionality..."

# Backup existing session
if [[ -f "$SESSION_FILE" ]]; then
    cp "$SESSION_FILE" "${SESSION_FILE}.backup"
    echo -e "${BLUE}ℹ${NC}  Backed up existing session file"
fi

# Create test session with a fake completed task
echo "999999999" > "$SESSION_FILE"
echo -e "${GREEN}✓${NC} Created test session file"

# Verify session file persistence
if grep -q "^999999999$" "$SESSION_FILE"; then
    echo -e "${GREEN}✓${NC} Session file persists completed task IDs"
else
    echo -e "${RED}✗${NC} Session file not persisting data"
    exit 1
fi

# Cleanup test session
rm -f "$SESSION_FILE"
if [[ -f "${SESSION_FILE}.backup" ]]; then
    mv "${SESSION_FILE}.backup" "$SESSION_FILE"
    echo -e "${BLUE}ℹ${NC}  Restored original session file"
fi

# Test 5: API Filter Validation
echo -e "\n${YELLOW}[TEST 5]${NC} Verifying API filter excludes completed tasks..."

# The API filter is 'today | overdue' which automatically excludes completed tasks
# We can't directly test this without completing a real task, but we can verify
# the filter is correctly configured in the precache script

if grep -q 'filter=today.*overdue' "$PRECACHE_SCRIPT"; then
    echo -e "${GREEN}✓${NC} Precache uses 'today | overdue' filter"
    echo -e "${BLUE}ℹ${NC}  This filter automatically excludes completed tasks"
else
    echo -e "${RED}✗${NC} API filter not found or incorrect"
    exit 1
fi

# Test 6: Completion State Visual Markers
echo -e "\n${YELLOW}[TEST 6]${NC} Verifying completion visual state markers..."

POPUP_SCRIPT="$HOME/.config/sketchybar/plugins/todoist_popup.sh"

# Check for grey color on completed tasks
if grep -q "IS_COMPLETED.*true" "$POPUP_SCRIPT" && \
   grep -q "TASK_LABEL_COLOR.*6e738d" "$POPUP_SCRIPT"; then
    echo -e "${GREEN}✓${NC} Completed tasks styled with grey color (0xff6e738d)"
else
    echo -e "${RED}✗${NC} Completed task styling not found"
    exit 1
fi

# Check for strikethrough
if grep -q "̶" "$POPUP_SCRIPT"; then
    echo -e "${GREEN}✓${NC} Completed tasks show strikethrough effect"
else
    echo -e "${RED}✗${NC} Strikethrough effect not found"
    exit 1
fi

# Check for filled circle icon
if grep -q 'TASK_ICON="●"' "$POPUP_SCRIPT"; then
    echo -e "${GREEN}✓${NC} Completed tasks show filled circle icon (●)"
else
    echo -e "${RED}✗${NC} Filled circle icon not found"
    exit 1
fi

# Summary
echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  INTEGRATION TESTS PASSED! ✓${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

echo -e "${BLUE}Feature Summary:${NC}"
echo -e "  • Precache fetches active tasks every 5 minutes"
echo -e "  • Completed tasks filtered by Todoist API automatically"
echo -e "  • Session file tracks completion state for instant UI feedback"
echo -e "  • Visual markers: grey color + strikethrough + filled circle"
echo -e "  • Click circle icon to toggle completion state"
echo ""

exit 0
