#!/bin/bash
# Complete task with 5 second countdown and undo option
# Shows undo arrow and strikethrough during countdown

CACHE_DIR="$HOME/.cache/sketchybar"
CURRENT_TASK_FILE="$CACHE_DIR/todoist_current_task"
PENDING_COMPLETE_FILE="$CACHE_DIR/todoist_pending_complete"
TASKS_CACHE="$CACHE_DIR/todoist_tasks_cache"

# Get the currently displayed task
if [[ ! -f "$CURRENT_TASK_FILE" ]]; then
    echo "No current task"
    exit 0
fi

TASK_ID=$(cat "$CURRENT_TASK_FILE")

if [[ -z "$TASK_ID" ]]; then
    echo "Current task file is empty"
    exit 0
fi

# Check if already in countdown
if [[ -f "$PENDING_COMPLETE_FILE" ]]; then
    PENDING_ID=$(head -n 1 "$PENDING_COMPLETE_FILE")
    if [[ "$PENDING_ID" == "$TASK_ID" ]]; then
        # UNDO - cancel the completion
        rm -f "$PENDING_COMPLETE_FILE"
        echo "Completion cancelled"

        # Get original task content
        TASKS_CACHE="$CACHE_DIR/todoist_tasks_cache"
        TASKS_DATA=$(sed '1,/^TASKS_START$/d' "$TASKS_CACHE")
        TASK_LINE=$(grep "^${TASK_ID}|" <<< "$TASKS_DATA" | head -n 1)
        IFS='|' read -r _ _ _ CONTENT _ _ <<< "$TASK_LINE"

        # INSTANT visual revert - uncheck and remove strikethrough immediately
        # Truncate if too long
        if [[ ${#CONTENT} -gt 40 ]]; then
            CONTENT="${CONTENT:0:37}..."
        fi
        sketchybar --set todoist icon="󰄱" \
                   --set todoist.name label="$CONTENT"

        exit 0
    fi
fi

# Get countdown duration from .env (default 15 seconds)
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

COUNTDOWN_SECONDS="${TODOIST_COUNTDOWN_SECONDS:-15}"

# Get current task content for immediate visual update
TASKS_CACHE="$CACHE_DIR/todoist_tasks_cache"
TASKS_DATA=$(sed '1,/^TASKS_START$/d' "$TASKS_CACHE")
TASK_LINE=$(grep "^${TASK_ID}|" <<< "$TASKS_DATA" | head -n 1)
IFS='|' read -r _ _ _ CONTENT _ _ <<< "$TASK_LINE"

# INSTANT visual feedback - update UI immediately (no delay)
STRIKETHROUGH_TEXT="$(echo "$CONTENT" | sed 's/./&̶/g')"
# Truncate if too long
if [[ ${#STRIKETHROUGH_TEXT} -gt 40 ]]; then
    STRIKETHROUGH_TEXT="${STRIKETHROUGH_TEXT:0:37}..."
fi
sketchybar --set todoist icon="󰄵" \
           --set todoist.name label="$STRIKETHROUGH_TEXT"

# Mark as pending in background
echo "$TASK_ID" > "$PENDING_COMPLETE_FILE"
echo "$(date +%s)" >> "$PENDING_COMPLETE_FILE"

# Wait for configured seconds in background, then complete
(
    sleep "$COUNTDOWN_SECONDS"

    # Check if still pending (not cancelled)
    if [[ -f "$PENDING_COMPLETE_FILE" ]] && grep -q "^${TASK_ID}$" "$PENDING_COMPLETE_FILE"; then
        # Complete the task via API
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

        if [[ -n "$TODOIST_API_TOKEN" ]]; then
            HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null -X POST \
                "https://api.todoist.com/api/v1/tasks/${TASK_ID}/close" \
                -H "Authorization: Bearer $TODOIST_API_TOKEN")

            if [[ "$HTTP_CODE" == "204" ]] || [[ "$HTTP_CODE" == "200" ]]; then
                echo "Task $TASK_ID marked as complete"

                # Clean up
                rm -f "$PENDING_COMPLETE_FILE"

                # Pick random new task
                ~/.config/sketchybar/plugins/todoist-pick-random.sh &

                # Trigger precache refresh
                ~/.config/sketchybar/helpers/todoist-precache.sh &
            else
                echo "Error: API returned $HTTP_CODE"
                rm -f "$PENDING_COMPLETE_FILE"

                # Revert visual state - uncheck and remove strikethrough
                ~/.config/sketchybar/plugins/todoist.sh &
            fi
        fi
    fi
) &

exit 0
