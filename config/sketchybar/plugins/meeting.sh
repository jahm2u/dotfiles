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
MEETING_CACHE="$CACHE_DIR/meeting_cache"
MEETING_DATA_CACHE="$CACHE_DIR/meeting_data_cache"
MEETING_TIMESTAMP_CACHE="$CACHE_DIR/meeting_timestamp_cache"
MEETING_METADATA_CACHE="$CACHE_DIR/meeting_metadata_cache"
CALENDAR_HASH_FILE="$CACHE_DIR/calendar_hash"
SYNC_STATUS_FILE="$CACHE_DIR/last_sync_status"
LAST_FETCH_FILE="$CACHE_DIR/last_khal_fetch"

# Create cache directory if it doesn't exist
mkdir -p "$CACHE_DIR"

# Load environment colors for icon blinking
source "$HOME/.config/sketchybar/helpers/source-colors.sh"

# Determine if we should fetch fresh data from khal
# Fetch when:
# - calendar_synced event (fires every 15min from LaunchAgent)
# - system_woke event (computer woke from sleep)
# - No cached data exists (first run)
should_fetch_data() {
    case "$SENDER" in
        calendar_synced|system_woke)
            return 0  # Always fetch on these events
            ;;
        *)
            # For all other triggers (routine display updates), check if cache exists
            if [[ -f "$MEETING_TIMESTAMP_CACHE" && -f "$MEETING_METADATA_CACHE" ]]; then
                return 1  # Cache exists, skip fetch
            else
                return 0  # No cache, must fetch (first run)
            fi
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

# Fast display update function - uses cached meeting data
# This runs 2x per second and does NOT query khal
update_display_from_cache() {
    # Check if we have cached meeting data
    if [[ ! -f "$MEETING_TIMESTAMP_CACHE" ]] || [[ ! -f "$MEETING_METADATA_CACHE" ]]; then
        # No cache, show placeholder and trigger fetch
        sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="Loading..."
        return 1
    fi

    # Read cached data
    MEETING_TIMESTAMP=$(cat "$MEETING_TIMESTAMP_CACHE" 2>/dev/null)
    source "$MEETING_METADATA_CACHE"  # Loads: TITLE, TIME, DATE, MEETING_TYPE

    # Current time
    CURRENT_TIMESTAMP=$(date "+%s")

    case "$MEETING_TYPE" in
        NO_MEETINGS_EOD|NO_MEETINGS_FREE)
            # Static display for no meetings
            sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="$LABEL"
            ;;
        NO_CALENDAR)
            sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="$LABEL"
            ;;
        SYNC_FAILED)
            STALE_ICON="󰁡"
            sketchybar --set "$NAME" icon="$STALE_ICON" --set "${NAME}.name" label="$LABEL"
            ;;
        UPCOMING)
            # Calculate live countdown
            if [[ -n "$MEETING_TIMESTAMP" ]] && [[ "$MEETING_TIMESTAMP" -gt "$CURRENT_TIMESTAMP" ]]; then
                DIFF=$((MEETING_TIMESTAMP - CURRENT_TIMESTAMP))

                # Calculate days, hours, minutes
                DAYS=$((DIFF / 86400))
                REMAINING=$((DIFF % 86400))
                HOURS=$((REMAINING / 3600))
                MINUTES=$(((REMAINING % 3600) / 60))

                # Format countdown
                if [[ $DAYS -gt 0 ]]; then
                    if [[ $DAYS -eq 1 ]]; then
                        TIME_STR="tomorrow"
                    else
                        TIME_STR="in ${DAYS}d"
                    fi
                elif [[ $HOURS -gt 0 ]]; then
                    TIME_STR="${HOURS}h ${MINUTES}m"
                else
                    TIME_STR="${MINUTES}m"
                fi

                # Update blink state (this is what runs 2x per second)
                BLINK_STATE=$(get_icon_blink_state $DIFF)
                ICON_BASE="󰃭"

                if [[ $DIFF -le 600 ]]; then
                    # ≤10 min: heartbeat blinking
                    if [[ "$BLINK_STATE" == "on" ]]; then
                        MEETING_BG_COLOR="$YELLOW_THRESHOLD"
                        MEETING_ICON_COLOR="$BLACK"
                    else
                        MEETING_BG_COLOR="$BLUE"
                        MEETING_ICON_COLOR="$WHITE"
                    fi
                else
                    # >10 min: static display
                    MEETING_BG_COLOR="$BLUE"
                    MEETING_ICON_COLOR="$WHITE"
                fi

                LABEL="$TITLE in $TIME_STR"
                sketchybar --set "$NAME" \
                    icon="$ICON_BASE" \
                    icon.color="$MEETING_ICON_COLOR" \
                    background.color="$MEETING_BG_COLOR" \
                    --set "${NAME}.name" label="$LABEL"
            elif [[ -n "$MEETING_TIMESTAMP" ]] && [[ $((CURRENT_TIMESTAMP - MEETING_TIMESTAMP)) -le 600 ]]; then
                # Meeting started within last 10 minutes
                STARTED_AGO=$(((CURRENT_TIMESTAMP - MEETING_TIMESTAMP) / 60))
                ICON="󰁅"
                LABEL="$TITLE (started ${STARTED_AGO}m ago)"
                sketchybar --set "$NAME" icon="$ICON" --set "${NAME}.name" label="$LABEL"
            fi
            ;;
        *)
            # Unknown type, show error
            sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="Error"
            ;;
    esac
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
    # Record fetch timestamp
    date +%s > "$LAST_FETCH_FILE"

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

    # Handle sync failures - cache for display function
    if [[ "$SYNC_STATUS" == "failed" ]] || [[ "$SYNC_STATUS" == "partial" ]]; then
        SYNC_TIME=$(get_sync_timestamp)
        LABEL="Sync Failed ($SYNC_TIME)"

        # Cache the failure state
        echo "0" > "$MEETING_TIMESTAMP_CACHE"
        cat > "$MEETING_METADATA_CACHE" <<EOF
