#!/usr/bin/env bash

# Enhanced meeting script with change detection and auto-sync
CACHE_DIR="$HOME/.cache/sketchybar"
MEETING_CACHE="$CACHE_DIR/meeting_cache"
CALENDAR_HASH_FILE="$CACHE_DIR/calendar_hash"

# Create cache directory if it doesn't exist
mkdir -p "$CACHE_DIR"

# Function to get calendar data hash
get_calendar_hash() {
    # Hash the actual calendar files to detect changes
    find ~/.local/share/khal/calendars -name "*.ics" -newer "$CALENDAR_HASH_FILE" 2>/dev/null | wc -l
}

# Function to force calendar sync
force_calendar_sync() {
    echo "$(date): Forcing calendar sync due to stale data" >> "$CACHE_DIR/sync.log"
    ~/.config/sketchybar/plugins/sync_calendars.sh >/dev/null 2>&1
    touch "$CALENDAR_HASH_FILE"
}

# Get events from khal with calendar name (skip the header line)
EVENTS_RAW=$(khal list today today --format "{calendar}|{start-time} - {end-time}: {title}" 2>/dev/null | tail -n +2 || echo "")

# Check if we have calendar data, if not, try to sync
if [[ "$EVENTS_RAW" =~ "No calendars" ]] || [[ -z "$EVENTS_RAW" ]]; then
    # Check if calendar files are older than 30 minutes
    if [[ ! -f "$CALENDAR_HASH_FILE" ]] || [[ $(find "$CALENDAR_HASH_FILE" -mmin +30) ]]; then
        force_calendar_sync
        # Retry getting events after sync
        EVENTS_RAW=$(khal list today today --format "{calendar}|{start-time} - {end-time}: {title}" 2>/dev/null | tail -n +2 || echo "")
    fi
fi

# Filter out spam events
SPAM_PATTERNS="fm\|.*(Million-Dollar|Webinar|Free Training|Limited Time|Act Now|Special Offer|How to Avoid|Mistakes When|Don't Miss|Last Chance|Exclusive|Register Now|Save Your Spot)"
EVENTS=$(echo "$EVENTS_RAW" | grep -v -E "$SPAM_PATTERNS" | sed 's/^[^|]*|//')

# Check if meeting data has changed significantly
CURRENT_HASH=$(echo "$EVENTS" | md5)
if [[ -f "$MEETING_CACHE" ]]; then
    CACHED_HASH=$(cat "$MEETING_CACHE" 2>/dev/null || echo "")
else
    CACHED_HASH=""
fi

# Store current hash for future comparison
echo "$CURRENT_HASH" > "$MEETING_CACHE"

if [[ "$EVENTS" =~ "No calendars" ]]; then
    # Real calendar access issue
    sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="No calendar access"
elif [[ -z "$EVENTS" ]] || [[ "$EVENTS" =~ "No events" ]]; then
    # No events for today - day off!
    sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="No meetings today"
elif [ -n "$EVENTS" ]; then
    # Get current time
    CURRENT_HOUR=$(date +%H)
    CURRENT_MIN=$(date +%M)
    CURRENT_TOTAL=$((10#$CURRENT_HOUR * 60 + 10#$CURRENT_MIN))
    
    # Find next meeting
    NEXT_EVENT=""
    NEXT_TIME=99999
    RECENTLY_STARTED=""
    LAST_STARTED_TIME=-1
    STARTED_AGO=0
    
    # Process each line
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Extract time and title from khal format: "09:00 AM - 10:00 AM: Meeting Title"
        if [[ "$line" =~ ^([0-9]{1,2}):([0-9]{2})\ (AM|PM)\ -\ [0-9]{1,2}:[0-9]{2}\ (AM|PM):\ (.+)$ ]]; then
            START_HOUR="${BASH_REMATCH[1]}"
            START_MIN="${BASH_REMATCH[2]}"
            START_AMPM="${BASH_REMATCH[3]}"
            TITLE="${BASH_REMATCH[5]}"
            
            # Convert to 24-hour format (force base 10 to avoid octal issues)
            if [[ "$START_AMPM" == "PM" ]] && [[ "$START_HOUR" != "12" ]]; then
                START_HOUR=$((10#$START_HOUR + 12))
            elif [[ "$START_AMPM" == "AM" ]] && [[ "$START_HOUR" == "12" ]]; then
                START_HOUR=0
            fi
            
            EVENT_TOTAL=$((10#$START_HOUR * 60 + 10#$START_MIN))
            
            # Check if this is in the future and closer than current next
            if [ $EVENT_TOTAL -gt $CURRENT_TOTAL ] && [ $EVENT_TOTAL -lt $NEXT_TIME ]; then
                NEXT_TIME=$EVENT_TOTAL
                NEXT_EVENT="$TITLE"
            # Check if meeting started within last 10 minutes
            elif [ $EVENT_TOTAL -le $CURRENT_TOTAL ] && [ $((CURRENT_TOTAL - EVENT_TOTAL)) -le 10 ]; then
                if [ -z "$NEXT_EVENT" ] || [ $EVENT_TOTAL -gt $LAST_STARTED_TIME ]; then
                    LAST_STARTED_TIME=$EVENT_TOTAL
                    RECENTLY_STARTED="$TITLE"
                    STARTED_AGO=$((CURRENT_TOTAL - EVENT_TOTAL))
                fi
            fi
        fi
    done <<< "$EVENTS"
    
    # Display result
    if [ -n "$RECENTLY_STARTED" ]; then
        # Always prioritize showing recently started meetings
        ICON="󰁅"  # Urgent icon for late meetings
        sketchybar --set "$NAME" icon="$ICON" --set "${NAME}.name" label="$RECENTLY_STARTED started ${STARTED_AGO}m ago"
    elif [ -n "$NEXT_EVENT" ]; then
        # Calculate time until meeting
        DIFF=$((NEXT_TIME - CURRENT_TOTAL))
        HOURS=$((DIFF / 60))
        MINS=$((DIFF % 60))
        
        if [ $HOURS -gt 0 ]; then
            TIME_STR="${HOURS}h ${MINS}m"
        else
            TIME_STR="${MINS}m"
        fi
        
        # Don't truncate title - let it use full width
        TITLE="$NEXT_EVENT"
        
        # Icon based on urgency
        if [ $DIFF -le 15 ]; then
            ICON="󰁅"  # Urgent
        else
            ICON="󰃭"  # Normal
        fi
        
        sketchybar --set "$NAME" icon="$ICON" --set "${NAME}.name" label="$TITLE in $TIME_STR"
    else
        sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="No meetings today"
    fi
fi