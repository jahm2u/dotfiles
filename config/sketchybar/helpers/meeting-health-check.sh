#!/usr/bin/env bash

# Meeting widget health check and monitoring script
# Usage:
#   ./meeting-health-check.sh              - Show current status
#   ./meeting-health-check.sh --watch      - Continuous monitoring
#   ./meeting-health-check.sh --emergency  - Emergency stop all khal processes

CACHE_DIR="$HOME/.cache/sketchybar"

show_status() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Meeting Widget Health Check - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Check khal process count
    local khal_count=$(pgrep -f "khal" | wc -l | tr -d ' ')
    if [[ $khal_count -eq 0 ]]; then
        echo "✅ khal processes: $khal_count (healthy)"
    elif [[ $khal_count -le 3 ]]; then
        echo "⚠️  khal processes: $khal_count (acceptable)"
    else
        echo "🚨 khal processes: $khal_count (CRITICAL - possible fork bomb!)"
        echo "   Run: $0 --emergency"
    fi

    # Check meeting.sh processes
    local meeting_count=$(pgrep -f "meeting.sh" | wc -l | tr -d ' ')
    echo "📝 meeting.sh instances: $meeting_count"

    # Check lock file
    if [[ -f "$CACHE_DIR/meeting_fetch.lock" ]]; then
        local lock_age=$(( $(date +%s) - $(stat -f %m "$CACHE_DIR/meeting_fetch.lock" 2>/dev/null || echo 0) ))
        if [[ $lock_age -gt 60 ]]; then
            echo "⚠️  Lock file: STALE (${lock_age}s old - will auto-clear)"
        else
            echo "🔒 Lock file: Active (${lock_age}s old)"
        fi
    else
        echo "✅ Lock file: None (healthy)"
    fi

    # Check cache files
    if [[ -f "$CACHE_DIR/meeting_events_list" ]]; then
        local cache_age=$(( $(date +%s) - $(stat -f %m "$CACHE_DIR/meeting_events_list" 2>/dev/null || echo 0) ))
        echo "💾 Event cache: Updated ${cache_age}s ago"
    else
        echo "⚠️  Event cache: Missing"
    fi

    # Check error log
    if [[ -f "$CACHE_DIR/meeting_error.log" ]]; then
        local error_count=$(wc -l < "$CACHE_DIR/meeting_error.log" | tr -d ' ')
        if [[ $error_count -gt 0 ]]; then
            echo "⚠️  Error log: $error_count errors logged"
            echo "   Last error: $(tail -1 "$CACHE_DIR/meeting_error.log")"
        fi
    fi

    # Check Sketchybar service
    if pgrep -q sketchybar; then
        echo "✅ Sketchybar: Running"
    else
        echo "🚨 Sketchybar: NOT RUNNING"
    fi

    # Show recent khal processes if any
    if [[ $khal_count -gt 0 ]]; then
        echo ""
        echo "📋 Current khal processes:"
        ps aux | grep -E "PID|khal" | grep -v grep | head -10
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

emergency_stop() {
    echo "🚨 EMERGENCY STOP TRIGGERED"
    echo "Killing all khal processes..."

    pkill -9 -f "khal"

    echo "Removing lock files..."
    rm -f "$CACHE_DIR/meeting_fetch.lock"

    echo "Clearing rate limit..."
    rm -f "$CACHE_DIR/meeting_last_run"

    local remaining=$(pgrep -f "khal" | wc -l | tr -d ' ')
    if [[ $remaining -eq 0 ]]; then
        echo "✅ All khal processes stopped"
    else
        echo "⚠️  Warning: $remaining khal processes still running"
    fi

    echo ""
    echo "Restarting Sketchybar..."
    brew services restart sketchybar

    echo "✅ Emergency stop complete"
}

watch_mode() {
    echo "👁️  Starting continuous monitoring (Ctrl+C to stop)..."
    echo ""

    while true; do
        clear
        show_status
        sleep 2
    done
}

# Main script
case "${1:-}" in
    --emergency|-e)
        emergency_stop
        ;;
    --watch|-w)
        watch_mode
        ;;
    --help|-h)
        echo "Meeting Widget Health Check"
        echo ""
        echo "Usage:"
        echo "  $0              Show current status"
        echo "  $0 --watch      Continuous monitoring"
        echo "  $0 --emergency  Emergency stop all khal processes"
        echo "  $0 --help       Show this help"
        ;;
    *)
        show_status
        ;;
esac