MEETING_TYPE="SYNC_FAILED"
LABEL="$LABEL"
TITLE=""
TIME=""
DATE=""
EOF
        return 0
    fi

    # Handle no calendar access
    if [[ "$EVENTS" =~ "No calendars" ]]; then
        LABEL="No calendar access"
        echo "0" > "$MEETING_TIMESTAMP_CACHE"
        cat > "$MEETING_METADATA_CACHE" <<EOF
MEETING_TYPE="NO_CALENDAR"
LABEL="$LABEL"
TITLE=""
TIME=""
DATE=""
EOF
        return 0
    fi

    # Handle no upcoming meetings
    if [[ -z "$EVENTS" ]] || [[ "$EVENTS" =~ "No events" ]]; then
        MEETING_STATE=$(check_meetings_today)
        if [[ "$MEETING_STATE" == "had_meetings" ]]; then
            LABEL=$(get_random_message END_OF_DAY_MESSAGES)
            MEETING_TYPE="NO_MEETINGS_EOD"
        else
            LABEL=$(get_random_message FREE_DAY_MESSAGES)
            MEETING_TYPE="NO_MEETINGS_FREE"
        fi

        echo "0" > "$MEETING_TIMESTAMP_CACHE"
        cat > "$MEETING_METADATA_CACHE" <<EOF
MEETING_TYPE="$MEETING_TYPE"
LABEL="$LABEL"
TITLE=""
TIME=""
DATE=""
EOF
        return 0
    fi
    # Process upcoming meetings - find next one and cache it
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

        # Cache the meeting data for fast display updates
        if [[ -n "$MEETING_TIMESTAMP" ]]; then
            echo "$MEETING_TIMESTAMP" > "$MEETING_TIMESTAMP_CACHE"
            cat > "$MEETING_METADATA_CACHE" <<EOF
MEETING_TYPE="UPCOMING"
TITLE="$TITLE"
TIME="$TIME"
DATE="$DATE"
LABEL=""
EOF
        fi
    else
        # No future meetings found
        MEETING_STATE=$(check_meetings_today)
        if [[ "$MEETING_STATE" == "had_meetings" ]]; then
            LABEL=$(get_random_message END_OF_DAY_MESSAGES)
            MEETING_TYPE="NO_MEETINGS_EOD"
        else
            LABEL=$(get_random_message FREE_DAY_MESSAGES)
            MEETING_TYPE="NO_MEETINGS_FREE"
        fi

        echo "0" > "$MEETING_TIMESTAMP_CACHE"
        cat > "$MEETING_METADATA_CACHE" <<EOF
MEETING_TYPE="$MEETING_TYPE"
LABEL="$LABEL"
TITLE=""
TIME=""
DATE=""
EOF
    fi
}

# MAIN EXECUTION LOGIC
# Decide whether to fetch data or just update display
if should_fetch_data; then
    # Fetch mode: Query khal and cache the results
    fetch_and_cache_meeting_data
fi

# Display mode: Always update display from cache (runs 2x per second)
update_display_from_cache