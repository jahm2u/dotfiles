#!/usr/bin/env bash

# Todoist Widget Popup - Shows top 25 priority tasks with colored priority circles
# Usage: Called when todoist widget is clicked
# Shows: Top 25 tasks with priority circles (P1=red, P2=orange, P3=blue, P4=unfilled)

# Check if popup is already open
POPUP_STATE=$(sketchybar --query todoist | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('popup', {}).get('drawing', 'off'))")

# If already open, just close it and exit
if [[ "$POPUP_STATE" == "on" ]]; then
    sketchybar --set todoist popup.drawing=off
    exit 0
fi

# Close all other popups and show this one immediately
sketchybar --set meeting popup.drawing=off \
           --set cpu popup.drawing=off \
           --set memory popup.drawing=off \
           --set week_num popup.drawing=off \
           --set todoist popup.drawing=on

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

# Read tasks from cache (precached by LaunchAgent every 5 minutes)
if [[ ! -f "$CACHE_DIR/todoist_tasks_cache" ]]; then
    # Trigger immediate sync and show loading state
    ~/.config/sketchybar/helpers/todoist-precache.sh &
    # Show one task item with loading message
    sketchybar --set "todoist.popup.task_1" \
        label="Refreshing tasks..." \
        icon="󰦖" \
        drawing=on \
        --set "todoist.popup.action_1" drawing=off
    # Hide other slots (now 25 total)
    for i in {2..25}; do
        sketchybar --set "todoist.popup.task_$i" drawing=off \
                   --set "todoist.popup.action_$i" drawing=off
    done
    exit 0
fi

# Read from cache
SYNC_STATUS=$(grep "^SYNC_STATUS=" "$CACHE_DIR/todoist_tasks_cache" | cut -d= -f2)
TASKS=$(sed '1,/^TASKS_START$/d' "$CACHE_DIR/todoist_tasks_cache")

if [[ "$SYNC_STATUS" == "failed" ]]; then
    sketchybar --set "todoist.popup.task_1" \
        label="Sync failed - click to retry" \
        icon="󰀨" \
        click_script="~/.config/sketchybar/helpers/todoist-precache.sh && sketchybar --set todoist popup.drawing=off && sketchybar --set todoist popup.drawing=on" \
        drawing=on \
        --set "todoist.popup.action_1" drawing=off
    # Hide other slots (now 25 total)
    for i in {2..25}; do
        sketchybar --set "todoist.popup.task_$i" drawing=off \
                   --set "todoist.popup.action_$i" drawing=off
    done
    exit 0
fi

if [[ -z "$TASKS" ]]; then
    sketchybar --set todoist.popup drawing=off
    exit 0
fi

# Create cache directory if needed
mkdir -p "$CACHE_DIR"

# Map color names to hex values (Catppuccin Macchiato theme)
declare -A COLORS
COLORS[RED]="0xffed8796"
COLORS[PEACH]="0xfff5a97f"
COLORS[BLUE]="0xff8aadf4"
COLORS[OVERLAY0]="0xff6e738d"

# Populate popup items
TASK_INDEX=1
while IFS='|' read -r TASK_ID ICON COLOR CONTENT URL PROJECT_ID; do
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
            # Highlight working task with yellow background
            TASK_BG="$YELLOW"
            TASK_LABEL_COLOR="$BLACK"
            TASK_ICON_COLOR="$BLACK"
        else
            TASK_BG="$TRANSPARENT"
            TASK_LABEL_COLOR="$LABEL_COLOR"
            # Use priority color for icon
            TASK_ICON_COLOR="${COLORS[$COLOR]}"
        fi

        # Optimized close timing: Hide popup FIRST, then update in background
        sketchybar --set "$item_name" \
            label="${CONTENT}" \
            label.color="$TASK_LABEL_COLOR" \
            icon="$ICON" \
            icon.color="$TASK_ICON_COLOR" \
            background.color="$TASK_BG" \
            click_script="sketchybar --set todoist popup.drawing=off && echo '$TASK_ID' > '$WORKING_TASK_FILE' && sketchybar --trigger todoist_focus_changed" \
            drawing=on

        # Action button removed - no external link buttons
        sketchybar --set "$action_name" drawing=off
    fi

    TASK_INDEX=$((TASK_INDEX + 1))
done <<< "$TASKS"

# Hide unused task slots (up to 25 total)
while [[ $TASK_INDEX -le 25 ]]; do
    sketchybar --set "todoist.popup.task_${TASK_INDEX}" drawing=off \
               --set "todoist.popup.action_${TASK_INDEX}" drawing=off
    TASK_INDEX=$((TASK_INDEX + 1))
done

# Popup already shown at the start - no need to toggle again
