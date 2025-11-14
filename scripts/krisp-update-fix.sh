#!/bin/bash
# Krisp Automation Update & Fix Script
# Run this on each computer to ensure latest code and clean state

set -e

echo "========================================="
echo "Krisp Automation Update & Fix"
echo "========================================="
echo

# 1. Check if we're in the dotfiles repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -d "$REPO_ROOT/.git" ]; then
    echo "❌ Error: Not in dotfiles repository"
    echo "   Run this script from: ~/repos/02_personal/dotfiles/scripts/"
    exit 1
fi

echo "✓ Found dotfiles repo: $REPO_ROOT"
echo

# 2. Pull latest changes
echo "Pulling latest changes from git..."
cd "$REPO_ROOT"
git pull origin main
echo "✓ Git pull complete"
echo

# 3. Check LaunchAgent status
echo "Checking LaunchAgent status..."
AGENT_LABEL="com.user.krisp-daemon"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"

if launchctl list | grep -q "$AGENT_LABEL"; then
    echo "✓ LaunchAgent is loaded: $AGENT_LABEL"
    AGENT_LOADED=true
else
    echo "⚠ LaunchAgent not loaded"
    AGENT_LOADED=false
fi
echo

# 4. Verify script exists and has our fixes
DAEMON_SCRIPT="$HOME/.config/sketchybar/helpers/krisp-hourly-daemon.sh"
if [ ! -f "$DAEMON_SCRIPT" ]; then
    echo "❌ Error: Daemon script not found at $DAEMON_SCRIPT"
    echo "   Is the symlink created? Run: $REPO_ROOT/scripts/install.sh"
    exit 1
fi

echo "Checking for critical fixes in daemon script..."
HAS_OLD_ERROR=$(grep -c "Phase 3 Error" "$DAEMON_SCRIPT" 2>/dev/null || echo 0)
HAS_OBSIDIAN_LINK=$(grep -c "obsidian://open" "$DAEMON_SCRIPT" 2>/dev/null || echo 0)

if [ "$HAS_OLD_ERROR" -gt 0 ]; then
    echo "❌ CRITICAL: Script still has old error messages!"
    echo "   This means the symlink may be broken or pointing to old code"
    echo "   Symlink target: $(readlink $DAEMON_SCRIPT)"
    exit 1
fi

if [ "$HAS_OBSIDIAN_LINK" -eq 0 ]; then
    echo "⚠ Warning: Script missing Obsidian link feature"
    echo "  This may indicate old code - check symlinks"
else
    echo "✓ Script has latest fixes (Obsidian links present)"
fi
echo

# 5. Check Python scripts
echo "Checking Python scripts..."
PROCESS_SCRIPT="$HOME/.config/sketchybar/helpers/krisp-process-transcript.py"
if [ -f "$PROCESS_SCRIPT" ]; then
    HAS_EXIT_FIX=$(grep -c "result.get(\"skipped\")" "$PROCESS_SCRIPT" 2>/dev/null || echo 0)
    if [ "$HAS_EXIT_FIX" -gt 0 ]; then
        echo "✓ krisp-process-transcript.py has exit code fix"
    else
        echo "⚠ krisp-process-transcript.py may need update"
    fi
fi
echo

# 6. Clear corrupted cache
echo "Checking cache for corruption..."
CACHE_FILE="$HOME/.cache/sketchybar/krisp-updated-meeting-notes.json"
if [ -f "$CACHE_FILE" ]; then
    # Count entries with note_path (truly processed)
    TRULY_PROCESSED=$(python3 <<'EOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        cache = json.load(f)
    processed = [e for e in cache.get('processed_meetings', []) if 'note_path' in e]
    print(len(processed))
except:
    print(0)
EOF
"$CACHE_FILE")

    TOTAL_PROCESSED=$(python3 <<'EOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        cache = json.load(f)
    print(len(cache.get('processed_meetings', [])))
except:
    print(0)
EOF
"$CACHE_FILE")

    echo "  Cache entries: $TOTAL_PROCESSED total, $TRULY_PROCESSED with notes"

    if [ "$TOTAL_PROCESSED" -gt "$TRULY_PROCESSED" ]; then
        CORRUPT_COUNT=$((TOTAL_PROCESSED - TRULY_PROCESSED))
        echo "⚠ Found $CORRUPT_COUNT corrupted cache entries (no note_path)"
        read -p "Clean corrupted entries? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            python3 <<'EOF'
import json, sys
cache_file = sys.argv[1]
with open(cache_file) as f:
    cache = json.load(f)
cache['processed_meetings'] = [e for e in cache['processed_meetings'] if 'note_path' in e]
with open(cache_file, 'w') as f:
    json.dump(cache, f, indent=2)
print("✓ Cache cleaned")
EOF
"$CACHE_FILE"
        fi
    else
        echo "✓ Cache is clean (all entries have note_path)"
    fi
else
    echo "⚠ Cache file not found (will be created on first run)"
fi
echo

# 7. Reload LaunchAgent
if [ "$AGENT_LOADED" = true ]; then
    echo "Reloading LaunchAgent with fresh code..."
    launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>&1 | grep -v "Could not find" || true
    sleep 2
    launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"
    echo "✓ LaunchAgent reloaded"
else
    echo "Loading LaunchAgent for first time..."
    launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"
    echo "✓ LaunchAgent loaded"
fi
echo

# 8. Verify LaunchAgent is running new code
sleep 1
if launchctl list | grep -q "$AGENT_LABEL"; then
    echo "✓ LaunchAgent is now running"
    echo
    echo "Next run scheduled in: $(launchctl print gui/$(id -u)/$AGENT_LABEL | grep 'run interval' | awk '{print $4, $5}')"
else
    echo "❌ LaunchAgent failed to load - check logs:"
    echo "   tail -50 $HOME/.config/sketchybar/logs/krisp-daemon-stderr.log"
fi
echo

echo "========================================="
echo "✓ Krisp Automation Update Complete"
echo "========================================="
echo
echo "Next steps:"
echo "1. Wait for next hourly run (or trigger manually)"
echo "2. Check Telegram for success message with Obsidian links"
echo "3. Verify no more 'Phase 3 Error' messages"
echo
echo "Manual trigger: launchctl start $AGENT_LABEL"
echo "Check logs: tail -f $HOME/.config/sketchybar/logs/krisp-daemon.log"
