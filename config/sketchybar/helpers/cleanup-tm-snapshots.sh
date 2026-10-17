#!/bin/bash
# Thin local Time Machine snapshots to free disk space. Runs hourly (LaunchAgent).
#
# Why hourly and not on backup completion: the old WatchPaths trigger
# (/var/db/.TimeMachine.Results.plist) no longer exists on macOS 26, so the agent
# never fired and 21 snapshots pinned ~87 GB of deleted worktrees and caches.
#
# Local snapshots cannot be disabled while Time Machine is on, and they are whole-volume
# APFS snapshots (backup exclusions do not shrink them). They only duplicate what the
# external backup already holds, so when that backup is recent we thin them hard. When
# the backup drive has been away for a day, they are the only safety net: thin gently.

LOG_FILE="$HOME/.config/sketchybar/logs/tm-cleanup.log"
NOTIFY_STAMP="$HOME/.cache/sketchybar/disk-low-notified"
BACKUP_FRESH_HOURS=24
LOW_SPACE_GB=40

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

free_gb() {
    df -g /System/Volumes/Data | awk 'NR==2 {print $4}'
}

log "Starting Time Machine snapshot cleanup"
FREE_BEFORE=$(free_gb)

# Age of the latest completed external backup. `tmutil latestbackup` returns nothing under
# launchd (no Full Disk Access), but the world-readable prefs list completed backups in local
# time, e.g. "Sat Oct 17 07:32:06 -03 2026". Drop the zone token and parse as local time.
LATEST=$(/usr/libexec/PlistBuddy -c "Print :Destinations:0:SnapshotDates" \
    /Library/Preferences/com.apple.TimeMachine.plist 2>/dev/null | grep -E '[0-9]{4}$' | tail -1 |
    awk '{print $1, $2, $3, $4, $6}')
AGE_HOURS=""
if [[ -n "$LATEST" ]]; then
    LATEST_EPOCH=$(date -j -f '%a %b %d %T %Y' "$LATEST" +%s 2>/dev/null)
    [[ -n "$LATEST_EPOCH" ]] && AGE_HOURS=$(( ($(date +%s) - LATEST_EPOCH) / 3600 ))
fi

if [[ -n "$AGE_HOURS" && "$AGE_HOURS" -lt "$BACKUP_FRESH_HOURS" ]]; then
    PURGE_BYTES=999999999999   # as much as possible; tmutil keeps the newest few
    log "Latest backup ${AGE_HOURS}h old: thinning all redundant snapshots"
else
    PURGE_BYTES=10000000000    # 10 GB
    log "Latest backup ${AGE_HOURS:-unknown}h old: gentle thin only"
fi

tmutil thinlocalsnapshots / "$PURGE_BYTES" 4 2>&1 | while read -r line; do
    log "$line"
done

FREE_AFTER=$(free_gb)
log "Free space: ${FREE_BEFORE}G -> ${FREE_AFTER}G"

# Nudge toward /disk-cleanup when thinning was not enough. At most once a day.
if [[ "$FREE_AFTER" -lt "$LOW_SPACE_GB" ]]; then
    if [[ ! -f "$NOTIFY_STAMP" ]] || [[ $(( $(date +%s) - $(stat -f %m "$NOTIFY_STAMP") )) -gt 86400 ]]; then
        mkdir -p "$(dirname "$NOTIFY_STAMP")" && touch "$NOTIFY_STAMP"
        osascript -e "display notification \"Only ${FREE_AFTER} GB free. Run /disk-cleanup in Claude Code.\" with title \"Disk low\""
        log "Low space notification sent"
    fi
fi

log "Cleanup complete"
