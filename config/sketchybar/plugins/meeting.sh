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
LOCK_FILE="$CACHE_DIR/meeting_fetch.lock"
LAST_RUN_FILE="$CACHE_DIR/meeting_last_run"

# Failsafe configuration
MAX_KHAL_PROCESSES=3           # Maximum allowed khal processes
KHAL_TIMEOUT=10                # Timeout for khal commands (seconds)
MIN_RUN_INTERVAL=1             # Minimum seconds between runs (rate limiting)

# Create cache directory if it doesn't exist
mkdir -p "$CACHE_DIR"

# Load environment colors for icon blinking
source "$HOME/.config/sketchybar/helpers/source-colors.sh"

# ============================================================================
# FAILSAFE MECHANISMS - Prevent runaway processes and fork bombs
# ============================================================================

# Failsafe 1: Check if too many khal processes are running
check_process_count() {
    local count=$(pgrep -f "khal" | wc -l | tr -d ' ')
    if [[ $count -ge $MAX_KHAL_PROCESSES ]]; then
        echo "ERROR: Too many khal processes running ($count >= $MAX_KHAL_PROCESSES). Aborting to prevent fork bomb." >> "$CACHE_DIR/meeting_error.log"
        return 1
    fi
    return 0
}

# Failsafe 2: Lock file mechanism - prevent concurrent data fetches
acquire_lock() {
    # Check if lock file exists and is less than 60 seconds old (stale lock protection)
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE" 2>/dev/null || echo 0) ))
        if [[ $lock_age -lt 60 ]]; then
            # Active lock, another instance is running
            return 1
        else
            # Stale lock (>60s old), remove it
            rm -f "$LOCK_FILE"
        fi
    fi

    # Create lock file with current PID
    echo $$ > "$LOCK_FILE"
    return 0
}

release_lock() {
    rm -f "$LOCK_FILE"
}

# Failsafe 3: Run khal with timeout to prevent hanging
run_khal_with_timeout() {
    local cmd="$1"
    local timeout_duration=${2:-$KHAL_TIMEOUT}

    # Check process count before running
    if ! check_process_count; then
        echo "Aborted: Too many khal processes"
        return 1
    fi

    # Run with timeout using background process and wait
    (
        eval "$cmd" &
        local pid=$!

        # Wait for timeout duration
        local count=0
        while [[ $count -lt $timeout_duration ]]; do
            if ! kill -0 $pid 2>/dev/null; then
                # Process finished
                wait $pid
                exit $?
            fi
            sleep 0.5
            count=$((count + 1))
        done

        # Timeout reached, kill the process
        kill -9 $pid 2>/dev/null
        echo "ERROR: khal command timed out after ${timeout_duration}s" >> "$CACHE_DIR/meeting_error.log"
        exit 124  # Timeout exit code
    )
    return $?
}

# Failsafe 4: Rate limiting - prevent too-frequent executions
check_rate_limit() {
    if [[ -f "$LAST_RUN_FILE" ]]; then
        local last_run=$(cat "$LAST_RUN_FILE")
        local current=$(date +%s)
        local elapsed=$((current - last_run))

        if [[ $elapsed -lt $MIN_RUN_INTERVAL ]]; then
            # Too soon since last run
            return 1
        fi
    fi

    # Update last run timestamp
    date +%s > "$LAST_RUN_FILE"
    return 0
}

# Emergency kill switch: If script is called with "emergency-stop" argument
if [[ "$1" == "emergency-stop" ]]; then
    echo "Emergency stop triggered - killing all khal processes"
    pkill -9 -f "khal"
    rm -f "$LOCK_FILE"
    exit 0
fi

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

# Work-focused message arrays - more direct and personal
# Messages are cached hourly and time-aware
END_OF_DAY_MESSAGES=(
    "Meetings crushed! 💪"
    "Calendar: cleared ✓"
    "Calls done. Ship mode?"
    "Meetings ✓ Focus time?"
    "Free to build now"
    "Uninterrupted time ahead"
    "Deep work unlocked"
    "Back to the code"
    "Meeting tax: paid"
    "Now: actual work"
)

