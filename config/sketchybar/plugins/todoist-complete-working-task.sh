#!/bin/bash
# Complete the current working/focus task via Todoist API
# Called when clicking the todoist icon in the bar

CACHE_DIR="$HOME/.cache/sketchybar"
WORKING_TASK_FILE="$CACHE_DIR/todoist_working_task"

# Check if there's a working task
if [[ ! -f "$WORKING_TASK_FILE" ]]; then
    echo "No working task set"
    exit 0
fi

TASK_ID=$(cat "$WORKING_TASK_FILE")

if [[ -z "$TASK_ID" ]]; then
    echo "Working task file is empty"
    exit 0
fi

# Source .env for API token
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
    echo "Error: TODOIST_API_TOKEN not found"
    exit 1
fi

# Call Todoist API to close/complete the task
HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null -X POST \
    "https://api.todoist.com/api/v1/tasks/${TASK_ID}/close" \
    -H "Authorization: Bearer $TODOIST_API_TOKEN")

if [[ "$HTTP_CODE" == "204" ]] || [[ "$HTTP_CODE" == "200" ]]; then
    # Success - clear the working task
    rm -f "$WORKING_TASK_FILE"

    # Trigger precache refresh to update the task list
    ~/.config/sketchybar/helpers/todoist-precache.sh &

    # Trigger widget update
    sketchybar --trigger todoist_focus_changed

    echo "Task $TASK_ID marked as complete"
    exit 0
else
    echo "Error: API returned $HTTP_CODE"
    exit 1
fi
