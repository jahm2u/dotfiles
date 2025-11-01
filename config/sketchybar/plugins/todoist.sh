#!/usr/bin/env bash

# Cache directory for state management
CACHE_DIR="$HOME/.cache/sketchybar"
WORKING_TASK_FILE="$CACHE_DIR/todoist_working_task"
mkdir -p "$CACHE_DIR"

# Completion messages for when all tasks are done (Story 3.1)
COMPLETION_MESSAGES=(
    "All done! 🎉"
    "Inbox zero! ✨"
    "Tasks cleared! 🏆"
    "You crushed it! 💪"
    "Nothing left! 🌟"
    "Completed all! ✅"
    "Todo-free! 🎊"
    "Mission done! 🚀"
    "List empty! 🎯"
    "Nailed it! 🔨"
    "Finished! 🏁"
    "Victory! 👑"
    "Conquered! ⚔️"
    "Perfect! 💎"
    "Champion! 🥇"
)

# Function to get random completion message
get_random_completion_message() {
    local count=${#COMPLETION_MESSAGES[@]}
    local index=$((RANDOM % count))
    echo "${COMPLETION_MESSAGES[$index]}"
}

# Source the .env file to get TODOIST_API_TOKEN
# Try multiple locations to find .env file
ENV_FILE=""
for possible_location in \
    "$HOME/dotfiles/.env" \
    "$HOME/repos/02_personal/dotfiles/.env" \
    "$HOME/.config/sketchybar/../../.env" \
    "$(dirname "$(dirname "$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")")")/../../.env"
do
    if [[ -f "$possible_location" ]]; then
        ENV_FILE="$possible_location"
        break
    fi
done

if [[ -n "$ENV_FILE" ]] && [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
fi

if [[ -z "$TODOIST_API_TOKEN" ]]; then
    sketchybar --set "${NAME}.name" label="No Todoist token"
    exit 0
fi

# Fetch tasks from Todoist API
# Get active tasks sorted by priority (4=urgent, 3=high, 2=medium, 1=normal)
RESPONSE=$(curl -s -w "\n%{http_code}" -X GET \
    "https://api.todoist.com/rest/v2/tasks?filter=today%20%7C%20overdue" \
    -H "Authorization: Bearer $TODOIST_API_TOKEN")

# Extract HTTP status code and response body
HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

# Check if API call was successful
if [[ "$HTTP_CODE" != "200" ]]; then
    sketchybar --set "${NAME}.name" label="API Error"
    exit 0
fi

# If no tasks and API succeeded, show random completion message
if [[ -z "$RESPONSE_BODY" ]] || [[ "$RESPONSE_BODY" == "[]" ]]; then
    COMPLETION_MSG=$(get_random_completion_message)
    sketchybar --set "${NAME}.name" label="$COMPLETION_MSG"
    exit 0
fi

# Update RESPONSE to use RESPONSE_BODY for the rest of the script
RESPONSE="$RESPONSE_BODY"

# Check if there's a "working on" task
WORKING_TASK_ID=""
if [[ -f "$WORKING_TASK_FILE" ]]; then
    WORKING_TASK_ID=$(cat "$WORKING_TASK_FILE")
fi

# Parse the task to display (either working task or highest priority)
TASK=$(echo "$RESPONSE" | python3 -c "
import sys, json

try:
    tasks = json.load(sys.stdin)
    if not tasks:
        print('No tasks')
        sys.exit(0)

    working_task_id = '$WORKING_TASK_ID'
    selected_task = None

    # If there's a working task, try to find it
    if working_task_id:
        for task in tasks:
            if str(task.get('id', '')) == working_task_id:
                selected_task = task
                break

    # If no working task found, get highest priority task
    if not selected_task:
        sorted_tasks = sorted(tasks, key=lambda x: (-x.get('priority', 1), x.get('due', {}).get('date', '9999-12-31')))
        selected_task = sorted_tasks[0]

    content = selected_task.get('content', 'No task')
    priority = selected_task.get('priority', 1)
    is_working = str(selected_task.get('id', '')) == working_task_id

    # Truncate if too long (fixed width)
    if len(content) > 40:
        content = content[:37] + '...'

    # Add working indicator
    if is_working:
        content = '▶ ' + content

    # Priority icon
    if priority == 4:
        icon = '󰄴'  # Urgent/P1
    elif priority == 3:
        icon = '󰄵'  # High/P2
    elif priority == 2:
        icon = '󰄶'  # Medium/P3
    else:
        icon = '󰃯'  # Normal/P4

    print(f'{icon}|{content}')

except Exception as e:
    print('󰃯|Error loading tasks')
")

# Split icon and content
IFS='|' read -r ICON CONTENT <<< "$TASK"

if [[ -z "$ICON" ]]; then
    ICON="󰃯"
fi

if [[ -z "$CONTENT" ]]; then
    CONTENT="No tasks"
fi

# Update sketchybar items
sketchybar --set "$NAME" icon="$ICON" \
           --set "${NAME}.name" label="$CONTENT"