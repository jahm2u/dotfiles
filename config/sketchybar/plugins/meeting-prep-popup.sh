#!/bin/bash
#
# Meeting Prep Popup Handler
# Provides instant feedback in the popup and kicks off the workflow
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPERS_DIR="${SCRIPT_DIR}/../helpers"
ITEM_NAME="meeting.popup.action_prep"

# Update popup item with status
update_status() {
    local icon="$1"
    local label="$2"
    sketchybar --set "$ITEM_NAME" icon="$icon" label="$label"
}

# Main workflow in background
run_workflow() {
    # Step 1: Classifying
    update_status "🔍" "Classifying meeting..."
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
    else
        update_status "❌" "Failed - check logs"
        sleep 3
    fi

    # Reset to default
    update_status "🤖" "Prep Meeting"
}

# Instant feedback
update_status "⏳" "Starting..."

# Run workflow in background
run_workflow &

# Exit immediately so popup stays responsive
exit 0
