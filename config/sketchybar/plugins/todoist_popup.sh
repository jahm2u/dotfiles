#!/usr/bin/env bash

# Todoist Widget Popup - Shows top 5 priority tasks with actions
# Usage: Called when todoist widget is clicked
# Shows: Top 5 tasks with priority, action buttons to open in Todoist or mark as working on

# Close all other popups first
sketchybar --set meeting popup.drawing=off \
           --set cpu popup.drawing=off \
           --set memory popup.drawing=off \
           --set week_num popup.drawing=off

CACHE_DIR="$HOME/.cache/sketchybar"
WORKING_TASK_FILE="$CACHE_DIR/todoist_working_task"

# Load environment colors
source "$HOME/.config/sketchybar/helpers/source-colors.sh"

# Source the .env file to get TODOIST_API_TOKEN
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

if [[ -n "$ENV_FILE" ]] && [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
fi

if [[ -z "$TODOIST_API_TOKEN" ]]; then
    sketchybar --set todoist.popup drawing=off
    exit 0
fi

# Fetch tasks from Todoist API
RESPONSE=$(curl -s -X GET \
    "https://api.todoist.com/rest/v2/tasks?filter=today%20%7C%20overdue" \
    -H "Authorization: Bearer $TODOIST_API_TOKEN")

# Check if API call was successful
if [[ -z "$RESPONSE" ]] || [[ "$RESPONSE" == "[]" ]]; then
    sketchybar --set todoist.popup drawing=off
    exit 0
fi

# Parse top 5 tasks
TASKS=$(echo "$RESPONSE" | python3 -c "
import sys, json

try:
    tasks = json.load(sys.stdin)
    if not tasks:
        sys.exit(0)

    # Sort by priority (highest first), then by due date
    sorted_tasks = sorted(tasks, key=lambda x: (-x.get('priority', 1), x.get('due', {}).get('date', '9999-12-31')))

    # Get top 5 tasks
    top_tasks = sorted_tasks[:5]

    for task in top_tasks:
        task_id = task.get('id', '')
        content = task.get('content', 'No task')
        priority = task.get('priority', 1)
        url = task.get('url', '')

        # Truncate if too long
        if len(content) > 40:
            content = content[:37] + '...'

        # Priority icon
        if priority == 4:
            icon = '󰄴'  # Urgent/P1
        elif priority == 3:
            icon = '󰄵'  # High/P2
        elif priority == 2:
            icon = '󰄶'  # Medium/P3
        else:
            icon = '󰃯'  # Normal/P4

        print(f'{task_id}|{icon}|{content}|{url}')

except Exception as e:
    print(f'error|󰃯|Error loading tasks|')
")

# Create cache directory if needed
mkdir -p "$CACHE_DIR"

# Populate popup items
TASK_INDEX=1
while IFS='|' read -r TASK_ID ICON CONTENT URL; do
    [[ -z "$TASK_ID" ]] && continue

    item_name="todoist.popup.task_${TASK_INDEX}"
    action_name="todoist.popup.action_${TASK_INDEX}"

    if [[ "$TASK_ID" == "error" ]]; then
        sketchybar --set "$item_name" \
            label="$CONTENT" \
            label.color="$RED" \
            icon="$ICON" \
            icon.color="$RED" \
            drawing=on \
            --set "$action_name" drawing=off
    else
        # Check if this task is currently being worked on
        WORKING_TASK_ID=""
        if [[ -f "$WORKING_TASK_FILE" ]]; then
            WORKING_TASK_ID=$(cat "$WORKING_TASK_FILE")
        fi

        if [[ "$TASK_ID" == "$WORKING_TASK_ID" ]]; then
            # Highlight working task
            TASK_BG="$YELLOW"
            TASK_LABEL_COLOR="$BLACK"
            TASK_ICON_COLOR="$BLACK"
            WORKING_INDICATOR=" [WORKING]"
        else
            TASK_BG="$TRANSPARENT"
            TASK_LABEL_COLOR="$LABEL_COLOR"
            TASK_ICON_COLOR="$LABEL_COLOR"
            WORKING_INDICATOR=""
        fi

        sketchybar --set "$item_name" \
            label="${CONTENT}${WORKING_INDICATOR}" \
            label.color="$TASK_LABEL_COLOR" \
            icon="$ICON" \
            icon.color="$TASK_ICON_COLOR" \
            background.color="$TASK_BG" \
            click_script="echo '$TASK_ID' > '$WORKING_TASK_FILE' && sketchybar --trigger todoist_update" \
            drawing=on

        # Action button to open in Todoist
        sketchybar --set "$action_name" \
            label="󰏌" \
            label.color="$BLUE" \
            icon.drawing=off \
            background.color="$TRANSPARENT" \
            click_script="open '$URL'" \
            drawing=on
    fi

    TASK_INDEX=$((TASK_INDEX + 1))
done <<< "$TASKS"

# Hide unused task slots
while [[ $TASK_INDEX -le 5 ]]; do
    sketchybar --set "todoist.popup.task_${TASK_INDEX}" drawing=off \
               --set "todoist.popup.action_${TASK_INDEX}" drawing=off
    TASK_INDEX=$((TASK_INDEX + 1))
done

# Toggle popup visibility
sketchybar --set todoist popup.drawing=toggle
