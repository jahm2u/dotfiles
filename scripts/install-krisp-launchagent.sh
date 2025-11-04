#!/usr/bin/env bash
#
# Install Krisp Transcript Download LaunchAgent
# Replaces HOME_DIR placeholders and installs to ~/Library/LaunchAgents/
#
# Usage: bash scripts/install-krisp-launchagent.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLIST_TEMPLATE="$DOTFILES_ROOT/config/sketchybar/launchagents/com.user.krisp-transcript-download.plist"
LAUNCHAGENT_DIR="$HOME/Library/LaunchAgents"
INSTALLED_PLIST="$LAUNCHAGENT_DIR/com.user.krisp-transcript-download.plist"

echo "=== Krisp LaunchAgent Installation ==="
echo ""

# Check if template exists
if [ ! -f "$PLIST_TEMPLATE" ]; then
    echo "❌ Error: Template not found at: $PLIST_TEMPLATE"
    exit 1
fi

# Create LaunchAgents directory if it doesn't exist
mkdir -p "$LAUNCHAGENT_DIR"

# Check if already installed
if [ -f "$INSTALLED_PLIST" ]; then
    echo "⚠️  LaunchAgent already installed: $INSTALLED_PLIST"
    read -p "Unload and reinstall? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Keeping existing installation"
        exit 0
    fi

    echo "Unloading existing LaunchAgent..."
    launchctl unload "$INSTALLED_PLIST" 2>/dev/null || true
fi

# Replace HOME_DIR placeholders with actual home directory
echo "Installing LaunchAgent..."
sed "s|HOME_DIR|$HOME|g" "$PLIST_TEMPLATE" > "$INSTALLED_PLIST"
echo "✓ Installed to: $INSTALLED_PLIST"
echo ""

# Load the LaunchAgent
echo "Loading LaunchAgent..."
launchctl load -w "$INSTALLED_PLIST"

# Verify it's running
sleep 2
if launchctl list | grep -q "com.user.krisp-transcript-download"; then
    echo "✓ LaunchAgent loaded successfully"
else
    echo "⚠️  LaunchAgent loaded but not showing in list yet (may take a moment)"
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "The Krisp download daemon will:"
echo "  - Run immediately (RunAtLoad: true)"
echo "  - Check for new transcripts every hour"
echo "  - Download up to 20 transcripts per run"
echo "  - Send Telegram notifications for each transcript"
echo ""
echo "Logs:"
echo "  stdout: ~/.config/sketchybar/logs/krisp-download-stdout.log"
echo "  stderr: ~/.config/sketchybar/logs/krisp-download-stderr.log"
echo ""
echo "Commands:"
echo "  Status:  launchctl list | grep krisp"
echo "  Unload:  launchctl unload $INSTALLED_PLIST"
echo "  Reload:  launchctl load -w $INSTALLED_PLIST"
echo "  Trigger: launchctl start com.user.krisp-transcript-download"
echo ""
echo "⚠️  IMPORTANT: Configure Telegram credentials in .env:"
echo "  TELEGRAM_BOT_TOKEN=..."
echo "  TELEGRAM_CHAT_ID=..."
echo ""
