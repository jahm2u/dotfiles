#!/usr/bin/env bash

# Source environment-specific colors (not hardcoded colors.sh)
source "$HOME/.config/sketchybar/helpers/source-colors.sh"

# The workspace ID passed as argument
WORKSPACE_ID="${NAME#space.}"

# Get the current focused workspace either from environment variable or command
if [ -n "$FOCUSED_WORKSPACE" ]; then
    CURRENT_WORKSPACE="$FOCUSED_WORKSPACE"
else
    CURRENT_WORKSPACE=$(aerospace list-workspaces --focused)
fi

if [ "$WORKSPACE_ID" = "$CURRENT_WORKSPACE" ]; then
    ${BAR_NAME:-sketchybar} --animate tanh 10 \
      --set $NAME \
      label.color=$WHITE \
      background.color=$YELLOW
else
    ${BAR_NAME:-sketchybar} --animate tanh 10 \
      --set $NAME \
      label.color=$LABEL_COLOR \
      background.color=$BACKGROUND_LESS_TRANSPARENT
fi