#!/usr/bin/env bash
#
# Krisp Hourly Daemon - Orchestrates transcript discovery and processing
# Runs via LaunchAgent every hour with Telegram health beat notifications
#
# Author: Amelia (completing Nich's work)
# Date: 2025-11-03
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PYTHON="$HOME/.config/sketchybar/venv/bin/python3"
LOG_FILE="$HOME/.config/sketchybar/logs/krisp-daemon.log"
CACHE_DIR="$HOME/.cache/sketchybar"

# Load environment variables
if [ -f "$HOME/repos/02_personal/dotfiles/.env" ]; then
    set -a
    source "$HOME/repos/02_personal/dotfiles/.env"
    set +a
elif [ -f "$HOME/dotfiles/.env" ]; then
    set -a
    source "$HOME/dotfiles/.env"
    set +a
fi

# Logging function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

# Telegram notification function
send_telegram() {
    local message="$1"

    if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
        log "WARN" "Telegram credentials not configured - skipping notification"
        log "WARN" "Add TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID to .env to enable notifications"
        return 0
    fi

    log "INFO" "Sending Telegram notification..."
    if curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\": \"${TELEGRAM_CHAT_ID}\", \"text\": \"$message\", \"parse_mode\": \"HTML\"}" \
        >/dev/null 2>&1; then
        log "INFO" "✓ Telegram notification sent"
    else
        log "WARN" "✗ Telegram notification failed (check credentials or network)"
    fi
}

