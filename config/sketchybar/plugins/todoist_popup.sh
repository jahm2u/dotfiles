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

# Close all other popups (but don't show todoist popup yet)
sketchybar --set meeting popup.drawing=off \
           --set cpu popup.drawing=off \
           --set memory popup.drawing=off \
           --set week_num popup.drawing=off

CACHE_DIR="$HOME/.cache/sketchybar"
WORKING_TASK_FILE="$CACHE_DIR/todoist_working_task"
COMPLETED_TASKS_FILE="$CACHE_DIR/todoist_completed_tasks_session"

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

        # Check if task was completed in this session
        IS_COMPLETED=false
        if [[ -f "$COMPLETED_TASKS_FILE" ]] && grep -q "^${TASK_ID}$" "$COMPLETED_TASKS_FILE"; then
            IS_COMPLETED=true
        fi

        # Set visual appearance based on state
        if [[ "$IS_COMPLETED" == true ]]; then
            # Completed: grey strikethrough text, filled circle
            TASK_BG="$TRANSPARENT"
            TASK_LABEL_COLOR="0xff6e738d"  # Grey
            TASK_ICON="●"  # Filled circle
            TASK_ICON_COLOR="0xff6e738d"  # Grey
            LABEL_DISPLAY="$(echo "$CONTENT" | sed 's/./&̶/g')"  # Strikethrough (combining character)
            COMPLETION_STATE="completed"
        elif [[ "$TASK_ID" == "$WORKING_TASK_ID" ]]; then
            # Highlight working task with yellow background
            TASK_BG="$YELLOW"
            TASK_LABEL_COLOR="$BLACK"
            TASK_ICON="$ICON"
            TASK_ICON_COLOR="$BLACK"
            LABEL_DISPLAY="$CONTENT"
            COMPLETION_STATE="active"
        else
            # Normal active task
            TASK_BG="$TRANSPARENT"
            TASK_LABEL_COLOR="$LABEL_COLOR"
            TASK_ICON="$ICON"
            TASK_ICON_COLOR="${COLORS[$COLOR]}"
            LABEL_DISPLAY="$CONTENT"
            COMPLETION_STATE="active"
        fi

        # Task label - clickable to set as working task
        sketchybar --set "$item_name" \
            label="${LABEL_DISPLAY}" \
            label.color="$TASK_LABEL_COLOR" \
            icon.drawing=off \
            background.color="$TASK_BG" \
            click_script="echo '$TASK_ID' > '$WORKING_TASK_FILE' && sketchybar --trigger todoist_focus_changed && sketchybar --set todoist popup.drawing=off" \
            drawing=on

        # Action button repurposed as completion checkbox - clickable icon
        sketchybar --set "$action_name" \
            label="$TASK_ICON" \
            label.color="$TASK_ICON_COLOR" \
            label.font="$FONT_FACE:Regular:14.0" \
            label.padding_left=10 \
            label.padding_right=5 \
            icon.drawing=off \
            background.color="$TRANSPARENT" \
            click_script="~/.config/sketchybar/helpers/todoist-toggle-complete.sh '$TASK_ID' '$COMPLETION_STATE' && sleep 0.3 && ~/.config/sketchybar/plugins/todoist_popup.sh" \
            drawing=on
    fi

    TASK_INDEX=$((TASK_INDEX + 1))
done <<< "$TASKS"

# Hide unused task slots (up to 25 total)
while [[ $TASK_INDEX -le 25 ]]; do
    sketchybar --set "todoist.popup.task_${TASK_INDEX}" drawing=off \
               --set "todoist.popup.action_${TASK_INDEX}" drawing=off
    TASK_INDEX=$((TASK_INDEX + 1))
done

# Now show popup with all items correctly configured
sketchybar --set todoist popup.drawing=on
