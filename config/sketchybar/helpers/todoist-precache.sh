#!/usr/bin/env bash

# Todoist Task Precache Script
# Runs every 5 minutes via LaunchAgent to provide instant popup performance
# Follows calendar sync architecture pattern

CACHE_DIR="$HOME/.cache/sketchybar"
TASKS_CACHE="$CACHE_DIR/todoist_tasks_cache"
LOG_FILE="$HOME/.config/sketchybar/logs/todoist-precache.log"

mkdir -p "$CACHE_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" >> "$LOG_FILE"
}

log "INFO" "Starting Todoist task precache sync"

# Source .env for TODOIST_API_TOKEN
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

if [[ -z "$ENV_FILE" ]] || [[ ! -f "$ENV_FILE" ]]; then
    log "ERROR" "Cannot find .env file with TODOIST_API_TOKEN"
    exit 2
fi

source "$ENV_FILE"

if [[ -z "$TODOIST_API_TOKEN" ]]; then
    log "ERROR" "TODOIST_API_TOKEN not set in .env"
    exit 2
fi

# Fetch tasks with timeout (using Todoist API v1)
RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 30 -G \
    "https://api.todoist.com/api/v1/tasks/filter" \
    --data-urlencode "query=today | overdue" \
    -H "Authorization: Bearer $TODOIST_API_TOKEN" 2>&1)

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" != "200" ]]; then
    log "ERROR" "Todoist API returned HTTP $HTTP_CODE"
    echo "SYNC_STATUS=failed" > "$TASKS_CACHE"
    exit 1
fi

if [[ -z "$RESPONSE_BODY" ]] || [[ "$RESPONSE_BODY" == "[]" ]] || [[ "$RESPONSE_BODY" == '{"results":[],"next_cursor":null}' ]]; then
    log "INFO" "No tasks found (all completed)"
    echo "SYNC_STATUS=success" > "$TASKS_CACHE"
    echo "TASKS_START" >> "$TASKS_CACHE"
    sketchybar --trigger todoist_synced
    exit 0
fi

# Parse tasks (top 25 sorted by priority) - increased from 5 to match Todoist's default view
TASKS=$(echo "$RESPONSE_BODY" | python3 -c "
import sys, json

try:
    data = json.load(sys.stdin)
    # API v1 wraps results in { results: [...], next_cursor: ... }
    tasks = data.get('results', data) if isinstance(data, dict) else data
    if not tasks:
        sys.exit(0)

    # Sort by priority, then due date
    sorted_tasks = sorted(tasks, key=lambda x: (-x.get('priority', 1), x.get('due', {}).get('date', '9999-12-31')))
    top_tasks = sorted_tasks[:25]  # Increased from 5 to 25 tasks

    for task in top_tasks:
        task_id = task.get('id', '')
        content = task.get('content', 'No task')
        priority = task.get('priority', 1)
        project_id = task.get('project_id', '')

        # Don't truncate - we'll make the popup wider
        # if len(content) > 40:
        #     content = content[:37] + '...'

        # Priority icons - using Unicode circles instead of Nerd Font icons
        # Matches Todoist UI: P1=red, P2=orange, P3=blue, P4=unfilled
        if priority == 4:
            icon = '●'  # Filled circle for P1 (highest priority)
            color = 'RED'  # Will be replaced with actual hex in popup script
        elif priority == 3:
            icon = '●'  # Filled circle for P2
            color = 'PEACH'
        elif priority == 2:
            icon = '●'  # Filled circle for P3
            color = 'BLUE'
        else:
            icon = '○'  # Unfilled circle for P4 (normal priority)
            color = 'OVERLAY0'

        print(f'{task_id}|{icon}|{color}|{content}||{project_id}')

except Exception as e:
    print(f'error|○|OVERLAY0|Error parsing tasks||', file=sys.stderr)
    sys.exit(1)
")

if [[ $? -ne 0 ]]; then
    log "ERROR" "Failed to parse tasks JSON"
    echo "SYNC_STATUS=failed" > "$TASKS_CACHE"
    exit 1
fi

# Write to cache
{
    echo "SYNC_STATUS=success"
    echo "TASKS_START"
    echo "$TASKS"
} > "$TASKS_CACHE"

log "INFO" "Successfully cached tasks"

# Trigger Sketchybar update
sketchybar --trigger todoist_synced

exit 0
