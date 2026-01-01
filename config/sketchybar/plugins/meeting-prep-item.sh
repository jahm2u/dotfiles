#!/bin/bash
#
# Meeting Prep Item Click Handler
# Triggers Jonas API prep for clicked meeting
#

MEETING_INDEX="$1"
ITEM_NAME="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPERS_DIR="${SCRIPT_DIR}/../helpers"
CACHE_DIR="$HOME/.cache/sketchybar"
MEETING_CACHE="$CACHE_DIR/meeting_click_${MEETING_INDEX}"

update_status() {
    sketchybar --set "$ITEM_NAME" icon="$1" label="$2"
}

# Read meeting info from cache
if [[ ! -f "$MEETING_CACHE" ]]; then
    update_status "❌" "Meeting not found"
    sleep 2
    exit 1
fi

MEETING_DATA=$(cat "$MEETING_CACHE")
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
