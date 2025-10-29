#!/bin/bash

# Exit on unset variables, but don't exit on command failures (we handle those)
set -u

# Logging configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs"
LOG_FILE="${LOG_DIR}/calendar-sync.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR" || {
    echo "FATAL: Cannot create log directory: $LOG_DIR" >&2
    exit 1
}

# Logging function - outputs to both console and log file
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

# Log rotation function
rotate_logs() {
    # Skip rotation if log file doesn't exist
    [[ ! -f "$LOG_FILE" ]] && return 0

    # Get log file size in bytes
    local log_size
    log_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo "0")

    # Rotate if size exceeds 1MB (1048576 bytes)
    if [[ "$log_size" -gt 1048576 ]]; then
        local archive_name="${LOG_FILE%.log}-$(date '+%Y-%m-%d-%H%M%S').log"
        mv "$LOG_FILE" "$archive_name"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Log rotated to: $(basename "$archive_name")" >> "$LOG_FILE"
    fi

    # Keep only last 10 log files (excluding current log)
    local archive_count
    archive_count=$(find "$LOG_DIR" -name "calendar-sync-*.log" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$archive_count" -gt 10 ]]; then
        # Delete oldest archived logs, keeping only 10 most recent
        find "$LOG_DIR" -name "calendar-sync-*.log" -type f 2>/dev/null | \
            sort | \
            head -n -10 | \
            xargs rm -f
    fi
}

# Rotate logs at startup
rotate_logs

# Source the .env file to get calendar URLs
# Try multiple locations to find .env file (should be in project root)
ENV_FILE=""
for possible_location in \
    "$HOME/dotfiles/.env" \
    "$HOME/repos/02_personal/dotfiles/.env" \
    "$HOME/.config/sketchybar/../../.env" \
    "$(dirname "$(dirname "$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")")")/../../.env"
do
    if [[ -r "$possible_location" ]]; then
        ENV_FILE="$possible_location"
        break
    fi
done

