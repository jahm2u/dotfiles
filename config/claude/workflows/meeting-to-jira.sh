#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.meeting-jira-config"
NOTES_DIR="${MEETING_NOTES_DIR:-$HOME/Documents/MeetingNotes}"
PROCESSED_FILE="$SCRIPT_DIR/.processed_meetings"
LOG_FILE="$SCRIPT_DIR/meeting-to-jira.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_dependencies() {
    local missing_deps=()
    
    command -v jq >/dev/null 2>&1 || missing_deps+=("jq")
    command -v khal >/dev/null 2>&1 || missing_deps+=("khal")
    command -v curl >/dev/null 2>&1 || missing_deps+=("curl")
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log "ERROR: Missing dependencies: ${missing_deps[*]}"
        log "Install with: brew install ${missing_deps[*]}"
        exit 1
    fi
}

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log "ERROR: Config file not found: $CONFIG_FILE"
        log "Please copy .meeting-jira-config.template to .meeting-jira-config and fill in your details"
        exit 1
    fi
    
    source "$CONFIG_FILE"
    
    if [ -z "${JIRA_URL:-}" ] || [ -z "${JIRA_EMAIL:-}" ] || [ -z "${JIRA_API_TOKEN:-}" ] || [ -z "${JIRA_PROJECT_KEY:-}" ]; then
        log "ERROR: Missing required configuration in $CONFIG_FILE"
        exit 1
    fi
}

get_todays_meetings() {
    local today=$(date '+%Y-%m-%d')
    khal list today today --format "{title}|{start-time}|{end-time}|{location}" 2>/dev/null | grep -v "^No events"
}

find_meeting_notes() {
    local meeting_title="$1"
    local meeting_date="$2"
    
    local sanitized_title=$(echo "$meeting_title" | tr '/' '-' | tr ':' '-')
    
    local possible_files=(
        "$NOTES_DIR/${meeting_date}_${sanitized_title}.md"
        "$NOTES_DIR/${meeting_date}-${sanitized_title}.md"
        "$NOTES_DIR/${sanitized_title}_${meeting_date}.md"
        "$NOTES_DIR/${sanitized_title}.md"
    )
    
    for file in "${possible_files[@]}"; do
        if [ -f "$file" ]; then
            echo "$file"
            return 0
        fi
    done
    
    return 1
}

extract_action_items() {
    local notes_file="$1"
    local action_items=()
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+\[?[[:space:]]*\]?[[:space:]]*(ACTION|TODO|TASK|@[[:alnum:]]+):?[[:space:]]+(.*) ]]; then
            action_items+=("${BASH_REMATCH[2]}")
        elif [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+.*[[:space:]]+@[[:alnum:]]+ ]]; then
            local item=$(echo "$line" | sed 's/^[[:space:]]*[-*][[:space:]]*//')
            action_items+=("$item")
        fi
    done < "$notes_file"
    
    printf '%s\n' "${action_items[@]}"
}

create_jira_ticket() {
    local summary="$1"
    local description="$2"
    local meeting_title="$3"
    local meeting_date="$4"
    
    local full_description="Generated from meeting: $meeting_title on $meeting_date\n\n$description"
    
    local json_payload=$(jq -n \
        --arg project "$JIRA_PROJECT_KEY" \
        --arg summary "$summary" \
        --arg description "$full_description" \
        --arg issueType "${JIRA_ISSUE_TYPE:-Task}" \
        --arg assignee "$JIRA_EMAIL" \
        '{
            fields: {
                project: { key: $project },
                summary: $summary,
                description: $description,
                issuetype: { name: $issueType },
                assignee: { emailAddress: $assignee }
            }
        }')
    
    local response=$(curl -s -X POST \
        -H "Authorization: Basic $(echo -n "$JIRA_EMAIL:$JIRA_API_TOKEN" | base64)" \
        -H "Content-Type: application/json" \
        "$JIRA_URL/rest/api/2/issue" \
        -d "$json_payload")
    
    local issue_key=$(echo "$response" | jq -r '.key // empty')
    
    if [ -n "$issue_key" ]; then
        log "Created Jira ticket: $issue_key - $summary"
        echo "$issue_key"
    else
        log "ERROR: Failed to create ticket for: $summary"
        log "Response: $response"
        return 1
    fi
}

mark_as_processed() {
    local notes_file="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S')|$notes_file" >> "$PROCESSED_FILE"
}

is_already_processed() {
    local notes_file="$1"
    [ -f "$PROCESSED_FILE" ] && grep -q "$notes_file" "$PROCESSED_FILE"
}

process_meeting() {
    local meeting_info="$1"
    local today=$(date '+%Y-%m-%d')
    
    IFS='|' read -r title start_time end_time location <<< "$meeting_info"
    
    log "Processing meeting: $title"
    
    local notes_file=$(find_meeting_notes "$title" "$today")
    
    if [ -z "$notes_file" ]; then
        log "No notes found for meeting: $title"
        return 0
    fi
    
    if is_already_processed "$notes_file"; then
        log "Already processed: $notes_file"
        return 0
    fi
    
    log "Found notes: $notes_file"
    
    local action_items=$(extract_action_items "$notes_file")
    
    if [ -z "$action_items" ]; then
        log "No action items found in meeting notes"
        mark_as_processed "$notes_file"
        return 0
    fi
    
    local created_tickets=()
    while IFS= read -r item; do
        if [ -n "$item" ]; then
            local ticket_key=$(create_jira_ticket "$item" "$item" "$title" "$today")
            if [ -n "$ticket_key" ]; then
                created_tickets+=("$ticket_key")
            fi
        fi
    done <<< "$action_items"
    
    if [ ${#created_tickets[@]} -gt 0 ]; then
        log "Created ${#created_tickets[@]} Jira tickets from meeting: $title"
        
        if [ "${APPEND_TICKETS_TO_NOTES:-true}" = "true" ]; then
            echo -e "\n\n## Created Jira Tickets ($(date '+%Y-%m-%d %H:%M'))" >> "$notes_file"
            for ticket in "${created_tickets[@]}"; do
                echo "- [$ticket]($JIRA_URL/browse/$ticket)" >> "$notes_file"
            done
        fi
    fi
    
    mark_as_processed "$notes_file"
}

main() {
    log "Starting meeting-to-jira workflow"
    
    check_dependencies
    load_config
    
    local meetings=$(get_todays_meetings)
    
    if [ -z "$meetings" ]; then
        log "No meetings found for today"
        exit 0
    fi
    
    while IFS= read -r meeting; do
        process_meeting "$meeting"
    done <<< "$meetings"
    
    log "Workflow completed"
}

if [ "${1:-}" = "--dry-run" ]; then
    log "DRY RUN MODE - No tickets will be created"
    DRY_RUN=true
fi

main "$@"