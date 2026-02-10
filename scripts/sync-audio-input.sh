#!/bin/bash
# Sync audio input to match the default output display.
# When two LG UltraFine displays are connected with identical names,
# this ensures the mic always follows the main (output) display.

SWITCH="/opt/homebrew/bin/SwitchAudioSource"

# Get current default output UID
output_uid=$("$SWITCH" -c -t output -f json | /usr/bin/python3 -c "import sys,json; print(json.load(sys.stdin)['uid'])" 2>/dev/null)

if [[ -z "$output_uid" ]]; then
    exit 1
fi

# Extract the serial/port identifier (e.g., 22241000)
serial=$(echo "$output_uid" | awk -F: '{print $(NF-1)}')

if [[ -z "$serial" ]]; then
    exit 1
fi

# Get current input UID
input_uid=$("$SWITCH" -c -t input -f json | /usr/bin/python3 -c "import sys,json; print(json.load(sys.stdin)['uid'])" 2>/dev/null)

# Check if input already matches the same physical display
if echo "$input_uid" | grep -q "$serial"; then
    exit 0
fi

# Find the input device with the matching serial and set it
"$SWITCH" -t input -u "$serial:1" 2>/dev/null
