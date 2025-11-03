#!/bin/bash
#
# Meeting Preparation Orchestration Script
# Triggers full workflow: classify → find person → analyze history → generate note → open in Obsidian
#

set -u

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs"
LOG_FILE="${LOG_DIR}/meeting-prep.log"
CACHE_DIR="$HOME/.cache/sketchybar"
VENV_DIR="${SCRIPT_DIR}/../venv"
PYTHON="${VENV_DIR}/bin/python3"

# Ensure directories exist
mkdir -p "$LOG_DIR" "$CACHE_DIR"

# Logging function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
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
            # Export variables from .env
            set -a
            source "$env_file"
            set +a
            return 0
        fi
    done

    log "ERROR" "No .env file found in expected locations"
    return 1
}

# Validate environment
validate_env() {
    if [[ -z "${OBSIDIAN_VAULT_PATH:-}" ]]; then
        log "ERROR" "OBSIDIAN_VAULT_PATH not set in environment"
        return 1
    fi

    if [[ ! -d "$OBSIDIAN_VAULT_PATH" ]]; then
        log "ERROR" "Vault path does not exist: $OBSIDIAN_VAULT_PATH"
        return 1
    fi

    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        log "ERROR" "OPENAI_API_KEY not set in environment"
        return 1
    fi

    if [[ ! -x "$PYTHON" ]]; then
        log "ERROR" "Python venv not found or not executable: $PYTHON"
        return 1
    fi

    return 0
}

# Loading animation function (runs in background)
animate_loading() {
    local NAME="${1:-meeting}"
    local patterns=("..." ":.." ".:." "..:")
    local i=0

    while kill -0 $MAIN_PID 2>/dev/null; do
        sketchybar --set "$NAME" label="${patterns[$i]}" 2>/dev/null || true
        i=$(( (i + 1) % 4 ))
        sleep 0.5
    done

    # Reset to normal when done
    sketchybar --set "$NAME" label="" 2>/dev/null || true
}

# Get next meeting from cache or environment
get_next_meeting() {
    # Check if meeting info was provided via environment (from popup click)
    if [[ -n "${PREP_MEETING_TITLE:-}" ]]; then
        log "INFO" "Using meeting from popup click"
        MEETING_TITLE="$PREP_MEETING_TITLE"
        MEETING_TIME="${PREP_MEETING_TIME:-}"
        MEETING_DATE="${PREP_MEETING_DATE:-$(date +%Y-%m-%d)}"
        MEETING_PARTICIPANTS="${PREP_MEETING_PARTICIPANTS:-}"
        log "INFO" "Meeting: $MEETING_TITLE at $MEETING_TIME on $MEETING_DATE"
        log "INFO" "Participants: $MEETING_PARTICIPANTS"
        return 0
    fi

    log "INFO" "Fetching next meeting from cache"

    local CACHE_FILE="$CACHE_DIR/meeting_events_list"

    if [[ ! -f "$CACHE_FILE" ]]; then
        log "ERROR" "Meeting cache not found: $CACHE_FILE"
        return 1
    fi

    # Read cache and find next meeting
    local CURRENT_TIMESTAMP=$(date "+%s")
    local NEXT_MEETING_LINE=""

    while IFS= read -r event; do
        [[ -z "$event" ]] && continue
        [[ "$event" =~ ^(SYNC_STATUS|EVENTS_START|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday) ]] && continue

        # Parse format: "Meeting Title|09:00 AM|2025-11-02|Attendees"
        local EVENT_TITLE=$(echo "$event" | cut -d'|' -f1)
        local EVENT_TIME=$(echo "$event" | cut -d'|' -f2)
        local EVENT_DATE=$(echo "$event" | cut -d'|' -f3)
        local EVENT_PARTICIPANTS=$(echo "$event" | cut -d'|' -f4)

        # Calculate event timestamp
        local EVENT_DATETIME="$EVENT_DATE $EVENT_TIME"
        local EVENT_TIMESTAMP=$(date -j -f "%Y-%m-%d %I:%M %p" "$EVENT_DATETIME" "+%s" 2>/dev/null)

        if [[ -n "$EVENT_TIMESTAMP" ]] && [[ $EVENT_TIMESTAMP -ge $CURRENT_TIMESTAMP ]]; then
            NEXT_MEETING_LINE="$event"
            break
        fi
    done < <(sed '1,/^EVENTS_START$/d' "$CACHE_FILE")

    if [[ -z "$NEXT_MEETING_LINE" ]]; then
        log "WARN" "No upcoming meetings found in cache"
        return 1
    fi

    # Parse the next meeting
    MEETING_TITLE=$(echo "$NEXT_MEETING_LINE" | cut -d'|' -f1)
    MEETING_TIME=$(echo "$NEXT_MEETING_LINE" | cut -d'|' -f2)
    MEETING_DATE=$(echo "$NEXT_MEETING_LINE" | cut -d'|' -f3)
    MEETING_PARTICIPANTS=$(echo "$NEXT_MEETING_LINE" | cut -d'|' -f4)

    log "INFO" "Next meeting: $MEETING_TITLE at $MEETING_TIME on $MEETING_DATE"
    log "INFO" "Participants: $MEETING_PARTICIPANTS"
    return 0
}

