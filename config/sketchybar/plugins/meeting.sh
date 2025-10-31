#!/usr/bin/env bash

# Enhanced meeting script with separated data fetch and display update
#
# TWO MODES:
# 1. DATA FETCH MODE: Queries khal every 30 minutes (triggered by routine, calendar_synced, system_woke)
# 2. DISPLAY UPDATE MODE: Updates countdown/blink 2x per second using cached data
#
# Sketchybar Environment Variables:
#   $NAME - The item name (e.g., "meeting")
#   $SENDER - Event that triggered the script (e.g., "calendar_synced", "forced", "routine")
#
# Dependencies:
#   - khal: Calendar CLI tool for querying upcoming meetings
#   - Sketchybar event system: Listens for calendar_synced events

CACHE_DIR="$HOME/.cache/sketchybar"
EVENTS_LIST_CACHE="$CACHE_DIR/meeting_events_list"
SYNC_STATUS_FILE="$CACHE_DIR/last_sync_status"
CALENDAR_HASH_FILE="$CACHE_DIR/calendar_hash"

# Create cache directory if it doesn't exist
mkdir -p "$CACHE_DIR"

# Load environment colors for icon blinking
source "$HOME/.config/sketchybar/helpers/source-colors.sh"

# Determine if we should fetch fresh data from khal
# ONLY fetch on specific events to avoid querying khal every second
# Fetch when:
# - calendar_synced event (fires every 15min from LaunchAgent)
# - system_woke event (computer woke from sleep)
should_fetch_data() {
    case "$SENDER" in
        calendar_synced|system_woke)
            return 0  # Always fetch on these events
            ;;
        *)
            # For all other triggers (routine display updates), NEVER fetch
            # This prevents querying khal every second
            return 1  # Skip fetch, use cached data or show placeholder
            ;;
    esac
}

# Random message arrays for no meetings
END_OF_DAY_MESSAGES=(
    "All clear! 🌅"
    "Day complete! ✨"
    "You're done! 🎉"
    "Time to unwind 😌"
    "Meetings wrapped! 🎁"
    "Free at last! 🕊️"
    "Calendar clear! ☀️"
    "Nothing left! 🏖️"
    "All finished! 🎊"
    "Take a break! ☕"
    "Day's done! 🌙"
    "Freedom! 🦅"
    "Rest time! 💤"
    "Clock out! ⏰"
    "Relax now! 🧘"
)

FREE_DAY_MESSAGES=(
    "No meetings! 🎨"
    "Free day! 🌈"
    "Open schedule! 📖"
    "Your time! ⏳"
    "Zero meetings! 🎯"
    "All yours! 🎪"
    "Unscheduled! 🗓️"
    "Meeting-free! 🦋"
    "No calls! 📵"
    "Empty slate! 📝"
    "Flexible day! 🤸"
    "Own your time! ⚡"
    "Interruption-free! 🧩"
    "Full control! 🎮"
    "No agenda! 🌊"
)

# Function to get random message from array
get_random_message() {
    local -n array=$1
    local count=${#array[@]}
    local index=$((RANDOM % count))
    echo "${array[$index]}"
}

# Function to check if there were any meetings today
check_meetings_today() {
    local today_start=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) 00:00:00" "+%s" 2>/dev/null)
    local now=$(date +%s)

    # Check khal for any meetings that started today
    local today_events=$(khal list today now --format "{title}|{start-time}|{start-date}" 2>/dev/null | tail -n +2 || echo "")

    if [[ -n "$today_events" ]]; then
        echo "had_meetings"
    else
        echo "no_meetings"
    fi
}

# Function to determine icon color based on time until meeting
# This runs 2x per second for blinking effect
get_icon_blink_state() {
    local time_until=$1

    if [[ $time_until -le 600 ]]; then
        # ≤10 min: heartbeat (fast blink = 2 blinks per second)
        # Get milliseconds for sub-second timing
        local current_ms=$(python3 -c "import time; print(int(time.time() * 1000))")
        local cycle=$(( (current_ms / 500) % 2 ))  # Toggle every 500ms
        if [[ $cycle -eq 0 ]]; then
            echo "on"
        else
            echo "off"
        fi
    else
        # >10 min: no blinking, static display
        echo "static"
    fi
}

