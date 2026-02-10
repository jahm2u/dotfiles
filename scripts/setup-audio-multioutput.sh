#!/bin/bash
# Creates a Multi-Output Device (LG Dual) from connected LG UltraFine displays
# Uses CoreAudio API via Swift - no manual Audio MIDI Setup needed

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Setting up Multi-Output Device for LG monitors..."

# Check if already exists
if /opt/homebrew/bin/SwitchAudioSource -a -t output | grep -q "LG Dual"; then
    echo "LG Dual device already exists."
    exit 0
fi

# Create via CoreAudio
swift "$SCRIPT_DIR/create-multi-output.swift"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "You can now cycle to 'LG Dual' with Ctrl+Option+Cmd+] or ["
else
    echo ""
    echo "Failed to create Multi-Output device. You can create one manually:"
    echo "  1. Open Audio MIDI Setup"
    echo "  2. Click '+' > Create Multi-Output Device"
    echo "  3. Check both LG UltraFine displays"
    echo "  4. Rename to 'LG Dual'"
fi
