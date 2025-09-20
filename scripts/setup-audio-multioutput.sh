#!/bin/bash

echo "Setting up Multi-Output Device for LG monitors..."
echo ""
echo "This script will guide you through creating a Multi-Output Device in Audio MIDI Setup."
echo ""
echo "MANUAL SETUP REQUIRED:"
echo "======================"
echo "1. Opening Audio MIDI Setup..."
open -a "Audio MIDI Setup"

echo ""
echo "2. In Audio MIDI Setup, please:"
echo "   a) Click the '+' button at the bottom left"
echo "   b) Select 'Create Multi-Output Device'"
echo "   c) In the right panel, check both 'LG UltraFine Display Audio' devices"
echo "   d) Optionally rename it to 'LG Dual Output' (right-click > Rename)"
echo ""
echo "3. Once done, close Audio MIDI Setup"
echo ""
echo "Press Enter when you've completed the setup..."
read -r

echo ""
echo "Verifying setup..."
if /opt/homebrew/bin/SwitchAudioSource -a | grep -E "(Multi-Output Device|LG Dual Output)" > /dev/null; then
    echo "✅ Multi-Output Device found!"
    echo ""
    echo "You can now use Ctrl+Option+Cmd+[ in Hammerspoon to toggle audio output."
else
    echo "⚠️  Multi-Output Device not found. Please try the manual setup again."
fi