#!/bin/bash
#
# Meeting Prep Item Click Handler
# Triggers prep workflow for a specific meeting clicked in the popup
#

MEETING_INDEX="$1"  # Can be "1", "2", etc. OR "prev_1", "prev_2", etc.
ITEM_NAME="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPERS_DIR="${SCRIPT_DIR}/../helpers"
CACHE_DIR="$HOME/.cache/sketchybar"
MEETING_CACHE="$CACHE_DIR/meeting_click_${MEETING_INDEX}"

# Update item with status
update_status() {
    local icon="$1"
    local label="$2"
    sketchybar --set "$ITEM_NAME" icon="$icon" label="$label"
}

# Read meeting info from cache
if [[ ! -f "$MEETING_CACHE" ]]; then
    update_status "❌" "Meeting info not found"
    sleep 2
    exit 1
fi

MEETING_DATA=$(cat "$MEETING_CACHE")
MEETING_TITLE=$(echo "$MEETING_DATA" | cut -d'|' -f1)
MEETING_TIME=$(echo "$MEETING_DATA" | cut -d'|' -f2)
MEETING_DATE=$(echo "$MEETING_DATA" | cut -d'|' -f3)
MEETING_PARTICIPANTS=$(echo "$MEETING_DATA" | cut -d'|' -f4)

# Export for meeting-prep.sh to use
export PREP_MEETING_TITLE="$MEETING_TITLE"
export PREP_MEETING_TIME="$MEETING_TIME"
export PREP_MEETING_DATE="$MEETING_DATE"
export PREP_MEETING_PARTICIPANTS="$MEETING_PARTICIPANTS"

# Main workflow in background
run_workflow() {
    # Step 1: Classifying
    update_status "🔍" "Classifying..."
    sleep 0.5

    # Step 2: Finding person
    update_status "👤" "Finding person..."
    sleep 0.5

    # Step 3: Analyzing history
    update_status "🧠" "Analyzing history..."
    sleep 0.5

    # Step 4: Generating note
    update_status "✍️" "Generating note..."
    sleep 0.5

    # Run the actual workflow
    if "$HELPERS_DIR/meeting-prep.sh" >> ~/.config/sketchybar/logs/meeting-prep.log 2>&1; then
        update_status "✅" "Note ready!"
        sleep 2
        # Close popup after success
        sketchybar --set meeting popup.drawing=off
    else
        update_status "❌" "Failed - check logs"
        sleep 3
    fi

    # Restore original display
    sketchybar --trigger refresh_meeting_popup
}

# Instant feedback
update_status "⏳" "Starting..."

# Run workflow in background
run_workflow &

# Exit immediately so popup stays responsive
exit 0
