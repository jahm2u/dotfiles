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

# Get ALL meetings for today (chronologically ordered)
ALL_MEETINGS=()

while IFS= read -r event; do
    [[ -z "$event" ]] && continue

    # Parse format: "Meeting Title|09:00 AM|2025-10-29|Attendees"
    EVENT_TIME=$(echo "$event" | cut -d'|' -f2)
    EVENT_DATE=$(echo "$event" | cut -d'|' -f3)

    # CRITICAL: Only show TODAY's meetings (filter out tomorrow/yesterday)
    if [[ "$EVENT_DATE" != "$TODAY" ]]; then
        continue
    fi

    # Add to all meetings array (already in chronological order from khal)
    ALL_MEETINGS+=("$event")
done <<< "$EVENTS"

TOTAL_MEETINGS=${#ALL_MEETINGS[@]}

# Remove old hardcoded items if they exist
for i in {1..5}; do
    sketchybar --remove meeting.popup.prev_$i 2>/dev/null
    sketchybar --remove meeting.popup.next_$i 2>/dev/null
done
sketchybar --remove meeting.popup.divider 2>/dev/null

# Create items dynamically for ALL meetings
FIRST_FUTURE_INDEX=-1
for i in "${!ALL_MEETINGS[@]}"; do
    MEETING="${ALL_MEETINGS[$i]}"
    TITLE=$(echo "$MEETING" | cut -d'|' -f1)
    TIME=$(echo "$MEETING" | cut -d'|' -f2)
    DATE=$(echo "$MEETING" | cut -d'|' -f3)

    # Calculate if meeting is past or future
    EVENT_TIMESTAMP=$(date -j -f "%Y-%m-%d %I:%M %p" "$DATE $TIME" "+%s" 2>/dev/null)
    if [[ -z "$EVENT_TIMESTAMP" ]]; then
        EVENT_TIMESTAMP=$(date -j -f "%Y-%m-%d %H:%M" "$DATE $TIME" "+%s" 2>/dev/null)
    fi

    IS_PAST=false
    if [[ -n "$EVENT_TIMESTAMP" ]] && [[ $EVENT_TIMESTAMP -lt $CURRENT_TIMESTAMP ]]; then
        IS_PAST=true
    else
        if [[ $FIRST_FUTURE_INDEX -eq -1 ]]; then
            FIRST_FUTURE_INDEX=$i
        fi
    fi

    LABEL=$(format_meeting_display "$TITLE" "$TIME" "$DATE" "$IS_PAST")

    # Determine colors based on past/future
    if [[ "$IS_PAST" == "true" ]]; then
        ICON_COLOR="$OVERLAY1"
        LABEL_COLOR_USE="$OVERLAY1"
        ICON="󰠮 󰄲"
    else
        # Highlight first upcoming meeting
        if [[ $i -eq $FIRST_FUTURE_INDEX ]]; then
            ICON_COLOR="$YELLOW"
            LABEL_COLOR_USE="$LABEL_COLOR"
        else
            ICON_COLOR="$BLUE"
            LABEL_COLOR_USE="$LABEL_COLOR"
        fi
        ICON="󰠮 󰃭"
    fi

    # Cache meeting info for click handler
    MEETING_CACHE="$CACHE_DIR/meeting_click_$i"
    echo "$MEETING" > "$MEETING_CACHE"

    # Create popup item
    item_name="meeting.popup.item_$i"
    sketchybar --add item "$item_name" popup.meeting \
               --set "$item_name" \
               label="$LABEL" \
               label.color="$LABEL_COLOR_USE" \
               icon="$ICON" \
               icon.color="$ICON_COLOR" \
               icon.padding_right=8 \
               click_script="$HOME/.config/sketchybar/plugins/meeting-prep-item.sh $i '$item_name'" \
               drawing=on
done

# Popup already shown at the start - no need to toggle again
