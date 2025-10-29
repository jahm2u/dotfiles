#!/usr/bin/env bash

# Enhanced meeting script with change detection, auto-sync, and fallback behavior
#
# Sketchybar Environment Variables (provided by Sketchybar when plugin is executed):
#   $NAME - The item name (e.g., "meeting") used for sketchybar --set commands
#   $SENDER - Event that triggered the script (e.g., "calendar_synced", "forced")
#
# Dependencies:
#   - khal: Calendar CLI tool for querying upcoming meetings
#   - Sketchybar event system: Listens for calendar_synced events

CACHE_DIR="$HOME/.cache/sketchybar"
MEETING_CACHE="$CACHE_DIR/meeting_cache"
MEETING_DATA_CACHE="$CACHE_DIR/meeting_data_cache"
CALENDAR_HASH_FILE="$CACHE_DIR/calendar_hash"
SYNC_STATUS_FILE="$CACHE_DIR/last_sync_status"

# Create cache directory if it doesn't exist
mkdir -p "$CACHE_DIR"

# Check last sync status
check_sync_status() {
    [[ ! -f "$SYNC_STATUS_FILE" ]] && echo "unknown" && return

    local exit_code
    exit_code=$(grep "^exit_code=" "$SYNC_STATUS_FILE" 2>/dev/null | cut -d= -f2)

    case "$exit_code" in
        0) echo "success" ;;
        1) echo "partial" ;;
        2) echo "failed" ;;
        *) echo "unknown" ;;
    esac
}

# Get last sync timestamp
get_sync_timestamp() {
    if [[ -f "$SYNC_STATUS_FILE" ]]; then
        grep "^timestamp=" "$SYNC_STATUS_FILE" 2>/dev/null | cut -d= -f2- | cut -d' ' -f2
    else
        echo "never"
    fi
}

# Function to get count of changed calendar files
# Returns the number of .ics files modified since last check
get_calendar_change_count() {
    # Count the actual calendar files that have changed
    find ~/.local/share/khal/calendars -name "*.ics" -newer "$CALENDAR_HASH_FILE" 2>/dev/null | wc -l
}

# Function to force calendar sync
force_calendar_sync() {
    echo "$(date): Forcing calendar sync due to stale data" >> "$CACHE_DIR/sync.log"
    ~/.config/sketchybar/helpers/sync-calendars.sh >/dev/null 2>&1
    touch "$CALENDAR_HASH_FILE"
}

# Check sync status before fetching events
SYNC_STATUS=$(check_sync_status)

# Get next meeting within 7 days (using new format: title|time|date)
# Note: tail -n +2 skips the first line which is khal's date header (e.g., "Today, 2025-10-29")
EVENTS_RAW=$(khal list now 7d --format "{title}|{start-time}|{start-date}" 2>/dev/null | tail -n +2 || echo "")

# Check if we have calendar data, if not, try to sync
if [[ "$EVENTS_RAW" =~ "No calendars" ]] || [[ -z "$EVENTS_RAW" ]]; then
    # Check if calendar files are older than 30 minutes (stale threshold)
    # 30 minutes = 2x the 15-minute LaunchAgent sync interval
    # If we've missed 2 sync cycles, force a manual sync
    if [[ ! -f "$CALENDAR_HASH_FILE" ]] || [[ $(find "$CALENDAR_HASH_FILE" -mmin +30 2>/dev/null) ]]; then
        force_calendar_sync
        # Retry getting events after sync (tail -n +2 skips khal's date header line)
        EVENTS_RAW=$(khal list now 7d --format "{title}|{start-time}|{start-date}" 2>/dev/null | tail -n +2 || echo "")
        # Update sync status after forced sync
        SYNC_STATUS=$(check_sync_status)
    fi
fi

