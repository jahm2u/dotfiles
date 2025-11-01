#!/usr/bin/env bash

# Meeting Widget Popup - Shows agenda with previous and next meetings
# Usage: Called when meeting widget is clicked
# Shows: Previous 5 meetings, Next 5 meetings, disabled "Open Notes" button

# Check if popup is already open
POPUP_STATE=$(sketchybar --query meeting | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('popup', {}).get('drawing', 'off'))")

# If already open, just close it and exit
if [[ "$POPUP_STATE" == "on" ]]; then
    sketchybar --set meeting popup.drawing=off
    exit 0
fi

# Close all other popups and show this one immediately
sketchybar --set todoist popup.drawing=off \
           --set cpu popup.drawing=off \
           --set memory popup.drawing=off \
           --set week_num popup.drawing=off \
           --set meeting popup.drawing=on

CACHE_DIR="$HOME/.cache/sketchybar"
EVENTS_LIST_CACHE="$CACHE_DIR/meeting_events_list"

# Load environment colors
source "$HOME/.config/sketchybar/helpers/source-colors.sh"

# Popup item count (5 previous + divider + 5 next + action button)
POPUP_ITEMS=("prev_5" "prev_4" "prev_3" "prev_2" "prev_1" "divider" "next_1" "next_2" "next_3" "next_4" "next_5" "action_notes")

# Function to format meeting display
format_meeting_display() {
    local title="$1"
    local time="$2"
    local date="$3"
    local is_past="$4"

    # Truncate title if too long
    if [[ ${#title} -gt 35 ]]; then
        title="${title:0:32}..."
    fi

    # Format: "09:30 AM - Meeting Title"
    echo "$time - $title"
}

# Get current timestamp and today's date
CURRENT_TIMESTAMP=$(date "+%s")
TODAY=$(date "+%Y-%m-%d")

# Read cached event list
if [[ ! -f "$EVENTS_LIST_CACHE" ]]; then
    sketchybar --set meeting.popup drawing=off
    exit 0
fi

EVENTS=$(sed '1,/^EVENTS_START$/d' "$EVENTS_LIST_CACHE")

# Separate into past and future meetings (TODAY ONLY - never show tomorrow/yesterday)
PAST_MEETINGS=()
FUTURE_MEETINGS=()

while IFS= read -r event; do
    [[ -z "$event" ]] && continue

    # Parse format: "Meeting Title|09:00 AM|2025-10-29"
    EVENT_TIME=$(echo "$event" | cut -d'|' -f2)
    EVENT_DATE=$(echo "$event" | cut -d'|' -f3)

    # CRITICAL: Only show TODAY's meetings (filter out tomorrow/yesterday)
    if [[ "$EVENT_DATE" != "$TODAY" ]]; then
        continue
    fi

    # Calculate event timestamp
    EVENT_TIMESTAMP=$(date -j -f "%Y-%m-%d %I:%M %p" "$EVENT_DATE $EVENT_TIME" "+%s" 2>/dev/null)
    if [[ -z "$EVENT_TIMESTAMP" ]]; then
        EVENT_TIMESTAMP=$(date -j -f "%Y-%m-%d %H:%M" "$EVENT_DATE $EVENT_TIME" "+%s" 2>/dev/null)
    fi

    if [[ -n "$EVENT_TIMESTAMP" ]]; then
        if [[ $EVENT_TIMESTAMP -lt $CURRENT_TIMESTAMP ]]; then
            PAST_MEETINGS+=("$event")
        else
            FUTURE_MEETINGS+=("$event")
        fi
    fi
done <<< "$EVENTS"

# Get last 5 past meetings (reversed order, most recent first)
PAST_COUNT=${#PAST_MEETINGS[@]}
DISPLAY_PAST=()
for ((i=PAST_COUNT-1; i>=PAST_COUNT-5 && i>=0; i--)); do
    DISPLAY_PAST+=("${PAST_MEETINGS[$i]}")
done

# Get next 5 future meetings
DISPLAY_FUTURE=("${FUTURE_MEETINGS[@]:0:5}")

# Populate popup items
# Previous meetings (grayed out)
for i in {0..4}; do
    item_name="meeting.popup.prev_$((5-i))"
    note_name="meeting.popup.prev_$((5-i))_note"

    if [[ $i -lt ${#DISPLAY_PAST[@]} ]]; then
        MEETING="${DISPLAY_PAST[$i]}"
        TITLE=$(echo "$MEETING" | cut -d'|' -f1)
        TIME=$(echo "$MEETING" | cut -d'|' -f2)
        DATE=$(echo "$MEETING" | cut -d'|' -f3)

        LABEL=$(format_meeting_display "$TITLE" "$TIME" "$DATE" "true")

        sketchybar --set "$item_name" \
            label="$LABEL" \
            label.color="$OVERLAY1" \
            icon="󰠮 󰄲" \
            icon.color="$OVERLAY1" \
            icon.padding_right=8 \
            drawing=on \
            --set "$note_name" \
            drawing=off
    else
        sketchybar --set "$item_name" drawing=off \
                   --set "$note_name" drawing=off
    fi
done

# Divider
sketchybar --set meeting.popup.divider \
    label="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" \
    label.color="$BACKGROUND_LESS_TRANSPARENT" \
    icon.drawing=off \
    drawing=on

# Next meetings (highlighted)
for i in {0..4}; do
    item_name="meeting.popup.next_$((i+1))"
    note_name="meeting.popup.next_$((i+1))_note"

    if [[ $i -lt ${#DISPLAY_FUTURE[@]} ]]; then
        MEETING="${DISPLAY_FUTURE[$i]}"
        TITLE=$(echo "$MEETING" | cut -d'|' -f1)
        TIME=$(echo "$MEETING" | cut -d'|' -f2)
        DATE=$(echo "$MEETING" | cut -d'|' -f3)

        LABEL=$(format_meeting_display "$TITLE" "$TIME" "$DATE" "false")

        # Highlight first upcoming meeting
        if [[ $i -eq 0 ]]; then
            ICON_COLOR="$YELLOW"
            LABEL_COLOR_USE="$LABEL_COLOR"
        else
            ICON_COLOR="$BLUE"
            LABEL_COLOR_USE="$LABEL_COLOR"
        fi

        sketchybar --set "$item_name" \
            label="$LABEL" \
            label.color="$LABEL_COLOR_USE" \
            icon="󰠮 󰃭" \
            icon.color="$ICON_COLOR" \
            icon.padding_right=8 \
            drawing=on \
            --set "$note_name" \
            drawing=off
    else
        sketchybar --set "$item_name" drawing=off \
                   --set "$note_name" drawing=off
    fi
done

# Popup already shown at the start - no need to toggle again