# Determine expected note path based on meeting classification
determine_note_path() {
    local CLASSIFICATION_JSON="$1"
    local PERSON_FOLDER="$2"
    local DATE="$3"

    local MEETING_TYPE=$(echo "$CLASSIFICATION_JSON" | jq -r '.meeting_type')
    local COMPANY=$(echo "$CLASSIFICATION_JSON" | jq -r '.company')

    # Mirror the logic from generate-meeting-note.py determine_save_path()
    if [[ "$MEETING_TYPE" == *"1on1"* ]]; then
        # 1-on-1: {person_folder}/Meetings/{date} 1on1.md
        echo "${PERSON_FOLDER}/Meetings/${DATE} 1on1.md"

    elif [[ "$MEETING_TYPE" == co_*_meeting ]]; then
        # Company: Business/CO/{Company}/Meetings/{date} {Company} Weekly.md
        echo "${OBSIDIAN_VAULT_PATH}/Business/CO/${COMPANY}/Meetings/${DATE} ${COMPANY} Weekly.md"

    elif [[ "$MEETING_TYPE" == *"team_"* ]]; then
        # Team: Business/People/IPMedia/Teams/{Team}/{date} {Team} Meeting.md
        local TEAM_NAME=$(echo "$MEETING_TYPE" | sed 's/ipmedia_team_//g' | sed 's/_/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
        echo "${OBSIDIAN_VAULT_PATH}/Business/People/IPMedia/Teams/${TEAM_NAME}/Meetings/${DATE} ${TEAM_NAME} Meeting.md"

    else
        # Default: {person_folder}/Meetings/{date} Meeting.md
        echo "${PERSON_FOLDER}/Meetings/${DATE} Meeting.md"
    fi
}

# Main workflow
main() {
    log "INFO" "========== Meeting Prep Workflow Started =========="

    # Start loading animation in background
    export MAIN_PID=$$
    animate_loading "meeting" &
    ANIMATION_PID=$!

    # Cleanup function
    cleanup() {
        log "INFO" "Cleaning up..."
        kill $ANIMATION_PID 2>/dev/null || true
        sketchybar --set meeting label="" 2>/dev/null || true
    }
    trap cleanup EXIT

    # Load and validate environment
    if ! load_env; then
        log "ERROR" "Failed to load environment"
        exit 1
    fi

    if ! validate_env; then
        log "ERROR" "Environment validation failed"
        exit 1
    fi

    # Get next meeting
    if ! get_next_meeting; then
        log "ERROR" "Failed to get next meeting"
        exit 1
    fi

    # Step 1: Classify meeting
    log "INFO" "Step 1: Classifying meeting"
    # Capture stderr separately to avoid contaminating JSON output
    CLASSIFICATION=$("$PYTHON" "${SCRIPT_DIR}/classify-meeting.py" \
        --title "$MEETING_TITLE" \
        --date "$MEETING_DATE" \
        --participants "$MEETING_PARTICIPANTS" 2>>"$LOG_FILE")

    if [[ $? -ne 0 ]]; then
        log "ERROR" "Classification failed"
        exit 1
    fi

    log "INFO" "Classification: $CLASSIFICATION"

    # Extract classification details
    PERSON=$(echo "$CLASSIFICATION" | jq -r '.participant')
    COMPANY=$(echo "$CLASSIFICATION" | jq -r '.company')
    MEETING_TYPE=$(echo "$CLASSIFICATION" | jq -r '.meeting_type')

    # Step 2: Find person folder
    log "INFO" "Step 2: Finding person folder for: $PERSON"
    PERSON_FOLDER=$("${SCRIPT_DIR}/find-person-folder.sh" \
        --person "$PERSON" \
        --company "$COMPANY" 2>&1)

    if [[ $? -ne 0 ]]; then
        log "ERROR" "Person folder not found: $PERSON_FOLDER"
        exit 1
    fi

    log "INFO" "Person folder: $PERSON_FOLDER"

    # Step 2.5: Check if note already exists (for past meetings)
    EXPECTED_NOTE_PATH=$(determine_note_path "$CLASSIFICATION" "$PERSON_FOLDER" "$MEETING_DATE")
    log "INFO" "Checking for existing note at: $EXPECTED_NOTE_PATH"

    if [[ -f "$EXPECTED_NOTE_PATH" ]]; then
        log "INFO" "✓ Note already exists - opening existing note instead of regenerating"
        NOTE_PATH="$EXPECTED_NOTE_PATH"

        # Calculate relative path for Obsidian
        RELATIVE_PATH="${NOTE_PATH#${OBSIDIAN_VAULT_PATH}/}"

        # Skip to opening in Obsidian
        log "INFO" "Step 5: Opening existing note in Obsidian"
        ENCODED_PATH=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$RELATIVE_PATH'))")
        open "obsidian://open?vault=U&file=$ENCODED_PATH"

        # Trigger calendar refresh
        sketchybar --trigger calendar_synced

        log "INFO" "========== Meeting Prep Workflow Complete =========="
        log "INFO" "Existing note opened in Obsidian: $NOTE_PATH"

        exit 0
    fi

    # Note doesn't exist - continue with full prep workflow
    log "INFO" "✗ Note doesn't exist - will generate new prep note"

    # Step 3: Analyze meeting history
    log "INFO" "Step 3: Analyzing meeting history"
    # Capture stderr separately to avoid contaminating JSON output
    CONTINUITY=$("$PYTHON" "${SCRIPT_DIR}/analyze-meeting-history.py" \
        --person-folder "$PERSON_FOLDER" \
        --classification "$CLASSIFICATION" 2>>"$LOG_FILE")
    ANALYSIS_EXIT=$?

    if [[ $ANALYSIS_EXIT -ne 0 ]] || [[ -z "$CONTINUITY" ]]; then
        log "WARN" "History analysis failed (may be first meeting) - exit code: $ANALYSIS_EXIT"
        # Use empty analysis for first meeting
        CONTINUITY='{
            "open_action_items": [],
            "recurring_topics": [],
            "active_blockers": [],
            "unresolved_threads": [],
            "suggested_agenda": {
                "must_discuss": ["Initial meeting - establish rapport"],
                "should_discuss": [],
                "could_discuss": []
            },
            "meeting_patterns": {"frequency_days": 0, "last_meeting_date": null}
        }'
    fi

    log "INFO" "Continuity analysis complete"

    # Step 4: Generate meeting note
    log "INFO" "Step 4: Generating meeting note"
    # Capture stderr separately to avoid contaminating JSON output
    NOTE_RESULT=$("$PYTHON" "${SCRIPT_DIR}/generate-meeting-note.py" \
        --classification "$CLASSIFICATION" \
        --person-folder "$PERSON_FOLDER" \
        --continuity "$CONTINUITY" \
        --date "$MEETING_DATE" 2>>"$LOG_FILE")

    if [[ $? -ne 0 ]]; then
        log "ERROR" "Note generation failed: $NOTE_RESULT"
        exit 1
    fi

    NOTE_PATH=$(echo "$NOTE_RESULT" | jq -r '.full_path')
    log "INFO" "Meeting note created: $NOTE_PATH"

    # Step 5: Cache result for debugging
    echo "$NOTE_RESULT" > "$CACHE_DIR/last_meeting_prep_result.json"

    # Step 6: Open in Obsidian
    log "INFO" "Step 5: Opening note in Obsidian"
    RELATIVE_PATH=$(echo "$NOTE_RESULT" | jq -r '.file_path')
    ENCODED_PATH=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$RELATIVE_PATH'))")
    open "obsidian://open?vault=U&file=$ENCODED_PATH"

    # Step 7: Trigger calendar refresh
    sketchybar --trigger calendar_synced

    log "INFO" "========== Meeting Prep Workflow Complete =========="
    log "INFO" "Note opened in Obsidian: $NOTE_PATH"

    exit 0
}

# Run main workflow
main "$@"
