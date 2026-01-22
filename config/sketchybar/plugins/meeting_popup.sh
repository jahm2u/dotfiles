#!/usr/bin/env bash

# Meeting Widget Popup - Shows agenda with previous and next meetings
# Usage: Called when meeting widget is clicked
# Shows: Previous meetings (newest at bottom), divider, Next meetings
#
# Uses pre-created slots defined in sketchybarrc:
# - meeting.popup.prev_1 through prev_N (past meetings)
# - meeting.popup.divider
# - meeting.popup.next_1 through next_N (future meetings)
# - meeting.popup.action_notes (optional action button)

# Load shared helpers (MAX_MEETING_SLOTS, parse_event_timestamp, etc.)
source "$HOME/.config/sketchybar/helpers/meeting-helpers.sh"

# Load environment colors
source "$HOME/.config/sketchybar/helpers/source-colors.sh"

EVENTS_LIST_CACHE="$MEETING_CACHE_DIR/meeting_events_list"

# Verify pre-created slots exist before proceeding
if ! verify_meeting_popup_slots; then
    exit 1
fi

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

# Function to format meeting display
format_meeting_display() {
    local title="$1"
    local time="$2"

    # Truncate title if too long
    if [[ ${#title} -gt 35 ]]; then
        title="${title:0:32}..."
    fi

    # Format: "09:30 AM - Meeting Title"
    echo "$time - $title"
}

# Hide all slots - used both for initialization and cleanup
hide_all_slots() {
    for i in $(seq 1 $MAX_MEETING_SLOTS); do
        sketchybar --set "meeting.popup.prev_$i" drawing=off \
                   --set "meeting.popup.next_$i" drawing=off
    done
    sketchybar --set "meeting.popup.divider" drawing=off \
               --set "meeting.popup.action_notes" drawing=off
}

# Get current timestamp and today's date
CURRENT_TIMESTAMP=$(date "+%s")
TODAY=$(date "+%Y-%m-%d")

# Check if we have cached events - show feedback if not
if [[ ! -f "$EVENTS_LIST_CACHE" ]]; then
    hide_all_slots
    # Show user feedback instead of silently closing
    sketchybar --set "meeting.popup.next_1" \
        label="Calendar not synced" \
        label.color="$OVERLAY1" \
        icon="󰀨" \
        icon.color="$RED" \
        icon.padding_right=8 \
        click_script="" \
        drawing=on
    exit 0
fi

EVENTS=$(sed '1,/^EVENTS_START$/d' "$EVENTS_LIST_CACHE")

# Split today's meetings into PAST and FUTURE arrays
PAST_MEETINGS=()
FUTURE_MEETINGS=()

while IFS= read -r event; do
    [[ -z "$event" ]] && continue

    # Parse format: "Meeting Title|09:00 AM|2025-10-29|Attendees"
    EVENT_TIME=$(echo "$event" | cut -d'|' -f2)
    EVENT_DATE=$(echo "$event" | cut -d'|' -f3)

    # Only include TODAY's meetings
    if [[ "$EVENT_DATE" != "$TODAY" ]]; then
        continue
    fi

    # Calculate event timestamp using shared helper
    EVENT_TIMESTAMP=$(parse_event_timestamp "$EVENT_DATE" "$EVENT_TIME")

    # Categorize as past or future
    if [[ -n "$EVENT_TIMESTAMP" ]] && [[ $EVENT_TIMESTAMP -lt $CURRENT_TIMESTAMP ]]; then
        PAST_MEETINGS+=("$event")
    else
        FUTURE_MEETINGS+=("$event")
    fi
done <<< "$EVENTS"

# Hide all slots initially
hide_all_slots

PAST_COUNT=${#PAST_MEETINGS[@]}
FUTURE_COUNT=${#FUTURE_MEETINGS[@]}

# Populate PAST meetings into prev_N → prev_1 (newest closest to divider)
# We fill from the end: if we have 3 past meetings, fill prev_3, prev_2, prev_1
# Take last N past meetings (most recent)
START_IDX=$((PAST_COUNT > MAX_MEETING_SLOTS ? PAST_COUNT - MAX_MEETING_SLOTS : 0))
PAST_DISPLAY_COUNT=$((PAST_COUNT > MAX_MEETING_SLOTS ? MAX_MEETING_SLOTS : PAST_COUNT))

for ((i=0; i<PAST_DISPLAY_COUNT; i++)); do
    MEETING="${PAST_MEETINGS[$((START_IDX + i))]}"
    TITLE=$(echo "$MEETING" | cut -d'|' -f1)
    TIME=$(echo "$MEETING" | cut -d'|' -f2)

    LABEL=$(format_meeting_display "$TITLE" "$TIME")

    # Slot index: if we have 3 meetings, use prev_3, prev_2, prev_1
    # Meeting 0 (oldest displayed) → prev_N, Meeting N-1 (newest) → prev_1
    SLOT_IDX=$((PAST_DISPLAY_COUNT - i))
    SLOT_NAME="meeting.popup.prev_$SLOT_IDX"

    # Cache meeting data atomically for click handler
    write_meeting_cache "prev_$SLOT_IDX" "$MEETING"

    sketchybar --set "$SLOT_NAME" \
        label="$LABEL" \
        label.color="$OVERLAY1" \
        icon="󰠮 󰄲" \
        icon.color="$OVERLAY1" \
        icon.padding_right=8 \
        click_script="$HOME/.config/sketchybar/plugins/meeting-prep-item.sh prev_$SLOT_IDX '$SLOT_NAME'" \
        drawing=on
done

# Show divider if we have BOTH past and future meetings
if [[ $PAST_COUNT -gt 0 ]] && [[ $FUTURE_COUNT -gt 0 ]]; then
    sketchybar --set "meeting.popup.divider" \
        label="────────────────" \
        label.color="$OVERLAY0" \
        icon="" \
        drawing=on
fi

# Populate FUTURE meetings into next_1 → next_N
# Take first N future meetings
FUTURE_DISPLAY_COUNT=$((FUTURE_COUNT > MAX_MEETING_SLOTS ? MAX_MEETING_SLOTS : FUTURE_COUNT))

for ((i=0; i<FUTURE_DISPLAY_COUNT; i++)); do
    MEETING="${FUTURE_MEETINGS[$i]}"
    TITLE=$(echo "$MEETING" | cut -d'|' -f1)
    TIME=$(echo "$MEETING" | cut -d'|' -f2)

    LABEL=$(format_meeting_display "$TITLE" "$TIME")

    SLOT_IDX=$((i + 1))
    SLOT_NAME="meeting.popup.next_$SLOT_IDX"

    # Cache meeting data atomically for click handler
    write_meeting_cache "next_$SLOT_IDX" "$MEETING"

    # First future meeting: yellow highlight, others: blue
    if [[ $i -eq 0 ]]; then
        ICON_COLOR="$YELLOW"
    else
        ICON_COLOR="$BLUE"
    fi

    sketchybar --set "$SLOT_NAME" \
        label="$LABEL" \
        label.color="$LABEL_COLOR" \
        icon="󰠮 󰃭" \
        icon.color="$ICON_COLOR" \
        icon.padding_right=8 \
        click_script="$HOME/.config/sketchybar/plugins/meeting-prep-item.sh next_$SLOT_IDX '$SLOT_NAME'" \
        drawing=on
done

# If no meetings at all, show "No meetings today" in next_1
if [[ $PAST_COUNT -eq 0 ]] && [[ $FUTURE_COUNT -eq 0 ]]; then
    sketchybar --set "meeting.popup.next_1" \
        label="No meetings today" \
        label.color="$OVERLAY1" \
        icon="󰃭" \
        icon.color="$OVERLAY1" \
        icon.padding_right=8 \
        click_script="" \
        drawing=on
fi

# Popup already shown at the start - no need to toggle again
