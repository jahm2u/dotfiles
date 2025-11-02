#!/usr/bin/env bash

# Cache directory for state management
CACHE_DIR="$HOME/.cache/sketchybar"
CURRENT_TASK_FILE="$CACHE_DIR/todoist_current_task"
PENDING_COMPLETE_FILE="$CACHE_DIR/todoist_pending_complete"
TASKS_CACHE="$CACHE_DIR/todoist_tasks_cache"
mkdir -p "$CACHE_DIR"

# Completion messages for when all tasks are done
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
    sketchybar --set "${NAME}.name" label="No Todoist token"
    exit 0
fi

# Read from precached tasks
if [[ ! -f "$TASKS_CACHE" ]]; then
    sketchybar --set "${NAME}.name" label="Loading tasks..."
    exit 0
fi

# Read cache status and tasks
SYNC_STATUS=$(grep "^SYNC_STATUS=" "$TASKS_CACHE" | cut -d= -f2)
TASKS_DATA=$(sed '1,/^TASKS_START$/d' "$TASKS_CACHE")

# Check sync status
if [[ "$SYNC_STATUS" == "failed" ]]; then
    sketchybar --set "${NAME}.name" label="Sync failed"
    exit 0
fi

# If no tasks in cache, show random completion message
if [[ -z "$TASKS_DATA" ]]; then
    COMPLETION_MSG=$(get_random_completion_message)
    sketchybar --set "${NAME}.name" label="$COMPLETION_MSG"
    sketchybar --set "$NAME" icon="✨"
    rm -f "$CURRENT_TASK_FILE"
    exit 0
fi

# Get current task ID (or pick one if none set)
if [[ ! -f "$CURRENT_TASK_FILE" ]] || [[ ! -s "$CURRENT_TASK_FILE" ]]; then
    # No current task - pick first one (highest priority)
    FIRST_LINE=$(echo "$TASKS_DATA" | head -n 1)
    TASK_ID=$(echo "$FIRST_LINE" | cut -d'|' -f1)
    echo "$TASK_ID" > "$CURRENT_TASK_FILE"
else
    TASK_ID=$(cat "$CURRENT_TASK_FILE")
fi

# Every 5 seconds, check via API if current task is complete
# Only check if SENDER is "routine" (from update_freq)
if [[ "$SENDER" == "routine" ]]; then
    # Check if task still exists in Todoist
    HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null -X GET \
        "https://api.todoist.com/rest/v2/tasks/${TASK_ID}" \
        -H "Authorization: Bearer $TODOIST_API_TOKEN")

    if [[ "$HTTP_CODE" == "404" ]]; then
        # Task completed elsewhere (phone, web, etc) - pick new random task
        ~/.config/sketchybar/plugins/todoist-pick-random.sh &
        exit 0
    fi
fi

# Find the task in cache
TASK_LINE=$(grep "^${TASK_ID}|" <<< "$TASKS_DATA" | head -n 1)

if [[ -z "$TASK_LINE" ]]; then
    # Task not in cache anymore - pick new one
    ~/.config/sketchybar/plugins/todoist-pick-random.sh &
    exit 0
fi

# Parse task details
IFS='|' read -r TASK_ID ICON COLOR CONTENT URL PROJECT_ID <<< "$TASK_LINE"

# Check if pending completion (countdown active)
IS_PENDING=false
if [[ -f "$PENDING_COMPLETE_FILE" ]] && grep -q "^${TASK_ID}$" "$PENDING_COMPLETE_FILE"; then
    IS_PENDING=true
fi

# Set icon and content based on state
if [[ "$IS_PENDING" == true ]]; then
    # Pending completion - show checked box and strikethrough
    DISPLAY_ICON="󰄵"  # Nerd Font: checkbox-marked (click to undo)
    DISPLAY_CONTENT="$(echo "$CONTENT" | sed 's/./&̶/g')"  # Strikethrough
else
    # Normal state - show unchecked box
    DISPLAY_ICON="󰄱"  # Nerd Font: checkbox-blank-outline (click to mark complete)
    DISPLAY_CONTENT="$CONTENT"
fi

# Truncate if too long
if [[ ${#DISPLAY_CONTENT} -gt 40 ]]; then
    DISPLAY_CONTENT="${DISPLAY_CONTENT:0:37}..."
fi

# Update sketchybar items
sketchybar --set "$NAME" icon="$DISPLAY_ICON" \
           --set "${NAME}.name" label="$DISPLAY_CONTENT"
