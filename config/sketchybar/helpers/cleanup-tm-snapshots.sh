#!/bin/bash
# Thin local Time Machine snapshots to free disk space
# Runs after Time Machine backs up to external drive

LOG_FILE="$HOME/.config/sketchybar/logs/tm-cleanup.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log "Starting Time Machine snapshot cleanup"

# Get free space before
FREE_BEFORE=$(df -h / | awk 'NR==2 {print $4}')
log "Free space before: $FREE_BEFORE"

# Thin local snapshots - keep 10GB urgency buffer
# This removes old snapshots while keeping recent ones
tmutil thinlocalsnapshots / 10000000000 4 2>&1 | while read line; do
    log "$line"
done

# Get free space after
FREE_AFTER=$(df -h / | awk 'NR==2 {print $4}')
log "Free space after: $FREE_AFTER"
log "Cleanup complete"