# Filter out spam events
SPAM_PATTERNS=".*(Million-Dollar|Webinar|Free Training|Limited Time|Act Now|Special Offer|How to Avoid|Mistakes When|Don't Miss|Last Chance|Exclusive|Register Now|Save Your Spot)"
EVENTS=$(echo "$EVENTS_RAW" | grep -v -E "$SPAM_PATTERNS")

# Check if meeting data has changed significantly
CURRENT_HASH=$(echo "$EVENTS" | md5)
if [[ -f "$MEETING_CACHE" ]]; then
    CACHED_HASH=$(cat "$MEETING_CACHE" 2>/dev/null || echo "")
else
    CACHED_HASH=""
fi

# Store current hash for future comparison (restrictive permissions)
(umask 077; echo "$CURRENT_HASH" > "$MEETING_CACHE")

# Handle sync failures with fallback display
if [[ "$SYNC_STATUS" == "failed" ]] || [[ "$SYNC_STATUS" == "partial" ]]; then
    SYNC_TIME=$(get_sync_timestamp)
    STALE_ICON="󰁡"  # Clock icon for stale data

    # Try to load cached meeting data
    if [[ -f "$MEETING_DATA_CACHE" ]]; then
        CACHED_LABEL=$(cat "$MEETING_DATA_CACHE" 2>/dev/null)
        if [[ -n "$CACHED_LABEL" ]]; then
            # Show cached data with stale indicator
            sketchybar --set "$NAME" icon="$STALE_ICON" --set "${NAME}.name" label="$CACHED_LABEL (stale)"
        else
            # No cached data, show sync failed message
            sketchybar --set "$NAME" icon="$STALE_ICON" --set "${NAME}.name" label="Sync Failed ($SYNC_TIME)"
        fi
    else
        # No cached data available
        sketchybar --set "$NAME" icon="$STALE_ICON" --set "${NAME}.name" label="Sync Failed ($SYNC_TIME)"
    fi
    exit 0
fi

if [[ "$EVENTS" =~ "No calendars" ]]; then
    # Real calendar access issue
    LABEL="No calendar access"
    sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="$LABEL"
    (umask 077; echo "$LABEL" > "$MEETING_DATA_CACHE")
elif [[ -z "$EVENTS" ]] || [[ "$EVENTS" =~ "No events" ]]; then
    # No upcoming meetings in next 7 days
    LABEL="No meetings"
    sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="$LABEL"
    (umask 077; echo "$LABEL" > "$MEETING_DATA_CACHE")
