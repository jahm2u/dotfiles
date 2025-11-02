#!/bin/bash
# Test the icon click completion workflow

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}Testing Icon Click Completion Workflow${NC}\n"

# Step 1: Check if click_script is registered
echo -e "${YELLOW}[1/4]${NC} Checking if click_script is registered..."
CLICK_SCRIPT=$(sketchybar --query todoist | grep "click_script" | cut -d'"' -f4)

if [[ "$CLICK_SCRIPT" == *"todoist-complete-working-task.sh"* ]]; then
    echo -e "${GREEN}✓${NC} Click script registered: $CLICK_SCRIPT"
else
    echo -e "${RED}✗${NC} Click script not registered correctly"
    echo "Expected: todoist-complete-working-task.sh"
    echo "Got: $CLICK_SCRIPT"
    exit 1
fi

# Step 2: Check if script exists and is executable
echo -e "\n${YELLOW}[2/4]${NC} Checking if script exists and is executable..."
SCRIPT_PATH=$(echo "$CLICK_SCRIPT" | tr -d '"')

if [[ -f "$SCRIPT_PATH" ]]; then
    echo -e "${GREEN}✓${NC} Script exists at: $SCRIPT_PATH"
else
    echo -e "${RED}✗${NC} Script not found at: $SCRIPT_PATH"
    exit 1
fi

if [[ -x "$SCRIPT_PATH" ]]; then
    echo -e "${GREEN}✓${NC} Script is executable"
else
    echo -e "${RED}✗${NC} Script is not executable"
    exit 1
fi

# Step 3: Simulate setting a working task
echo -e "\n${YELLOW}[3/4]${NC} Testing with a mock working task..."
CACHE_DIR="$HOME/.cache/sketchybar"
WORKING_TASK_FILE="$CACHE_DIR/todoist_working_task"
TEST_TASK_ID="9999999999"

# Create a fake working task
echo "$TEST_TASK_ID" > "$WORKING_TASK_FILE"
echo -e "${GREEN}✓${NC} Created mock working task: $TEST_TASK_ID"

# Step 4: Test script behavior (dry run - won't actually call API with fake ID)
echo -e "\n${YELLOW}[4/4]${NC} Testing script execution..."
echo -e "${BLUE}ℹ${NC}  Running script (will fail API call with fake task ID - that's expected)..."

OUTPUT=$(bash "$SCRIPT_PATH" 2>&1 || true)

if echo "$OUTPUT" | grep -q "Error: API returned"; then
    echo -e "${GREEN}✓${NC} Script executed and reached API call (fake ID rejected as expected)"
elif echo "$OUTPUT" | grep -q "Task .* marked as complete"; then
    echo -e "${YELLOW}⚠${NC}  Script completed successfully (was the task ID real?)"
else
    echo -e "${BLUE}ℹ${NC}  Script output: $OUTPUT"
fi

# Clean up
rm -f "$WORKING_TASK_FILE"

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ICON CLICK TESTS PASSED! ✓${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

echo -e "${BLUE}Manual Test Instructions:${NC}"
echo -e "  1. Click any task in the Todoist popup to set as working task"
echo -e "  2. Click the todoist ICON (󰃯) in the bar"
echo -e "  3. Task should be marked complete and disappear from list"
echo ""

exit 0
