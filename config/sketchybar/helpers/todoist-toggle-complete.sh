#!/bin/bash
# Toggle task completion status via Todoist API
# Usage: todoist-toggle-complete.sh <task_id> <current_state>
# current_state: "active" or "completed"

TASK_ID="$1"
CURRENT_STATE="$2"

if [[ -z "$TASK_ID" ]]; then
    echo "Error: Task ID required"
    exit 1
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

# Determine action based on current state
if [[ "$CURRENT_STATE" == "completed" ]]; then
    # Reopen the task
    ENDPOINT="https://api.todoist.com/rest/v2/tasks/${TASK_ID}/reopen"
else
    # Close/complete the task
    ENDPOINT="https://api.todoist.com/rest/v2/tasks/${TASK_ID}/close"
fi

# Make API call
HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null -X POST "$ENDPOINT" \
    -H "Authorization: Bearer $TODOIST_API_TOKEN")

if [[ "$HTTP_CODE" == "204" ]] || [[ "$HTTP_CODE" == "200" ]]; then
    # Success - update session state file
    COMPLETED_TASKS_FILE="$HOME/.cache/sketchybar/todoist_completed_tasks_session"
    mkdir -p "$(dirname "$COMPLETED_TASKS_FILE")"

    if [[ "$CURRENT_STATE" == "completed" ]]; then
        # Reopened - remove from completed list
        grep -v "^${TASK_ID}$" "$COMPLETED_TASKS_FILE" > "${COMPLETED_TASKS_FILE}.tmp" 2>/dev/null || true
        mv "${COMPLETED_TASKS_FILE}.tmp" "$COMPLETED_TASKS_FILE" 2>/dev/null || true
    else
        # Completed - add to completed list
        echo "$TASK_ID" >> "$COMPLETED_TASKS_FILE"
    fi

    # Trigger precache refresh in background to update list
    ~/.config/sketchybar/helpers/todoist-precache.sh &
    exit 0
else
    echo "Error: API returned $HTTP_CODE"
    exit 1
fi
