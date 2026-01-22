#!/bin/bash
#
# Shared helper functions for meeting widget scripts
# Source this from meeting.sh and meeting_popup.sh
#

# Configuration constants
MAX_MEETING_SLOTS=5

# Cache directory (ensure it exists)
MEETING_CACHE_DIR="$HOME/.cache/sketchybar"
mkdir -p "$MEETING_CACHE_DIR"

# Parse event timestamp from date and time strings
# Handles both 12-hour (09:00 AM) and 24-hour (09:00) formats
# Usage: parse_event_timestamp "2025-01-21" "09:00 AM"
# Returns: Unix timestamp or empty string on failure
parse_event_timestamp() {
    local event_date="$1"
    local event_time="$2"
    local timestamp=""

    # Try 12-hour format first (e.g., "09:00 AM")
    timestamp=$(date -j -f "%Y-%m-%d %I:%M %p" "$event_date $event_time" "+%s" 2>/dev/null)

    # Fall back to 24-hour format (e.g., "09:00")
    if [[ -z "$timestamp" ]]; then
        timestamp=$(date -j -f "%Y-%m-%d %H:%M" "$event_date $event_time" "+%s" 2>/dev/null)
    fi

    echo "$timestamp"
}

# Verify that pre-created popup slots exist in sketchybar
# Returns 0 if all slots exist, 1 otherwise
verify_meeting_popup_slots() {
    # Check one slot from each group - if these exist, all should exist
    if ! sketchybar --query "meeting.popup.prev_1" &>/dev/null; then
        echo "ERROR: Pre-created slot meeting.popup.prev_1 not found. Check sketchybarrc." >&2
        return 1
    fi
    if ! sketchybar --query "meeting.popup.next_1" &>/dev/null; then
        echo "ERROR: Pre-created slot meeting.popup.next_1 not found. Check sketchybarrc." >&2
        return 1
    fi
    if ! sketchybar --query "meeting.popup.divider" &>/dev/null; then
        echo "ERROR: Pre-created slot meeting.popup.divider not found. Check sketchybarrc." >&2
        return 1
    fi
    return 0
}

# Write meeting cache atomically to prevent race conditions
# Usage: write_meeting_cache "slot_id" "meeting_data"
write_meeting_cache() {
    local slot_id="$1"
    local meeting_data="$2"
    local cache_file="$MEETING_CACHE_DIR/meeting_click_${slot_id}"
    local temp_file="${cache_file}.tmp.$$"

    # Write to temp file first, then atomic rename
    echo "$meeting_data" > "$temp_file"
    mv -f "$temp_file" "$cache_file"
}

# Read meeting cache safely
# Usage: read_meeting_cache "slot_id"
# Returns: meeting data or empty string if not found
read_meeting_cache() {
    local slot_id="$1"
    local cache_file="$MEETING_CACHE_DIR/meeting_click_${slot_id}"

    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
    fi
}

# Clear all meeting click caches
clear_meeting_caches() {
    for i in $(seq 1 $MAX_MEETING_SLOTS); do
        rm -f "$MEETING_CACHE_DIR/meeting_click_prev_$i" 2>/dev/null
        rm -f "$MEETING_CACHE_DIR/meeting_click_next_$i" 2>/dev/null
    done
}
