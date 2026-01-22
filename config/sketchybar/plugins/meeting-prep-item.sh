#!/bin/bash
#
# Meeting Prep Item Click Handler
# Triggers Jonas API prep for clicked meeting
#
# Arguments:
#   $1 - Slot identifier (e.g., "prev_1", "next_2")
#   $2 - Full item name (e.g., "meeting.popup.prev_1")
#

SLOT_ID="$1"
ITEM_NAME="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPERS_DIR="${SCRIPT_DIR}/../helpers"

# Load shared helpers for cache operations
source "$HELPERS_DIR/meeting-helpers.sh"

update_status() {
    sketchybar --set "$ITEM_NAME" icon="$1" label="$2"
}

# Read meeting info from cache using shared helper
MEETING_DATA=$(read_meeting_cache "$SLOT_ID")
if [[ -z "$MEETING_DATA" ]]; then
    update_status "❌" "Meeting not found"
    sleep 2
    exit 1
fi
MEETING_TITLE=$(echo "$MEETING_DATA" | cut -d'|' -f1)
MEETING_TIME=$(echo "$MEETING_DATA" | cut -d'|' -f2)
MEETING_DATE=$(echo "$MEETING_DATA" | cut -d'|' -f3)
MEETING_PARTICIPANTS=$(echo "$MEETING_DATA" | cut -d'|' -f4)

# Export for meeting-prep.sh
export PREP_MEETING_TITLE="$MEETING_TITLE"
export PREP_MEETING_TIME="$MEETING_TIME"
export PREP_MEETING_DATE="$MEETING_DATE"
export PREP_MEETING_PARTICIPANTS="$MEETING_PARTICIPANTS"

run_workflow() {
    update_status "🧠" "Jonas preparing..."

    if "$HELPERS_DIR/meeting-prep.sh" >> ~/.config/sketchybar/logs/meeting-prep.log 2>&1; then
        update_status "✅" "Ready"
        sleep 1
        sketchybar --set meeting popup.drawing=off
    else
        update_status "❌" "Failed"
        sleep 2
    fi

    sketchybar --trigger refresh_meeting_popup
}

update_status "⏳" "Starting..."
run_workflow &
exit 0