# Main execution
main() {
    log "INFO" "========================================="
    log "INFO" "Krisp Daemon Starting (Hourly Run)"
    log "INFO" "========================================="

    # Removed "Started" telegram message per user request

    START_TIME=$(date +%s)
    DISCOVERED=0
    DOWNLOADED=0
    NOT_READY=0
    PENDING=0
    FAILED=0

    # Phase 1: Discovery & Download (simplified script - first 20 meetings)
    log "INFO" "Phase 1: Discovering and downloading transcripts..."

    # Capture output to temp file and display simultaneously
    TEMP_OUTPUT=$(mktemp)
    if "$VENV_PYTHON" "$SCRIPT_DIR/krisp-download-transcripts-simple.py" --limit 20 2>&1 | tee "$TEMP_OUTPUT" | tee -a "$LOG_FILE"; then
        # Extract stats from captured output (BSD grep compatible)
        # Extract only the number after "Found" and "meetings"
        DISCOVERED=$(grep 'Found.*meetings on page' "$TEMP_OUTPUT" | tail -1 | sed -E 's/.*Found ([0-9]+) meetings.*/\1/' || echo 0)
        DOWNLOADED=$(grep 'Successfully downloaded:' "$TEMP_OUTPUT" | tail -1 | grep -Eo '[0-9]+/[0-9]+' | cut -d'/' -f1 || echo 0)
        NOT_READY=$(grep 'Not ready:' "$TEMP_OUTPUT" | tail -1 | grep -Eo '[0-9]+/[0-9]+' | cut -d'/' -f1 || echo 0)
        FAILED=$(grep 'Errors:' "$TEMP_OUTPUT" | tail -1 | grep -Eo '[0-9]+/[0-9]+' | cut -d'/' -f1 || echo 0)
        rm -f "$TEMP_OUTPUT"
        log "INFO" "Discovery & download complete: $DISCOVERED discovered, $DOWNLOADED downloaded, $NOT_READY not ready, $FAILED failed"
    else
        rm -f "$TEMP_OUTPUT"
        log "ERROR" "Discovery & download failed"
        send_telegram "❌ <b>Krisp Discovery & Download Failed</b>

<b>Error:</b> Phase encountered errors
<b>Check logs:</b> <code>~/.config/sketchybar/logs/krisp-daemon.log</code>"
        exit 1
    fi

    # Check for pending transcripts (either newly downloaded or previously unprocessed)
    PENDING_TRANSCRIPTS=$(ls -1 "$HOME/.config/sketchybar/krisp-transcripts"/*.txt 2>/dev/null | wc -l | tr -d ' ')

    # Phase 2: Create enhanced processing queue with calendar matching
    # Always create queue to check for any pending transcripts (new or existing)
    log "INFO" "Phase 2: Creating enhanced processing queue with calendar matching..."
    if "$VENV_PYTHON" "$SCRIPT_DIR/krisp-create-queue-enhanced.py" 2>&1 | tee -a "$LOG_FILE"; then
        log "INFO" "Enhanced queue created with calendar matching"

        # Check if queue has items to process
        if [ -f "$CACHE_DIR/krisp-pending-downloads.json" ]; then
            QUEUE_COUNT=$(jq -r '.total // 0' "$CACHE_DIR/krisp-pending-downloads.json" 2>/dev/null || echo 0)
            log "INFO" "Queue contains $QUEUE_COUNT meetings"
        fi
    else
        log "WARN" "Enhanced queue creation failed, trying simple fallback..."
        # Fallback to simple queue creator
        if "$VENV_PYTHON" "$SCRIPT_DIR/krisp-create-queue-from-transcripts.py" 2>&1 | tee -a "$LOG_FILE"; then
            log "INFO" "Simple queue created (without calendar matching)"
        else
            log "ERROR" "Failed to create any queue file"
        fi
    fi

    # Phase 3: Batch processing transcripts
    PROCESSED=0
    PROCESSING_FAILED=0
    SKIPPED=0
    BATCH_DETAILS="[]"

    # Ensure archive directory exists
    ARCHIVE_DIR="$HOME/.config/sketchybar/krisp-transcripts/processed"
    mkdir -p "$ARCHIVE_DIR"

    # Use queue count from Phase 2 (if available) or check for transcripts
    QUEUE_COUNT=${QUEUE_COUNT:-$PENDING_TRANSCRIPTS}

    if [ "$QUEUE_COUNT" -gt 0 ]; then
        log "INFO" "Phase 3: Processing $QUEUE_COUNT queued meetings..."
        if BATCH_OUTPUT=$("$VENV_PYTHON" "$SCRIPT_DIR/krisp-batch-process.py" 2>&1); then
            # Extract JSON output (from first { to end of file)
            BATCH_JSON=$(echo "$BATCH_OUTPUT" | sed -n '/^{$/,$p')

            if [ -n "$BATCH_JSON" ]; then
                PROCESSED=$(echo "$BATCH_JSON" | jq -r '.success // 0' 2>/dev/null || echo 0)
                PROCESSING_FAILED=$(echo "$BATCH_JSON" | jq -r '.failed // 0' 2>/dev/null || echo 0)
                SKIPPED=$(echo "$BATCH_JSON" | jq -r '.skipped // 0' 2>/dev/null || echo 0)
                BATCH_DETAILS=$(echo "$BATCH_JSON" | jq -c '.details // []' 2>/dev/null || echo "[]")
                log "INFO" "Batch processing complete: $PROCESSED processed, $PROCESSING_FAILED failed, $SKIPPED skipped"

                # Archive successfully processed transcripts
                if [ "$PROCESSED" -gt 0 ]; then
                    log "INFO" "Moving $PROCESSED processed transcripts to archive..."
                    # Extract successfully processed file IDs and move them
                    echo "$BATCH_DETAILS" | jq -r '.[] | select(.status == "success") | .meeting_id // empty' | while read -r meeting_id; do
                        if [ -n "$meeting_id" ]; then
                            # Move both .txt and .json files if they exist
                            for ext in txt json; do
                                SOURCE_FILE="$HOME/.config/sketchybar/krisp-transcripts/krisp-transcript-${meeting_id}.${ext}"
                                if [ -f "$SOURCE_FILE" ]; then
                                    mv "$SOURCE_FILE" "$ARCHIVE_DIR/" 2>/dev/null && \
                                        log "INFO" "  Archived: krisp-transcript-${meeting_id}.${ext}"
                                fi
                            done
                        fi
                    done
                fi
            else
                log "WARN" "Could not parse batch processing output"
            fi
        else
            log "ERROR" "Batch processing failed (non-zero exit), continuing anyway..."
            # Don't exit - processing failures shouldn't break the daemon
        fi
    else
        log "INFO" "No pending transcripts to process (batch phase skipped)"
    fi

    # Calculate remaining pending
    REMAINING_PENDING=$((PENDING - DOWNLOADED))
    if [ $REMAINING_PENDING -lt 0 ]; then
        REMAINING_PENDING=0
    fi

    # Check for person_not_found errors
    PERSON_NOT_FOUND_ERRORS=""
    if [ "$BATCH_DETAILS" != "[]" ]; then
        PERSON_NOT_FOUND_ERRORS=$(echo "$BATCH_DETAILS" | jq -r '.[] | select(.status == "failed" and (.reason // "" | contains("person_not_found"))) | "\(.details.person // "Unknown") (\(.details.company // "Unknown Company"))"' | sort -u)
    fi

    # Calculate duration
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    # Health beat: Only send notification if actual new work was done (not re-downloads)
    # Send telegram if: new downloads + successfully processed, OR processing failures
    if [ "$PROCESSED" -gt 0 ] || [ "$PROCESSING_FAILED" -gt 0 ]; then
        MESSAGE="✅ <b>Krisp Processing Complete</b>"

        # Show download summary if any downloads occurred
        if [ "$DOWNLOADED" -gt 0 ]; then
            MESSAGE+="

<b>Downloaded:</b> $DOWNLOADED new transcripts"
        fi

        # Add per-file breakdown if we have details
        if [ "$BATCH_DETAILS" != "[]" ] && [ "$PROCESSED" -gt 0 ]; then
            MESSAGE+="

<b>Processed (${PROCESSED}):</b>"

            # Build detail lines
            DETAIL_LINES=""
            DETAIL_COUNT=0
            MAX_MESSAGE_LENGTH=3500

            # Parse details and format each entry (only show successful items in detail)
            while IFS= read -r detail; do
                if [ -z "$detail" ]; then
                    continue
                fi

                TITLE=$(echo "$detail" | jq -r '.title // "Unknown"')
                STATUS=$(echo "$detail" | jq -r '.status // "unknown"')
                DATE_TEXT=$(echo "$detail" | jq -r '.date_text // .date // ""')

                # Skip non-success items (they're shown in summary counts)
                if [ "$STATUS" != "success" ]; then
                    continue
                fi

                # Format successful items
                ACTION=$(echo "$detail" | jq -r '.action // "Note updated"')
                LINE="  ✓ ${TITLE}"
                if [ -n "$DATE_TEXT" ]; then
                    LINE+=" (${DATE_TEXT})"
                fi
                LINE+=" → ${ACTION}"

                # Check message length before adding (only length limit, no item count limit)
                TEMP_MESSAGE="${MESSAGE}${DETAIL_LINES}
${LINE}"

                if [ ${#TEMP_MESSAGE} -gt $MAX_MESSAGE_LENGTH ]; then
                    # Hit message length limit (Telegram limit is 4096 chars)
                    TOTAL_DETAILS=$(echo "$BATCH_DETAILS" | jq 'length')
                    REMAINING=$((TOTAL_DETAILS - DETAIL_COUNT))
                    if [ $REMAINING -gt 0 ]; then
                        DETAIL_LINES+="
  ...and ${REMAINING} more (message too long)"
                    fi
                    break
                fi

                DETAIL_LINES+="
${LINE}"
                ((DETAIL_COUNT++))

            done < <(echo "$BATCH_DETAILS" | jq -c '.[]')

            MESSAGE+="$DETAIL_LINES"
        fi

        # Show failures if any
        if [ "$PROCESSING_FAILED" -gt 0 ]; then
            MESSAGE+="

<b>Failed:</b> ${PROCESSING_FAILED}"

            # Add detailed failure breakdown if available
            if [ "$BATCH_DETAILS" != "[]" ]; then
                FAILED_DETAILS=$(echo "$BATCH_DETAILS" | jq -r '.[] | select(.status == "failed") | "  ✗ \"\(.title // "Unknown")\" → \(.reason // "Unknown error")"' 2>/dev/null | head -5)

                if [ -n "$FAILED_DETAILS" ]; then
                    MESSAGE+="

<b>Failure Details:</b>
$FAILED_DETAILS"

                    # Show "and N more" if we truncated
                    TOTAL_FAILED=$(echo "$BATCH_DETAILS" | jq '[.[] | select(.status == "failed")] | length' 2>/dev/null)
                    if [ "$TOTAL_FAILED" -gt 5 ]; then
                        REMAINING_FAILED=$((TOTAL_FAILED - 5))
                        MESSAGE+="
  ...and ${REMAINING_FAILED} more"
                    fi
                fi
            fi
        fi

        # Show skipped if any
        if [ "$SKIPPED" -gt 0 ]; then
            MESSAGE+="

<b>Skipped:</b> ${SKIPPED} (already processed)"
        fi

        # Show download failures if any
        if [ "$FAILED" -gt 0 ]; then
            MESSAGE+="

<b>Download Failed:</b> ${FAILED}"
        fi

        # Show person_not_found warnings with actionable instructions
        if [ -n "$PERSON_NOT_FOUND_ERRORS" ]; then
            MESSAGE+="

⚠️ <b>Missing Person Folders:</b>
The following participants need folders created:
$PERSON_NOT_FOUND_ERRORS

<i>Create folders at:
\$VAULT/Business/People/{Company}/{Person}/Meetings/</i>"
        fi

        # Add summary footer
        MESSAGE+="

<b>Still Pending:</b> $REMAINING_PENDING
<b>Duration:</b> ${DURATION}s
<b>Next run:</b> In 1 hour"

        send_telegram "$MESSAGE"
    fi

    log "INFO" "========================================="
    log "INFO" "Daemon complete: $PROCESSED processed, $REMAINING_PENDING remaining"
    log "INFO" "========================================="
}

# Execute
main "$@"