FREE_DAY_MESSAGES=(
    "Zero meetings. Ship it!"
    "Full focus mode 🎯"
    "Deep work day"
    "Uninterrupted. Build."
    "No calls = Progress"
    "Focus time activated"
    "Maker's schedule today"
    "Your time. Use it well."
    "Build something great"
    "Distraction-free zone"
)

# Function to get random message from array
# Messages are cached for 1 hour to prevent constant changing
get_random_message() {
    local array_name=$1
    local cache_file="$CACHE_DIR/meeting_message_${array_name}"
    local cache_timestamp="$CACHE_DIR/meeting_message_${array_name}_time"
    local cache_duration=3600  # 1 hour in seconds

    # Check if we have a valid cached message
    if [[ -f "$cache_file" ]] && [[ -f "$cache_timestamp" ]]; then
        local cached_time=$(cat "$cache_timestamp" 2>/dev/null || echo 0)
        local current_time=$(date +%s)
        local age=$((current_time - cached_time))

        # If cache is less than 1 hour old, use it
        if [[ $age -lt $cache_duration ]]; then
            cat "$cache_file"
            return 0
        fi
    fi

    # Generate new random message
    eval "local count=\${#${array_name}[@]}"
    local index=$((RANDOM % count))
    eval "local message=\"\${${array_name}[$index]}\""

    # Cache the message
    echo "$message" > "$cache_file"
    date +%s > "$cache_timestamp"

    echo "$message"
}

