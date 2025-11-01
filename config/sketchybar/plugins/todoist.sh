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

# Read from precached tasks (updated every 30 seconds by LaunchAgent)
CACHE_FILE="$CACHE_DIR/todoist_tasks_cache"

if [[ ! -f "$CACHE_FILE" ]]; then
    sketchybar --set "${NAME}.name" label="Loading tasks..."
    exit 0
fi

# Read cache status and tasks
SYNC_STATUS=$(grep "^SYNC_STATUS=" "$CACHE_FILE" | cut -d= -f2)
TASKS_DATA=$(sed '1,/^TASKS_START$/d' "$CACHE_FILE")

# Check sync status
if [[ "$SYNC_STATUS" == "failed" ]]; then
    sketchybar --set "${NAME}.name" label="Sync failed"
    exit 0
fi

# If no tasks in cache, show random completion message
if [[ -z "$TASKS_DATA" ]]; then
    COMPLETION_MSG=$(get_random_completion_message)
    sketchybar --set "${NAME}.name" label="$COMPLETION_MSG"
    exit 0
fi

# Check if there's a "working on" task
WORKING_TASK_ID=""
if [[ -f "$WORKING_TASK_FILE" ]]; then
    WORKING_TASK_ID=$(cat "$WORKING_TASK_FILE")
fi

# Parse tasks from cache (format: TASK_ID|ICON|COLOR|CONTENT|URL|PROJECT_ID)
TASK=""

# If working task exists, find it quickly with grep
if [[ -n "$WORKING_TASK_ID" ]]; then
    TASK_LINE=$(grep "^${WORKING_TASK_ID}|" <<< "$TASKS_DATA" | head -n 1)
    if [[ -n "$TASK_LINE" ]]; then
        IFS='|' read -r TASK_ID ICON COLOR CONTENT URL PROJECT_ID <<< "$TASK_LINE"
        TASK="$ICON|▶ $CONTENT"
    fi
fi

# If no working task found, use first task (highest priority from cache)
if [[ -z "$TASK" ]]; then
    FIRST_LINE=$(echo "$TASKS_DATA" | head -n 1)
    if [[ -n "$FIRST_LINE" ]]; then
        IFS='|' read -r TASK_ID ICON COLOR CONTENT URL PROJECT_ID <<< "$FIRST_LINE"
        TASK="$ICON|$CONTENT"
    fi
fi

# Fallback if still nothing
if [[ -z "$TASK" ]]; then
    TASK="󰃯|No tasks"
fi

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