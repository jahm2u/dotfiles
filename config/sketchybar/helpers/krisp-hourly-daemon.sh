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

    # Phase 2: Processing (limit to 10 per hour to avoid overwhelming)
    if [ "$PENDING" -gt 0 ]; then
        log "INFO" "Phase 2: Downloading transcripts (max 10)..."
        if PROCESS_OUTPUT=$("$VENV_PYTHON" "$SCRIPT_DIR/krisp-process-queue.py" --limit 10 2>&1 | sed -n '/^{$/,$p'); then
            DOWNLOADED=$(echo "$PROCESS_OUTPUT" | jq -r '.processed // 0' 2>/dev/null || echo 0)
            FAILED=$(echo "$PROCESS_OUTPUT" | jq -r '.failed // 0' 2>/dev/null || echo 0)
            log "INFO" "Processing complete: $DOWNLOADED downloaded, $FAILED failed"
        else
            log "ERROR" "Processing failed: $PROCESS_OUTPUT"
            send_telegram "⚠️ <b>Krisp Processing Failed</b>

<b>Discovery:</b> $DISCOVERED meetings found
<b>Error:</b> Download phase encountered errors
<b>Check logs:</b> <code>~/.config/sketchybar/logs/krisp-daemon.log</code>"
            exit 1
        fi
    else
        log "INFO" "No pending transcripts to process"
    fi

    # Calculate remaining pending
    REMAINING_PENDING=$((PENDING - DOWNLOADED))
    if [ $REMAINING_PENDING -lt 0 ]; then
        REMAINING_PENDING=0
    fi

    # Calculate duration
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    # Health beat: Complete
    if [ "$DOWNLOADED" -gt 0 ] || [ "$DISCOVERED" -gt 0 ]; then
        send_telegram "✅ <b>Krisp Daemon Complete</b>

<b>Discovered:</b> $DISCOVERED new meetings
<b>Downloaded:</b> $DOWNLOADED transcripts
<b>Failed:</b> $FAILED
<b>Still Pending:</b> $REMAINING_PENDING
<b>Duration:</b> ${DURATION}s

<b>Next run:</b> In 1 hour"
    fi

    log "INFO" "========================================="
    log "INFO" "Daemon complete: $DOWNLOADED downloaded, $REMAINING_PENDING remaining"
    log "INFO" "========================================="
}

# Execute
main "$@"