# Fast display update function - reads cached event list and finds next meeting
# This runs every second and does NOT query khal
update_display_from_cache() {
    # Check if we have cached event list
    if [[ ! -f "$EVENTS_LIST_CACHE" ]]; then
        sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="Loading..."
        return 1
    fi

    # Read cached event list
    SYNC_STATUS=$(grep "^SYNC_STATUS=" "$EVENTS_LIST_CACHE" | cut -d= -f2)
    EVENTS=$(sed '1,/^EVENTS_START$/d' "$EVENTS_LIST_CACHE")

    CURRENT_TIMESTAMP=$(date "+%s")

    # Handle sync failures
    if [[ "$SYNC_STATUS" == "failed" ]] || [[ "$SYNC_STATUS" == "partial" ]]; then
        SYNC_TIME=$(get_sync_timestamp)
        sketchybar --set "$NAME" icon="󰁡" --set "${NAME}.name" label="Sync Failed ($SYNC_TIME)"
        return 0
    fi

    # Handle no calendar access
    if [[ "$EVENTS" =~ "No calendars" ]]; then
        sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="No calendar access"
        return 0
    fi

    # Handle empty event list
    if [[ -z "$EVENTS" ]] || [[ "$EVENTS" =~ "No events" ]]; then
        LABEL=$(get_random_message FREE_DAY_MESSAGES)
        sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="$LABEL"
        return 0
    fi

    # Find next meeting from cached list
    NEXT_MEETING=""
    while IFS= read -r event; do
        [[ -z "$event" ]] && continue

        # Parse format: "Meeting Title|09:00 AM|2025-10-29"
        EVENT_TIME=$(echo "$event" | cut -d'|' -f2)
        EVENT_DATE=$(echo "$event" | cut -d'|' -f3)

        # Calculate event timestamp
        EVENT_TIMESTAMP=$(date -j -f "%Y-%m-%d %I:%M %p" "$EVENT_DATE $EVENT_TIME" "+%s" 2>/dev/null)
        if [[ -z "$EVENT_TIMESTAMP" ]]; then
            EVENT_TIMESTAMP=$(date -j -f "%Y-%m-%d %H:%M" "$EVENT_DATE $EVENT_TIME" "+%s" 2>/dev/null)
        fi

        # Include events that haven't ended yet (within 10 minutes of start or future)
        if [[ -n "$EVENT_TIMESTAMP" ]] && [[ $((CURRENT_TIMESTAMP - EVENT_TIMESTAMP)) -le 600 ]]; then
            NEXT_MEETING="$event"
            break  # Found next meeting
        fi
    done <<< "$EVENTS"

    # Display next meeting or end-of-day message
    if [[ -n "$NEXT_MEETING" ]]; then
        TITLE=$(echo "$NEXT_MEETING" | cut -d'|' -f1)
        TIME=$(echo "$NEXT_MEETING" | cut -d'|' -f2)
        DATE=$(echo "$NEXT_MEETING" | cut -d'|' -f3)

        MEETING_TIMESTAMP=$(date -j -f "%Y-%m-%d %I:%M %p" "$DATE $TIME" "+%s" 2>/dev/null)
        if [[ -z "$MEETING_TIMESTAMP" ]]; then
            MEETING_TIMESTAMP=$(date -j -f "%Y-%m-%d %H:%M" "$DATE $TIME" "+%s" 2>/dev/null)
        fi

        if [[ -n "$MEETING_TIMESTAMP" ]] && [[ "$MEETING_TIMESTAMP" -gt "$CURRENT_TIMESTAMP" ]]; then
            # Future meeting - show countdown
            DIFF=$((MEETING_TIMESTAMP - CURRENT_TIMESTAMP))
            DAYS=$((DIFF / 86400))
            REMAINING=$((DIFF % 86400))
            HOURS=$((REMAINING / 3600))
            MINUTES=$(((REMAINING % 3600) / 60))

            if [[ $DAYS -gt 0 ]]; then
                TIME_STR=$([[ $DAYS -eq 1 ]] && echo "tomorrow" || echo "in ${DAYS}d")
            elif [[ $HOURS -gt 0 ]]; then
                TIME_STR="${HOURS}h ${MINUTES}m"
            else
                TIME_STR="${MINUTES}m"
            fi

            # Blinking for meetings ≤10 min away
            BLINK_STATE=$(get_icon_blink_state $DIFF)
            if [[ $DIFF -le 600 ]] && [[ "$BLINK_STATE" == "on" ]]; then
                MEETING_BG_COLOR="$YELLOW_THRESHOLD"
                MEETING_ICON_COLOR="$BLACK"
            else
                MEETING_BG_COLOR="$BLUE"
                MEETING_ICON_COLOR="$WIDGET_ICON_COLOR"
            fi

            sketchybar --set "$NAME" \
                icon="󰃭" \
                icon.color="$MEETING_ICON_COLOR" \
                background.color="$MEETING_BG_COLOR" \
                --set "${NAME}.name" label="$TITLE in $TIME_STR"
        elif [[ -n "$MEETING_TIMESTAMP" ]]; then
            # Meeting started recently
            STARTED_AGO=$(((CURRENT_TIMESTAMP - MEETING_TIMESTAMP) / 60))
            sketchybar --set "$NAME" icon="󰁅" --set "${NAME}.name" label="$TITLE (started ${STARTED_AGO}m ago)"
        fi
    else
        # No upcoming meetings
        LABEL=$(get_random_message END_OF_DAY_MESSAGES)
        sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="$LABEL"
    fi
}

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

# DATA FETCH FUNCTION - Queries khal and caches results
# Only called when should_fetch_data() returns true
fetch_and_cache_meeting_data() {
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

    # Cache the complete event list for display function to process
    # Store sync status at top of file, then event list
    {
        echo "SYNC_STATUS=$SYNC_STATUS"
        echo "EVENTS_START"
        echo "$EVENTS"
    } > "$EVENTS_LIST_CACHE"
}

# MAIN EXECUTION LOGIC
# Decide whether to fetch data or just update display
if should_fetch_data; then
    # Fetch mode: Query khal and cache the results
    fetch_and_cache_meeting_data
fi

# Display mode: Always update display from cache (runs 2x per second)
update_display_from_cache