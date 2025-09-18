#!/bin/bash

source "$HOME/.config/sketchybar/colors.sh"

# Get CPU usage percentage (consolidated for better performance)
CPU_USAGE=$(top -l 1 | awk '/CPU usage/ {print substr($3, 1, length($3)-1)}')

# Handle case where CPU_USAGE might be empty and round to integer
CPU_USAGE=${CPU_USAGE:-0}
CPU_USAGE=$(printf "%.0f" "$CPU_USAGE")

# Set color based on CPU usage (fixed to use rounded value)
if [ "$CPU_USAGE" -ge 80 ]; then
    COLOR=$RED
elif [ "$CPU_USAGE" -ge 60 ]; then
    COLOR=$ORANGE
elif [ "$CPU_USAGE" -ge 40 ]; then
    COLOR=$YELLOW
else
    COLOR=$GREEN
fi

# Update the CPU item (icon color is set in config, only update label)
sketchybar --set "$NAME" label="${CPU_USAGE}%"
