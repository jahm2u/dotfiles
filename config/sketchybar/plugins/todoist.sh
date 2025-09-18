#!/usr/bin/env bash

# Source the .env file to get TODOIST_API_TOKEN
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
fi

if [[ -z "$TODOIST_API_TOKEN" ]]; then
    sketchybar --set "${NAME}.name" label="No Todoist token"
    exit 0
fi

# Fetch tasks from Todoist API
# Get active tasks sorted by priority (4=urgent, 3=high, 2=medium, 1=normal)
RESPONSE=$(curl -s -X GET \
    "https://api.todoist.com/rest/v2/tasks?filter=today%20%7C%20overdue" \
    -H "Authorization: Bearer $TODOIST_API_TOKEN")

if [[ -z "$RESPONSE" ]] || [[ "$RESPONSE" == "[]" ]]; then
    sketchybar --set "${NAME}.name" label="No tasks today"
    exit 0
fi

# Parse the highest priority task
# Todoist priority: 4=p1 (highest), 3=p2, 2=p3, 1=p4 (lowest)
TASK=$(echo "$RESPONSE" | python3 -c "
import sys, json

try:
    tasks = json.load(sys.stdin)
    if not tasks:
        print('No tasks')
        sys.exit(0)
    
    # Sort by priority first (highest first), then by due date
    # Todoist priority: 4=p1 (highest), 3=p2, 2=p3, 1=p4 (lowest)
    # For due dates, we want earlier dates first, so we don't reverse that part
    sorted_tasks = sorted(tasks, key=lambda x: (-x.get('priority', 1), x.get('due', {}).get('date', '9999-12-31')))
    
    # Get the highest priority task
    top_task = sorted_tasks[0]
    content = top_task.get('content', 'No task')
    priority = top_task.get('priority', 1)
    
    # Truncate if too long (fixed width)
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