if [[ -n "$ENV_FILE" ]] && [[ -r "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    log "INFO" "Loaded environment from: $ENV_FILE"
else
    log "ERROR" ".env file not found or not readable"
    log "ERROR" "Expected locations: ~/dotfiles/.env or ~/repos/02_personal/dotfiles/.env"
    exit 1
fi

# Set history window configuration with default
CALENDAR_HISTORY_DAYS=${CALENDAR_HISTORY_DAYS:-7}

# Validate CALENDAR_HISTORY_DAYS is a positive integer
if ! [[ "$CALENDAR_HISTORY_DAYS" =~ ^[0-9]+$ ]] || [[ "$CALENDAR_HISTORY_DAYS" -lt 1 ]]; then
    log "WARN" "Invalid CALENDAR_HISTORY_DAYS value '${CALENDAR_HISTORY_DAYS}', using default=7"
    CALENDAR_HISTORY_DAYS=7
fi

log "INFO" "Starting calendar sync"
log "INFO" "History window: ${CALENDAR_HISTORY_DAYS} days"

# Track sync start time
SYNC_START=$(date +%s)

# Discover calendar URLs using CALENDAR_URL_* pattern
# Try bash 4+ parameter expansion first, fall back to grep for bash 3.2 compatibility
CALENDAR_URLS=()
CALENDAR_NAMES=()

# Detect bash version and use appropriate method
if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
    # Bash 4+: Use parameter expansion to find all CALENDAR_URL_* variables
    for var_name in ${!CALENDAR_URL_@}; do
        url="${!var_name}"
        # Extract suffix: CALENDAR_URL_GOOGLE → GOOGLE
        cal_name_upper="${var_name#CALENDAR_URL_}"
        # Convert to lowercase: GOOGLE → google
        cal_name=$(echo "$cal_name_upper" | tr '[:upper:]' '[:lower:]')

        CALENDAR_URLS+=("$url")
        CALENDAR_NAMES+=("$cal_name")
    done
else
    # Bash 3.2 fallback: Use compgen to find all variables (works with sourced, non-exported vars)
    for var_name in $(compgen -v | grep '^CALENDAR_URL_'); do
        url="${!var_name}"
        # Extract suffix: CALENDAR_URL_GOOGLE → GOOGLE
        cal_name_upper="${var_name#CALENDAR_URL_}"
        # Convert to lowercase: GOOGLE → google
        cal_name=$(echo "$cal_name_upper" | tr '[:upper:]' '[:lower:]')

        CALENDAR_URLS+=("$url")
        CALENDAR_NAMES+=("$cal_name")
    done
fi

# Backward compatibility: Fall back to ICAL_URLS if no CALENDAR_URL_* variables found
if [[ ${#CALENDAR_URLS[@]} -eq 0 ]] && [[ -n "${ICAL_URLS:-}" ]]; then
    log "WARN" "Using deprecated ICAL_URLS format. Please migrate to CALENDAR_URL_* pattern (see .env.example)"

    IFS=',' read -ra URLS <<< "$ICAL_URLS"
    for i in "${!URLS[@]}"; do
        url="${URLS[$i]}"

        # Legacy calendar name detection based on URL content
        if [[ "$url" == *"google"* ]]; then
            cal_name="google"
        elif [[ "$url" == *"user.fm"* ]]; then
            cal_name="fm"
        else
            log "WARN" "Cannot determine calendar name from URL: $url (skipping)"
            continue
        fi

        CALENDAR_URLS+=("$url")
        CALENDAR_NAMES+=("$cal_name")
    done
fi

# Validate that at least one calendar URL is configured
if [[ ${#CALENDAR_URLS[@]} -eq 0 ]]; then
    log "ERROR" "No CALENDAR_URL_* variables defined in .env"
    log "ERROR" "Please configure at least one calendar URL (see config/sketchybar/.env.example)"
    exit 1
fi

log "INFO" "Discovered ${#CALENDAR_URLS[@]} calendar source(s)"

# Track statistics for summary
VALID_URLS=0
INVALID_URLS=0
SUCCESSFUL_IMPORTS=0
FAILED_IMPORTS=0

# Process each calendar URL
for i in "${!CALENDAR_URLS[@]}"; do
    url="${CALENDAR_URLS[$i]}"
    cal_name="${CALENDAR_NAMES[$i]}"

    log "INFO" "Processing calendar: $cal_name"

    # Validate URL format
    if [[ ! "$url" =~ ^https?:// ]]; then
        log "ERROR" "Invalid URL format for $cal_name (must start with http:// or https://): ${url:0:50}..."
        ((INVALID_URLS++))
        continue
    fi

    ((VALID_URLS++))
    log "INFO" "URL validated for $cal_name"

    # Create calendar directory dynamically
    CAL_DIR="$HOME/.local/share/khal/calendars/$cal_name"
    if mkdir -p "$CAL_DIR" 2>/dev/null; then
        log "INFO" "Calendar directory ready: $cal_name"
    else
        log "ERROR" "Failed to create calendar directory: $CAL_DIR"
        ((FAILED_IMPORTS++))
        continue
    fi

    # Download calendar
    TEMP_FILE=$(mktemp) || {
        log "ERROR" "Failed to create temp file for $cal_name"
        ((FAILED_IMPORTS++))
        continue
    }

    log "INFO" "Downloading $cal_name calendar..."

    # Download with detailed error capture
    CURL_EXIT=0
    curl -sL --max-time 60 "$url" -o "$TEMP_FILE" 2>/dev/null || CURL_EXIT=$?

    if [[ $CURL_EXIT -ne 0 ]]; then
        # Log specific curl error with code
        case $CURL_EXIT in
            6)  log "ERROR" "Failed to download $cal_name: DNS resolution failed (curl exit 6)" ;;
            7)  log "ERROR" "Failed to download $cal_name: Connection refused (curl exit 7)" ;;
            22)
                log "ERROR" "Failed to download $cal_name: HTTP error (curl exit 22)"
                # Capture and log first 200 bytes of error response
                if [[ -f "$TEMP_FILE" ]]; then
                    ERROR_CONTENT=$(head -c 200 "$TEMP_FILE" 2>/dev/null | tr '\n' ' ' | tr -s ' ')
                    if [[ -n "$ERROR_CONTENT" ]]; then
                        log "ERROR" "HTTP response preview: ${ERROR_CONTENT:0:200}"
                    fi
                fi
                ;;
            28) log "ERROR" "Failed to download $cal_name: Timeout after 60s (curl exit 28)" ;;
            35) log "ERROR" "Failed to download $cal_name: SSL/TLS error (curl exit 35)" ;;
            *)  log "ERROR" "Failed to download $cal_name: Network error (curl exit $CURL_EXIT)" ;;
        esac
        log "ERROR" "Calendar URL: ${url:0:60}..."
        ((FAILED_IMPORTS++))
        rm -f "$TEMP_FILE" 2>/dev/null || true
        continue
    fi

    # Check if it's a valid ICS file
    if ! grep -q "BEGIN:VCALENDAR" "$TEMP_FILE" 2>/dev/null; then
        log "ERROR" "Invalid calendar file for $cal_name (missing VCALENDAR header)"
        log "ERROR" "File may be HTML error page or corrupted data"
        log "ERROR" "Source URL: ${url:0:60}..."
        ((FAILED_IMPORTS++))
        rm -f "$TEMP_FILE" 2>/dev/null || true
        continue
    fi

    log "INFO" "Valid ICS file downloaded for $cal_name"
    log "INFO" "Importing events to $cal_name..."

    # Import to khal with detailed error capture
    KHAL_OUTPUT=$(khal import -a "$cal_name" --batch "$TEMP_FILE" 2>&1) || KHAL_EXIT=$?
    KHAL_EXIT=${KHAL_EXIT:-0}

    if [[ $KHAL_EXIT -ne 0 ]]; then
        log "ERROR" "khal import failed for $cal_name (exit code: $KHAL_EXIT)"
        log "ERROR" "khal output: ${KHAL_OUTPUT:0:200}"
        ((FAILED_IMPORTS++))
    elif echo "$KHAL_OUTPUT" | grep -q "critical:"; then
        # Khal succeeded but reported critical parse errors
        log "WARN" "Some events failed to import to $cal_name"
        log "WARN" "Parse errors: $(echo "$KHAL_OUTPUT" | grep "critical:" | head -1)"
        # Count as partial success - some events may have imported
        ((SUCCESSFUL_IMPORTS++))
    else
        log "INFO" "Successfully imported $cal_name calendar"
        ((SUCCESSFUL_IMPORTS++))
    fi

    rm -f "$TEMP_FILE" 2>/dev/null || true
done

IMPORT_END=$(date +%s)
IMPORT_DURATION=$((IMPORT_END - SYNC_START))
log "INFO" "Import phase complete (${IMPORT_DURATION}s), starting stale event cleanup"

# Calculate cutoff date for stale event detection
CUTOFF_DATE=$(date -v-"${CALENDAR_HISTORY_DAYS}"d +%Y-%m-%d 2>/dev/null) || {
    log "ERROR" "Failed to calculate cutoff date, skipping cleanup"
    log "INFO" "Calendar sync complete"
    exit 0
}
log "INFO" "Cutoff date: ${CUTOFF_DATE} (events before this will be removed)"

# Verify khal is accessible before proceeding
if ! command -v khal &>/dev/null; then
    log "ERROR" "khal command not found, skipping cleanup"
    log "INFO" "Calendar sync complete"
    exit 0
fi

# Query khal for stale events (events before cutoff date)
STALE_EVENTS=()
while IFS= read -r line; do
    if [[ -n "$line" ]]; then
        STALE_EVENTS+=("$line")
    fi
done < <(khal list --format '{uid}|{title}|{start-date}|{calendar}' --day-format '' "1900-01-01" "${CUTOFF_DATE}" 2>/dev/null || true)

# Log count of stale events detected
STALE_COUNT=${#STALE_EVENTS[@]}
if [[ $STALE_COUNT -eq 0 ]]; then
    log "INFO" "No stale events detected, skipping cleanup"
else
    log "INFO" "Detected ${STALE_COUNT} stale events"

    # Safe cleanup approach: Remove individual .ics files for one-time past events
    # Preserve all recurring events (RRULE) to maintain future occurrences
    DELETED_COUNT=0
    FAILED_COUNT=0

    # Process stale events for each discovered calendar
    for calendar in "${CALENDAR_NAMES[@]}"; do
        CAL_DIR="$HOME/.local/share/khal/calendars/$calendar"

        if [[ ! -d "$CAL_DIR" ]]; then
            log "WARN" "Calendar directory not found: $calendar, skipping"
            continue
        fi

        log "INFO" "Processing stale events in $calendar..."

        # Iterate through .ics files and check each for:
        # 1. Is it a one-time event (no RRULE)?
        # 2. Did it end before the cutoff date?
        for ics_file in "$CAL_DIR"/*.ics; do
            [[ -f "$ics_file" ]] || continue

            # Skip if file has random suffix (temp files from khal)
            [[ "$ics_file" =~ \.ics[a-z0-9_]+$ ]] && continue

            # Check if event is recurring (has RRULE)
            if grep -q "^RRULE:" "$ics_file" 2>/dev/null; then
                # Preserve recurring events - they may have future occurrences
                continue
            fi

            # Extract DTEND or DTSTART to determine if event is past
            EVENT_END=$(grep -E "^DTEND" "$ics_file" 2>/dev/null | head -1 | cut -d: -f2 | cut -dT -f1)
            if [[ -z "$EVENT_END" ]]; then
                # No DTEND, use DTSTART
                EVENT_END=$(grep -E "^DTSTART" "$ics_file" 2>/dev/null | head -1 | cut -d: -f2 | cut -dT -f1)
            fi

            if [[ -n "$EVENT_END" ]]; then
                # Convert dates to comparable format (remove hyphens)
                EVENT_END_CMP=$(echo "$EVENT_END" | tr -d '-')
                CUTOFF_CMP=$(echo "$CUTOFF_DATE" | tr -d '-')

                # If event ended before cutoff, delete it
                # Note: Lexicographic comparison (< operator) is correct for YYYYMMDD format
                # since date strings sort chronologically when formatted this way
                if [[ "$EVENT_END_CMP" < "$CUTOFF_CMP" ]]; then
                    if rm -f "$ics_file" 2>/dev/null; then
                        ((DELETED_COUNT++))
                    else
                        ((FAILED_COUNT++))
                    fi
                fi
            fi
        done

        log "INFO" "Processed $calendar calendar"
    done

    CLEANUP_END=$(date +%s)
    CLEANUP_DURATION=$((CLEANUP_END - IMPORT_END))

    # Log cleanup summary
    log "INFO" "Cleanup complete: removed $DELETED_COUNT stale event files (${CLEANUP_DURATION}s)"
    if [[ $FAILED_COUNT -gt 0 ]]; then
        log "WARN" "Failed to delete $FAILED_COUNT files"
    fi
fi

# Final summary
SYNC_END=$(date +%s)
TOTAL_DURATION=$((SYNC_END - SYNC_START))

log "INFO" "====== Sync Summary ======"
log "INFO" "Total duration: ${TOTAL_DURATION}s"
log "INFO" "Calendars discovered: ${#CALENDAR_URLS[@]}"
log "INFO" "Valid URLs: ${VALID_URLS}"
log "INFO" "Invalid URLs: ${INVALID_URLS}"
log "INFO" "Successful imports: ${SUCCESSFUL_IMPORTS}"
log "INFO" "Failed imports: ${FAILED_IMPORTS}"
log "INFO" "Stale events detected: ${STALE_COUNT:-0}"
log "INFO" "Stale events removed: ${DELETED_COUNT:-0}"
log "INFO" "Cleanup errors: ${FAILED_COUNT:-0}"
log "INFO" "========================="

# Determine exit code based on sync results
SYNC_EXIT_CODE=0
if [[ $SUCCESSFUL_IMPORTS -eq 0 ]] && [[ $VALID_URLS -gt 0 ]]; then
    # Complete failure: no calendars imported successfully
    SYNC_EXIT_CODE=2
    log "ERROR" "Calendar sync FAILED: No calendars imported successfully"
elif [[ $FAILED_IMPORTS -gt 0 ]]; then
    # Partial failure: some calendars failed
    SYNC_EXIT_CODE=1
    log "WARN" "Calendar sync completed with PARTIAL SUCCESS: $FAILED_IMPORTS of $VALID_URLS failed"
else
    # Complete success
    log "INFO" "Calendar sync completed SUCCESSFULLY"
fi

# Trigger Sketchybar event to update meeting widget immediately
SKETCHYBAR_BIN="/opt/homebrew/bin/sketchybar"
if [[ -x "$SKETCHYBAR_BIN" ]]; then
    "$SKETCHYBAR_BIN" --trigger calendar_synced
    log "INFO" "Triggered calendar_synced event for Sketchybar"
else
    log "WARN" "Sketchybar binary not found at $SKETCHYBAR_BIN"
fi

# Write sync status to cache for meeting widget
SYNC_STATUS_FILE="$HOME/.cache/sketchybar/last_sync_status"
mkdir -p "$(dirname "$SYNC_STATUS_FILE")"
# Use restrictive permissions (600) for cache files
(
    umask 077
    echo "exit_code=$SYNC_EXIT_CODE" > "$SYNC_STATUS_FILE"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')" >> "$SYNC_STATUS_FILE"
    echo "successful_imports=$SUCCESSFUL_IMPORTS" >> "$SYNC_STATUS_FILE"
    echo "failed_imports=$FAILED_IMPORTS" >> "$SYNC_STATUS_FILE"
)

exit $SYNC_EXIT_CODE