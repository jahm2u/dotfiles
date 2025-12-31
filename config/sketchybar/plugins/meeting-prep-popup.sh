#!/bin/bash
# Meeting Prep Popup Handler - Jonas API Version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPERS_DIR="${SCRIPT_DIR}/../helpers"
ITEM_NAME="meeting.popup.action_prep"

update_status() {
    sketchybar --set "$ITEM_NAME" icon="$1" label="$2"
}

run_workflow() {
    update_status "🧠" "Jonas is preparing..."

    # Run the actual workflow (15-90 seconds)
    if "$HELPERS_DIR/meeting-prep.sh" >> ~/.config/sketchybar/logs/meeting-prep.log 2>&1; then
        update_status "✅" "Note ready!"
        sleep 2
    else
        update_status "❌" "Failed - check logs"
        sleep 3
    fi

    update_status "🤖" "Prep Meeting"
}

update_status "⏳" "Starting..."
run_workflow &
exit 0