# Function to check if there were any meetings today
# Uses cached event list instead of calling khal to avoid spawning processes
check_meetings_today() {
    # Check cached events list instead of calling khal directly
    if [[ ! -f "$EVENTS_LIST_CACHE" ]]; then
        echo "no_meetings"
        return
    fi

    # Read cached events
    local cached_events=$(sed '1,/^EVENTS_START$/d' "$EVENTS_LIST_CACHE")
    local today=$(date +%Y-%m-%d)

    # Check if any event is from today
    if echo "$cached_events" | grep -q "|$today$"; then
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
        sketchybar --set "$NAME" icon="󰃭" label="Loading..."
        return 1
    fi

    # Read cached event list
    SYNC_STATUS=$(grep "^SYNC_STATUS=" "$EVENTS_LIST_CACHE" | cut -d= -f2)
    EVENTS=$(sed '1,/^EVENTS_START$/d' "$EVENTS_LIST_CACHE")

    CURRENT_TIMESTAMP=$(date "+%s")

    # Handle sync failures
    if [[ "$SYNC_STATUS" == "failed" ]] || [[ "$SYNC_STATUS" == "partial" ]]; then
        SYNC_TIME=$(get_sync_timestamp)
        sketchybar --set "$NAME" icon="󰁡" label="Sync Failed ($SYNC_TIME)"
        return 0
    fi

    # Handle no calendar access
    if [[ "$EVENTS" =~ "No calendars" ]]; then
        sketchybar --set "$NAME" icon="󰃭" label="No calendar access"
        return 0
    fi

    # Handle empty event list
    if [[ -z "$EVENTS" ]] || [[ "$EVENTS" =~ "No events" ]]; then
        LABEL=$(get_random_message FREE_DAY_MESSAGES)
        sketchybar --set "$NAME" icon="󰃭" label="$LABEL"
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

    # Day boundary check: if next meeting is tomorrow or later, show appropriate message
    if [[ -n "$NEXT_MEETING" ]]; then
        MEETING_DATE=$(echo "$NEXT_MEETING" | cut -d'|' -f3)
        TODAY=$(date +%Y-%m-%d)

        if [[ "$MEETING_DATE" != "$TODAY" ]]; then
            # Meeting is tomorrow or later - check if we had meetings today
            MEETING_STATUS=$(check_meetings_today)

            if [[ "$MEETING_STATUS" == "had_meetings" ]]; then
                # Had meetings today, all done - show end of day message
                LABEL=$(get_random_message END_OF_DAY_MESSAGES)
            else
                # No meetings today at all - show free day message
                LABEL=$(get_random_message FREE_DAY_MESSAGES)
            fi

            sketchybar --set "$NAME" icon="󰃭" label="$LABEL"
            return
        fi
    fi

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
                label="$TITLE in $TIME_STR"
        elif [[ -n "$MEETING_TIMESTAMP" ]]; then
            # Meeting started recently
            STARTED_AGO=$(((CURRENT_TIMESTAMP - MEETING_TIMESTAMP) / 60))
            sketchybar --set "$NAME" icon="󰁅" label="$TITLE (started ${STARTED_AGO}m ago)"
        fi
    else
        # No upcoming meetings - check if we had meetings today
        MEETING_STATUS=$(check_meetings_today)

        if [[ "$MEETING_STATUS" == "had_meetings" ]]; then
            # Had meetings today, all done - show end of day message
            LABEL=$(get_random_message END_OF_DAY_MESSAGES)
        else
            # No meetings today at all - show free day message
            LABEL=$(get_random_message FREE_DAY_MESSAGES)
        fi

        sketchybar --set "$NAME" icon="󰃭" label="$LABEL"
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
    # Failsafe: Check rate limiting first
    if ! check_rate_limit; then
        # Too soon since last run, skip silently
        return 0
    fi

    # Failsafe: Acquire lock to prevent concurrent fetches
    if ! acquire_lock; then
        # Another instance is already fetching, skip
        return 0
    fi

    # Ensure lock is released even if script fails
    trap release_lock EXIT INT TERM

    # Failsafe: Check process count before starting
    if ! check_process_count; then
        release_lock
        return 1
    fi

    # Check sync status before fetching events
    SYNC_STATUS=$(check_sync_status)

    # Get next meeting within 7 days (using new format: title|time|date|attendees)
    # Note: tail -n +2 skips the first line which is khal's date header (e.g., "Today, 2025-10-29")
    # Failsafe: Use timeout wrapper to prevent hanging
    EVENTS_RAW=$(run_khal_with_timeout 'khal list now 7d --format "{title}|{start-time}|{start-date}|{attendees}" 2>/dev/null | tail -n +2' || echo "")

    # Check if we have calendar data, if not, try to sync
    if [[ "$EVENTS_RAW" =~ "No calendars" ]] || [[ -z "$EVENTS_RAW" ]]; then
        # Check if calendar files are older than 30 minutes (stale threshold)
        # 30 minutes = 2x the 15-minute LaunchAgent sync interval
        # If we've missed 2 sync cycles, force a manual sync
        if [[ ! -f "$CALENDAR_HASH_FILE" ]] || [[ $(find "$CALENDAR_HASH_FILE" -mmin +30 2>/dev/null) ]]; then
            force_calendar_sync
            # Retry getting events after sync (tail -n +2 skips khal's date header line)
            # Failsafe: Use timeout wrapper
            EVENTS_RAW=$(run_khal_with_timeout 'khal list now 7d --format "{title}|{start-time}|{start-date}|{attendees}" 2>/dev/null | tail -n +2' || echo "")
            # Update sync status after forced sync
            SYNC_STATUS=$(check_sync_status)
        fi
    fi

    # Filter out spam events
    SPAM_PATTERNS=".*(Million-Dollar|Webinar|Free Training|Limited Time|Act Now|Special Offer|How to Avoid|Mistakes When|Don't Miss|Last Chance|Exclusive|Register Now|Save Your Spot)"
    EVENTS=$(echo "$EVENTS_RAW" | grep -v -E "$SPAM_PATTERNS")

    # Filter out khal's date header lines (they don't have pipe delimiters)
    # Headers look like: "Today, 2025-11-04" or "Tomorrow, 2025-11-05"
    EVENTS=$(echo "$EVENTS" | grep '|')

    # Cache the complete event list for display function to process
    # Store sync status at top of file, then event list
    {
        echo "SYNC_STATUS=$SYNC_STATUS"
        echo "EVENTS_START"
        echo "$EVENTS"
    } > "$EVENTS_LIST_CACHE"

    # Release lock explicitly (trap will also release it)
    release_lock
}

# MAIN EXECUTION LOGIC
# Decide whether to fetch data or just update display
if should_fetch_data; then
    # Fetch mode: Query khal and cache the results
    fetch_and_cache_meeting_data
fi

# Display mode: Always update display from cache (runs 2x per second)
update_display_from_cache