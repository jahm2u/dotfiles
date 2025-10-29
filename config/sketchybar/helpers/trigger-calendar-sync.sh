#!/usr/bin/env bash

# Manual Calendar Sync Trigger
# This script provides manual triggering of calendar sync for testing/troubleshooting

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync-calendars.sh"
LAUNCHAGENT_LABEL="com.user.calendar-sync"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[SYNC]${NC} $1"
}

# Check if LaunchAgent is loaded
if launchctl list | grep -q "$LAUNCHAGENT_LABEL"; then
    info "Using LaunchAgent to trigger sync..."
    info "This mirrors the automatic sync behavior"
    launchctl start "$LAUNCHAGENT_LABEL"
    log "Sync triggered via LaunchAgent"
    log "Check logs: tail -f ~/.config/sketchybar/logs/calendar-sync-stdout.log"
else
    warn "LaunchAgent not loaded, running sync script directly..."
    if [[ -x "$SYNC_SCRIPT" ]]; then
        bash "$SYNC_SCRIPT"
        log "Sync completed directly"
    else
        echo "Error: Sync script not found or not executable: $SYNC_SCRIPT"
        exit 1
    fi
fi
