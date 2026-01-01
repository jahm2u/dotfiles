#!/bin/bash
# Meeting Preparation - Jonas API Integration
# Sends meeting title to Jonas, opens resulting Obsidian note

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs"
LOG_FILE="${LOG_DIR}/meeting-prep.log"
CACHE_DIR="$HOME/.cache/sketchybar"

mkdir -p "$LOG_DIR" "$CACHE_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" | tee -a "$LOG_FILE"
}

# Load environment variables
load_env() {
    local env_locations=(
        "$HOME/dotfiles/.env"
        "$HOME/.env"
        "$HOME/repos/02_personal/dotfiles/.env"
    )

    for env_file in "${env_locations[@]}"; do
        if [[ -f "$env_file" ]]; then
            log "INFO" "Loading environment from: $env_file"
            set -a
            source "$env_file"
            set +a
            return 0
        fi
    done

    log "WARN" "No .env file found, using defaults"
    return 0
}

# Check required dependencies
check_dependencies() {
    if ! command -v jq &>/dev/null; then
        log "ERROR" "jq is required but not installed"
        return 1
    fi
    if ! command -v curl &>/dev/null; then
        log "ERROR" "curl is required but not installed"
        return 1
    fi
    return 0
}

# Cleanup on exit
cleanup() {
    sketchybar --set meeting label="" 2>/dev/null || true
}

# Get next meeting from cache
get_next_meeting() {
    # Check if meeting info was provided via environment (from popup click)
    if [[ -n "${PREP_MEETING_TITLE:-}" ]]; then
        MEETING_TITLE="$PREP_MEETING_TITLE"
        return 0
    fi

    local CACHE_FILE="$CACHE_DIR/meeting_events_list"
    if [[ ! -f "$CACHE_FILE" ]]; then
        log "ERROR" "Meeting cache not found"
        return 1
    fi

    local CURRENT_TIMESTAMP=$(date "+%s")

    while IFS= read -r event; do
        [[ -z "$event" ]] && continue
        [[ "$event" =~ ^(SYNC_STATUS|EVENTS_START|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday) ]] && continue

        local EVENT_TITLE=$(echo "$event" | cut -d'|' -f1)
        local EVENT_TIME=$(echo "$event" | cut -d'|' -f2)
        local EVENT_DATE=$(echo "$event" | cut -d'|' -f3)

        local EVENT_DATETIME="$EVENT_DATE $EVENT_TIME"
        local EVENT_TIMESTAMP=$(date -j -f "%Y-%m-%d %I:%M %p" "$EVENT_DATETIME" "+%s" 2>/dev/null)

        if [[ -n "$EVENT_TIMESTAMP" ]] && [[ $EVENT_TIMESTAMP -ge $CURRENT_TIMESTAMP ]]; then
            MEETING_TITLE="$EVENT_TITLE"
            return 0
        fi
    done < <(sed '1,/^EVENTS_START$/d' "$CACHE_FILE")

    log "WARN" "No upcoming meetings found"
    return 1
}

# Main
main() {
    log "INFO" "========== Meeting Prep Started =========="

    trap cleanup EXIT

    # Load environment and check dependencies
    load_env
    if ! check_dependencies; then
        exit 1
    fi

    # Set API URL after loading env
    JONAS_API_URL="${JONAS_API_URL:-https://jonas.ilovejeff.co}"
    log "INFO" "Using API: $JONAS_API_URL"

    # Get meeting title
    if ! get_next_meeting; then
        exit 1
    fi

    log "INFO" "Meeting: $MEETING_TITLE"

    # Build JSON payload safely with jq
    PAYLOAD=$(jq -n --arg title "$MEETING_TITLE" '{meeting: $title}')

    # Call Jonas API - capture exit code properly
    # 5 minute timeout for complex meeting preps
    log "INFO" "Calling Jonas API..."
    RESPONSE=$(curl -s -m 300 -X POST "${JONAS_API_URL}/prep" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD")
    CURL_EXIT=$?

    if [[ $CURL_EXIT -ne 0 ]]; then
        log "ERROR" "API request failed (curl exit: $CURL_EXIT)"
        exit 1
    fi

    # Validate response is valid JSON
    if ! echo "$RESPONSE" | jq -e . >/dev/null 2>&1; then
        log "ERROR" "Invalid JSON response from API"
        exit 1
    fi

    # Parse response
    SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
    if [[ "$SUCCESS" != "true" ]]; then
        ERROR=$(echo "$RESPONSE" | jq -r '.error // "Unknown error"')
        log "ERROR" "Jonas error: $ERROR"
        exit 1
    fi

    # Log duration
    DURATION=$(echo "$RESPONSE" | jq -r '.duration_ms // 0')
    log "INFO" "Jonas completed in ${DURATION}ms"

    # Cache result for debugging
    echo "$RESPONSE" > "$CACHE_DIR/last_meeting_prep_result.json"

    # Extract and open obsidian URI
    OBSIDIAN_URI=$(echo "$RESPONSE" | jq -r '.obsidian_uri // empty')
    NOTE_PATH=$(echo "$RESPONSE" | jq -r '.note_path // empty')

    # Fallback: construct URI from note_path if obsidian_uri is missing
    if [[ -z "$OBSIDIAN_URI" && -n "$NOTE_PATH" ]]; then
        # Strip /vault/ prefix and URL-encode
        RELATIVE_PATH="${NOTE_PATH#/vault/}"
        ENCODED_PATH=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$RELATIVE_PATH'))")
        OBSIDIAN_URI="obsidian://open?vault=U&file=$ENCODED_PATH"
        log "INFO" "Constructed fallback URI from note_path"
    fi

    if [[ -n "$OBSIDIAN_URI" ]]; then
        log "INFO" "Opening: $OBSIDIAN_URI"
        open "$OBSIDIAN_URI"
    else
        log "WARN" "No obsidian_uri or note_path in response - cannot open note"
    fi

    # Trigger calendar refresh
    sketchybar --trigger calendar_synced 2>/dev/null || true

    log "INFO" "========== Meeting Prep Complete =========="
}

main "$@"
