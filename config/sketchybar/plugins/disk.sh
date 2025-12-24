#!/bin/bash

source "$HOME/.config/sketchybar/helpers/source-colors.sh"

# Get disk usage percentage for root filesystem
DISK_USAGE=$(df -h / | awk 'NR==2 {gsub(/%/,""); print $5}')

# Handle empty value
DISK_USAGE=${DISK_USAGE:-0}

# Set color based on disk usage thresholds
if [ "$DISK_USAGE" -ge 90 ]; then
    COLOR=$RED_THRESHOLD
elif [ "$DISK_USAGE" -ge 75 ]; then
    COLOR=$YELLOW_THRESHOLD
else
    COLOR=$ICON_COLOR  # Default color
fi

# Update the disk item with dynamic colors
sketchybar --set "$NAME" \
    label="${DISK_USAGE}%" \
    label.color="$COLOR" \
    icon.color="$COLOR"
