#!/bin/bash

source "$HOME/.config/sketchybar/helpers/source-colors.sh"

# Get CPU usage percentage (consolidated for better performance)
CPU_USAGE=$(top -l 1 | awk '/CPU usage/ {print substr($3, 1, length($3)-1)}')

# Handle case where CPU_USAGE might be empty and round to integer
CPU_USAGE=${CPU_USAGE:-0}
CPU_USAGE=$(printf "%.0f" "$CPU_USAGE")

# Set color based on CPU usage thresholds (Story 3.1)
if [ "$CPU_USAGE" -ge 90 ]; then
    COLOR=$RED_THRESHOLD
elif [ "$CPU_USAGE" -ge 75 ]; then
    COLOR=$YELLOW_THRESHOLD
else
    COLOR=$ICON_COLOR  # Default color
fi

# Update the CPU item with dynamic colors
sketchybar --set "$NAME" \
    label="${CPU_USAGE}%" \
    label.color="$COLOR" \
    icon.color="$COLOR"
