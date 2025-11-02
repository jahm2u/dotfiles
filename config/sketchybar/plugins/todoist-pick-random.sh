#!/bin/bash
# Pick a random task from the cached task list and set as current

CACHE_DIR="$HOME/.cache/sketchybar"
TASKS_CACHE="$CACHE_DIR/todoist_tasks_cache"
CURRENT_TASK_FILE="$CACHE_DIR/todoist_current_task"

if [[ ! -f "$TASKS_CACHE" ]]; then
    echo "No tasks cache"
    rm -f "$CURRENT_TASK_FILE"
    sketchybar --trigger todoist_update
    exit 0
fi

# Read tasks from cache
SYNC_STATUS=$(grep "^SYNC_STATUS=" "$TASKS_CACHE" | cut -d= -f2)
TASKS_DATA=$(sed '1,/^TASKS_START$/d' "$TASKS_CACHE")

if [[ "$SYNC_STATUS" != "success" ]] || [[ -z "$TASKS_DATA" ]]; then
    echo "No tasks available"
    rm -f "$CURRENT_TASK_FILE"
    sketchybar --trigger todoist_update
    exit 0
fi

# Count tasks
TASK_COUNT=$(echo "$TASKS_DATA" | wc -l | tr -d ' ')

if [[ "$TASK_COUNT" -eq 0 ]]; then
    echo "No tasks"
    rm -f "$CURRENT_TASK_FILE"
    sketchybar --trigger todoist_update
    exit 0
fi

# Pick random task (1 to TASK_COUNT)
RANDOM_INDEX=$((RANDOM % TASK_COUNT + 1))
TASK_LINE=$(echo "$TASKS_DATA" | sed -n "${RANDOM_INDEX}p")

if [[ -n "$TASK_LINE" ]]; then
    TASK_ID=$(echo "$TASK_LINE" | cut -d'|' -f1)
    echo "$TASK_ID" > "$CURRENT_TASK_FILE"
    echo "Picked random task: $TASK_ID"
else
    # Fallback to first task
    TASK_ID=$(echo "$TASKS_DATA" | head -n 1 | cut -d'|' -f1)
    echo "$TASK_ID" > "$CURRENT_TASK_FILE"
    echo "Picked first task: $TASK_ID"
fi

# Force immediate widget update by calling script directly
~/.config/sketchybar/plugins/todoist.sh &

exit 0