elif [ -n "$EVENTS" ]; then
    # Filter out past meetings - only show meetings that haven't ended yet
    # Meetings are considered "ended" if they started more than 10 minutes ago
    CURRENT_TIMESTAMP=$(date "+%s")
    FUTURE_EVENTS=""

    while IFS= read -r event; do
        [[ -z "$event" ]] && continue

        # Parse format: "Meeting Title|09:00 AM|2025-10-29"
        EVENT_TIME=$(echo "$event" | cut -d'|' -f2)
        EVENT_DATE=$(echo "$event" | cut -d'|' -f3)

        # Calculate event timestamp
        EVENT_TIMESTAMP=$(date -j -f "%Y-%m-%d %I:%M %p" "$EVENT_DATE $EVENT_TIME" "+%s" 2>/dev/null)
        if [[ -z "$EVENT_TIMESTAMP" ]]; then
            # Fallback: Try 24-hour format for non-US locales
            EVENT_TIMESTAMP=$(date -j -f "%Y-%m-%d %H:%M" "$EVENT_DATE $EVENT_TIME" "+%s" 2>/dev/null)
        fi

        # Include events that are in the future OR started within last 10 minutes
        if [[ -n "$EVENT_TIMESTAMP" ]] && [[ $((CURRENT_TIMESTAMP - EVENT_TIMESTAMP)) -le 600 ]]; then
            if [[ -z "$FUTURE_EVENTS" ]]; then
                FUTURE_EVENTS="$event"
            else
                FUTURE_EVENTS="$FUTURE_EVENTS"$'\n'"$event"
            fi
        fi
    done <<< "$EVENTS"

    # Get the next meeting (first line from filtered future events)
    NEXT_MEETING=$(echo "$FUTURE_EVENTS" | head -n 1)

    if [[ -n "$NEXT_MEETING" ]]; then
        # Parse format: "Meeting Title|09:00 AM|2025-10-29"
        TITLE=$(echo "$NEXT_MEETING" | cut -d'|' -f1)
        TIME=$(echo "$NEXT_MEETING" | cut -d'|' -f2)
        DATE=$(echo "$NEXT_MEETING" | cut -d'|' -f3)

        # Calculate countdown - convert meeting datetime to timestamp
        # Try 12-hour format first (e.g., "09:00 AM"), then fall back to 24-hour format (e.g., "09:00")
        MEETING_TIMESTAMP=$(date -j -f "%Y-%m-%d %I:%M %p" "$DATE $TIME" "+%s" 2>/dev/null)
        if [[ -z "$MEETING_TIMESTAMP" ]]; then
            # Fallback: Try 24-hour format for non-US locales
            MEETING_TIMESTAMP=$(date -j -f "%Y-%m-%d %H:%M" "$DATE $TIME" "+%s" 2>/dev/null)
        fi

        if [[ -n "$MEETING_TIMESTAMP" ]] && [[ "$MEETING_TIMESTAMP" -gt "$CURRENT_TIMESTAMP" ]]; then
            DIFF=$((MEETING_TIMESTAMP - CURRENT_TIMESTAMP))

            # Calculate days, hours, minutes
            DAYS=$((DIFF / 86400))
            REMAINING=$((DIFF % 86400))
            HOURS=$((REMAINING / 3600))
            MINUTES=$(((REMAINING % 3600) / 60))

            # Format countdown based on time remaining
            if [[ $DAYS -gt 0 ]]; then
                # More than 1 day away
                if [[ $DAYS -eq 1 ]]; then
                    TIME_STR="tomorrow"
                else
                    TIME_STR="in ${DAYS}d"
                fi
            elif [[ $HOURS -gt 0 ]]; then
                # Less than 1 day, show hours and minutes
                TIME_STR="${HOURS}h ${MINUTES}m"
            else
                # Less than 1 hour, show minutes only
                TIME_STR="${MINUTES}m"
            fi

            # Icon based on urgency (< 15 minutes)
            if [[ $DIFF -le 900 ]]; then
                ICON="󰁅"  # Urgent
            else
                ICON="󰃭"  # Normal
            fi

            LABEL="$TITLE in $TIME_STR"
            sketchybar --set "$NAME" icon="$ICON" --set "${NAME}.name" label="$LABEL"
            # Cache this successful display
            (umask 077; echo "$LABEL" > "$MEETING_DATA_CACHE")
        elif [[ -n "$MEETING_TIMESTAMP" ]] && [[ $((CURRENT_TIMESTAMP - MEETING_TIMESTAMP)) -le 600 ]]; then
            # Meeting started within last 10 minutes
            STARTED_AGO=$(((CURRENT_TIMESTAMP - MEETING_TIMESTAMP) / 60))
            ICON="󰁅"  # Urgent icon
            LABEL="$TITLE (started ${STARTED_AGO}m ago)"
            sketchybar --set "$NAME" icon="$ICON" --set "${NAME}.name" label="$LABEL"
            (umask 077; echo "$LABEL" > "$MEETING_DATA_CACHE")
        else
            # Fallback if timestamp calculation failed
            LABEL="No meetings"
            sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="$LABEL"
            (umask 077; echo "$LABEL" > "$MEETING_DATA_CACHE")
        fi
    else
        LABEL="No meetings"
        sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="$LABEL"
        (umask 077; echo "$LABEL" > "$MEETING_DATA_CACHE")
    fi
fi