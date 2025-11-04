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

    # Health beat: Start
    send_telegram "🤖 <b>Krisp Daemon Started</b>

<b>Time:</b> $(date '+%I:%M %p')
<b>Status:</b> Checking for new transcripts..."

    START_TIME=$(date +%s)
    DISCOVERED=0
    DOWNLOADED=0
    PENDING=0
    FAILED=0

    # Phase 1: Discovery
    log "INFO" "Phase 1: Discovering new meetings..."
    if DISCOVERY_OUTPUT=$("$VENV_PYTHON" "$SCRIPT_DIR/krisp-discover-meetings.py" --max-pages 5 2>&1 | sed -n '/^{$/,$p'); then
        DISCOVERED=$(echo "$DISCOVERY_OUTPUT" | jq -r '.discovered // 0' 2>/dev/null || echo 0)
        PENDING=$(echo "$DISCOVERY_OUTPUT" | jq -r '.pending // 0' 2>/dev/null || echo 0)
        log "INFO" "Discovery complete: $DISCOVERED meetings found, $PENDING pending download"
    else
        log "ERROR" "Discovery failed: $DISCOVERY_OUTPUT"
        send_telegram "❌ <b>Krisp Discovery Failed</b>

<b>Error:</b> Discovery phase encountered errors
<b>Check logs:</b> <code>~/.config/sketchybar/logs/krisp-daemon.log</code>"
        exit 1
    fi

    # Phase 2: Downloading (limit to 10 per hour to avoid overwhelming)
    if [ "$PENDING" -gt 0 ]; then
        log "INFO" "Phase 2: Downloading transcripts (max 10)..."
        if PROCESS_OUTPUT=$("$VENV_PYTHON" "$SCRIPT_DIR/krisp-process-queue.py" --limit 10 2>&1 | sed -n '/^{$/,$p'); then
            DOWNLOADED=$(echo "$PROCESS_OUTPUT" | jq -r '.processed // 0' 2>/dev/null || echo 0)
            FAILED=$(echo "$PROCESS_OUTPUT" | jq -r '.failed // 0' 2>/dev/null || echo 0)
            log "INFO" "Download complete: $DOWNLOADED downloaded, $FAILED failed"
        else
            log "ERROR" "Download failed: $PROCESS_OUTPUT"
            send_telegram "⚠️ <b>Krisp Download Failed</b>

<b>Discovery:</b> $DISCOVERED meetings found
<b>Error:</b> Download phase encountered errors
<b>Check logs:</b> <code>~/.config/sketchybar/logs/krisp-daemon.log</code>"
            exit 1
        fi
    else
        log "INFO" "No pending transcripts to download"
    fi

    # Phase 3: Batch processing downloaded transcripts
    PROCESSED=0
    PROCESSING_FAILED=0
    SKIPPED=0
    BATCH_DETAILS="[]"

    if [ "$DOWNLOADED" -gt 0 ]; then
        log "INFO" "Phase 3: Processing downloaded transcripts..."
        if BATCH_OUTPUT=$("$VENV_PYTHON" "$SCRIPT_DIR/krisp-batch-process.py" 2>&1); then
            # Extract JSON output (from first { to end of file)
            BATCH_JSON=$(echo "$BATCH_OUTPUT" | sed -n '/^{$/,$p')

            if [ -n "$BATCH_JSON" ]; then
                PROCESSED=$(echo "$BATCH_JSON" | jq -r '.success // 0' 2>/dev/null || echo 0)
                PROCESSING_FAILED=$(echo "$BATCH_JSON" | jq -r '.failed // 0' 2>/dev/null || echo 0)
                SKIPPED=$(echo "$BATCH_JSON" | jq -r '.skipped // 0' 2>/dev/null || echo 0)
                BATCH_DETAILS=$(echo "$BATCH_JSON" | jq -c '.details // []' 2>/dev/null || echo "[]")
                log "INFO" "Batch processing complete: $PROCESSED processed, $PROCESSING_FAILED failed, $SKIPPED skipped"
            else
                log "WARN" "Could not parse batch processing output"
            fi
        else
            log "ERROR" "Batch processing failed (non-zero exit), continuing anyway..."
            # Don't exit - processing failures shouldn't break the daemon
        fi
    else
        log "INFO" "No transcripts to process (batch phase skipped)"
    fi

    # Calculate remaining pending
    REMAINING_PENDING=$((PENDING - DOWNLOADED))
    if [ $REMAINING_PENDING -lt 0 ]; then
        REMAINING_PENDING=0
    fi

    # Calculate duration
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    # Health beat: Build enhanced Telegram message with per-file details
    if [ "$DOWNLOADED" -gt 0 ] || [ "$DISCOVERED" -gt 0 ] || [ "$PROCESSED" -gt 0 ]; then
        MESSAGE="✅ <b>Krisp Daemon Complete</b>

<b>Discovered:</b> $DISCOVERED new meetings"

        # Show download summary if any downloads occurred
        if [ "$DOWNLOADED" -gt 0 ]; then
            MESSAGE+="
<b>Downloaded:</b> $DOWNLOADED transcripts"
        fi

        # Add per-file breakdown if we have details
        if [ "$BATCH_DETAILS" != "[]" ] && [ "$PROCESSED" -gt 0 ]; then
            MESSAGE+="

<b>Processed (${PROCESSED}):</b>"

            # Build detail lines
            DETAIL_LINES=""
            DETAIL_COUNT=0
            MAX_DETAILS=10
            MAX_MESSAGE_LENGTH=3500

            # Parse details and format each entry
            while IFS= read -r detail; do
                if [ -z "$detail" ]; then
                    continue
                fi

                TITLE=$(echo "$detail" | jq -r '.title // "Unknown"')
                STATUS=$(echo "$detail" | jq -r '.status // "unknown"')
                DATE_TEXT=$(echo "$detail" | jq -r '.date_text // .date // ""')

                # Format based on status
                case "$STATUS" in
                    "success")
                        ACTION=$(echo "$detail" | jq -r '.action // "Note updated"')
                        LINE="  ✓ ${TITLE}"
                        if [ -n "$DATE_TEXT" ]; then
                            LINE+=" (${DATE_TEXT})"
                        fi
                        LINE+=" → ${ACTION}"
                        ;;
                    "failed")
                        REASON=$(echo "$detail" | jq -r '.reason // "Unknown error"')
                        LINE="  ✗ ${TITLE}"
                        if [ -n "$DATE_TEXT" ]; then
                            LINE+=" (${DATE_TEXT})"
                        fi
                        LINE+=" → ${REASON}"
                        ;;
                    "skipped")
                        REASON=$(echo "$detail" | jq -r '.reason // "Already processed"')
                        LINE="  ⊘ ${TITLE}"
                        if [ -n "$DATE_TEXT" ]; then
                            LINE+=" (${DATE_TEXT})"
                        fi
                        LINE+=" → ${REASON}"
                        ;;
                    *)
                        LINE="  ? ${TITLE}"
                        ;;
                esac

                # Check message length before adding
                TEMP_MESSAGE="${MESSAGE}${DETAIL_LINES}
${LINE}"

                if [ ${#TEMP_MESSAGE} -gt $MAX_MESSAGE_LENGTH ] || [ $DETAIL_COUNT -ge $MAX_DETAILS ]; then
                    # Calculate remaining items
                    TOTAL_DETAILS=$(echo "$BATCH_DETAILS" | jq 'length')
                    REMAINING=$((TOTAL_DETAILS - DETAIL_COUNT))
                    if [ $REMAINING -gt 0 ]; then
                        DETAIL_LINES+="
  ...and ${REMAINING} more"
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
