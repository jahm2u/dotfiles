#!/usr/bin/env bash

# Source colors
source "$HOME/.config/sketchybar/colors.sh"

# Update all aerospace workspace indicators
# This script is called by aerospace's exec-on-workspace-change

# Get the current focused workspace
CURRENT_WORKSPACE="$1"

# If no argument provided, get it from aerospace
if [ -z "$CURRENT_WORKSPACE" ]; then
    CURRENT_WORKSPACE=$(aerospace list-workspaces --focused)
fi

# Update all workspace indicators with smooth animation
# Update both the main bar and vertical bar if they exist
for bar_name in sketchybar vertical_bar; do
    # Check if the bar process is running
    if pgrep -x "$bar_name" > /dev/null; then
        for workspace in 1 2 3 4 5 6 7 8 9; do
            if [ "$workspace" = "$CURRENT_WORKSPACE" ]; then
                # Highlight the focused workspace
                $bar_name --animate tanh 10 \
                  --set space.$workspace \
                  label.color=$BLACK \
                  background.color=$GREEN
            else
                # Unhighlight other workspaces
                $bar_name --animate tanh 10 \
                  --set space.$workspace \
                  label.color=$LABEL_COLOR \
                  background.color=$BACKGROUND_LESS_TRANSPARENT
            fi
        done
    fi
done