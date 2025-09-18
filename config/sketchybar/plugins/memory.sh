#!/bin/bash

source "$HOME/.config/sketchybar/colors.sh"

# Get memory usage
MEMORY_PRESSURE=$(memory_pressure | grep "System-wide memory free percentage" | awk '{print $5}' | sed 's/%//')

# If memory_pressure doesn't work, use vm_stat as fallback
if [ -z "$MEMORY_PRESSURE" ]; then
    # Alternative method using vm_stat
    VM_STAT=$(vm_stat)
    FREE=$(echo "$VM_STAT" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
    ACTIVE=$(echo "$VM_STAT" | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
    INACTIVE=$(echo "$VM_STAT" | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
    WIRED=$(echo "$VM_STAT" | grep "Pages wired down" | awk '{print $4}' | sed 's/\.//')
    
    TOTAL_PAGES=$((FREE + ACTIVE + INACTIVE + WIRED))
    USED_PAGES=$((ACTIVE + INACTIVE + WIRED))
    
    if [ "$TOTAL_PAGES" -gt 0 ]; then
        MEMORY_USAGE=$((USED_PAGES * 100 / TOTAL_PAGES))
        # Cap at 100% to handle edge cases
        MEMORY_USAGE=$((MEMORY_USAGE > 100 ? 100 : MEMORY_USAGE))
    else
        MEMORY_USAGE=0
    fi
else
    MEMORY_USAGE=$((100 - MEMORY_PRESSURE))
fi

# Set color based on memory usage (aligned with CPU thresholds)
if [ "$MEMORY_USAGE" -ge 80 ]; then
    COLOR=$RED
elif [ "$MEMORY_USAGE" -ge 60 ]; then
    COLOR=$ORANGE
elif [ "$MEMORY_USAGE" -ge 40 ]; then
    COLOR=$YELLOW
else
    COLOR=$GREEN
fi

# Update the memory item (icon color is set in config, only update label)
sketchybar --set "$NAME" label="${MEMORY_USAGE}%"
