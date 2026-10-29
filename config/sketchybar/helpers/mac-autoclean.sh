#!/bin/bash
# Daily cleanup of things that regenerate, or that belong to work already finished.
# Never touches worktrees, named Docker volumes or anything a running process holds;
# those stay with the disk-cleanup skill, where a human approves each one.
# Run daily by the com.user.mac-autoclean LaunchAgent (installed by scripts/install.sh,
# next to com.user.tm-snapshot-cleanup, which thins the snapshots that pin what this deletes).
# DRY_RUN=1 prints what would go and deletes nothing.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

DRY="${DRY_RUN:-0}"
LOG="$HOME/.local/share/mac-autoclean/autoclean.log"
mkdir -p "$(dirname "$LOG")"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; [ -t 1 ] && printf '%s\n' "$*"; }
free_gb() { df -g /System/Volumes/Data | awk 'NR==2{print $4}'; }
rmpath() { if [ "$DRY" = 1 ]; then log "would remove $1"; else /bin/rm -rf -- "$1"; fi; }
held() { lsof +D "$1" >/dev/null 2>&1; }

before=$(free_gb)
log "start: ${before}G free (dry=$DRY)"

# 1. Transcripts of builders whose worktree is gone, untouched for 3 days.
# The trash collector archives each builder's spec and log; the transcript is not needed.
n=0
live=$(find "$HOME/repos" -maxdepth 7 -type d -path '*/.claude/worktrees/wt-*' -prune 2>/dev/null | sed 's#.*/##')
for d in "$HOME"/.claude/projects/*worktrees-wt-*; do
  [ -d "$d" ] || continue
  wt="${d##*worktrees-}"
  printf '%s\n' "$live" | grep -qxF -- "$wt" && continue
  [ -n "$(find "$d" -mtime -3 -print -quit 2>/dev/null)" ] && continue
  rmpath "$d"; n=$((n + 1))
done
log "claude transcripts of finished builders: $n dirs"

# 2. Docker/OrbStack: build cache, images unused for 7 days, ANONYMOUS volumes only.
# `volume prune` without -a never removes a named volume (local dev databases live there).
if docker info >/dev/null 2>&1; then
  if [ "$DRY" = 1 ]; then
    log "would prune docker: $(docker system df --format '{{.Type}} {{.Reclaimable}}' | tr '\n' ';')"
  else
    docker builder prune -af --filter until=72h >/dev/null 2>&1
    docker image prune -af --filter until=168h >/dev/null 2>&1
    docker volume prune -f >/dev/null 2>&1
    log "docker pruned: $(docker system df --format '{{.Type}} {{.Size}}' | tr '\n' ';')"
  fi
fi

# 3. Expo local builds left behind (EAS deletes them only on success), older than a day.
for d in /private/var/folders/*/*/T/eas-build-local-nodejs/*; do
  [ -d "$d" ] || continue
  [ -n "$(find "$d" -maxdepth 0 -mtime -1 2>/dev/null)" ] && continue
  held "$d" && { log "eas build dir in use, kept: $d"; continue; }
  rmpath "$d"
done

# 4. Regenerating caches.
if [ "$DRY" != 1 ]; then
  npm cache clean --force >/dev/null 2>&1
  uv cache prune >/dev/null 2>&1
  xcrun simctl delete unavailable >/dev/null 2>&1
fi
find "$HOME/Library/Developer/Xcode/DerivedData" -mindepth 1 -maxdepth 1 -mtime +7 2>/dev/null | while read -r d; do rmpath "$d"; done

# 5. Dev build caches (babel-loader, webpack packs) under ~/repos. Entries untouched for 7
# days go even from a cache in daily use (admin-app's reached 15 GB that way); a cache still
# over 2 GB with no write for a day goes whole. The next build is slower once.
find "$HOME/repos" -maxdepth 8 -type d -path '*/node_modules/.cache' -prune 2>/dev/null | while read -r d; do
  if [ "$DRY" = 1 ]; then log "would prune entries >7d in $d"; else find "$d" -type f -mtime +7 -delete 2>/dev/null; fi
  [ -n "$(find "$d" -mtime -1 -print -quit 2>/dev/null)" ] && continue
  [ "$(du -sk "$d" 2>/dev/null | cut -f1)" -gt 2097152 ] && rmpath "$d"
done

# 6. Maestro test runs (logs, recordings) older than 3 days.
find "$HOME/.maestro/tests" -mindepth 1 -maxdepth 1 -type d -mtime +3 2>/dev/null | while read -r d; do rmpath "$d"; done

# 7. chrome-devtools-mcp: browser caches only, never the profile (it holds logins),
# and only while no Chrome runs on that profile.
MCP_PROFILE="$HOME/.cache/chrome-devtools-mcp/chrome-profile"
if [ -d "$MCP_PROFILE" ] && ! pgrep -f "user-data-dir=$MCP_PROFILE" >/dev/null 2>&1; then
  for c in Default/Cache "Default/Code Cache" Default/GPUCache GrShaderCache ShaderCache; do
    [ -d "$MCP_PROFILE/$c" ] && rmpath "$MCP_PROFILE/$c"
  done
fi

# 8. Chrome's on-device AI model (~4 GB). The GenAILocalFoundationalModelSettings=1
# policy stops Chrome downloading it again; delete once it is set.
if [ "$(defaults read com.google.Chrome GenAILocalFoundationalModelSettings 2>/dev/null)" = 1 ]; then
  d="$HOME/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel"
  [ -d "$d" ] && rmpath "$d"
fi

# 9. Log rotation without root: mac-monitor and sketchybar repeat a harmless macOS
# MallocStackLogging line per subprocess (sketchybar.err.log reached 4.8 GB by 2026-10-29).
for f in "$HOME/.local/share/mac-monitor/logs/stderr.log" /opt/homebrew/var/log/sketchybar/*.log "$LOG"; do
  [ -f "$f" ] || continue
  if [ "$(stat -f %z "$f")" -gt 52428800 ]; then
    [ "$DRY" = 1 ] && log "would truncate $f" || : > "$f"
  fi
done

log "done: ${before}G -> $(free_gb)G free"
exit 0
