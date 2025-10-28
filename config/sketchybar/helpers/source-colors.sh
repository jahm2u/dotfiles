#!/bin/bash
# Helper to source environment-specific colors
# Used by both variant configs and plugins

# Source environment configuration
ENV_FILE="$HOME/.config/sketchybar/.env"
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
fi

# Source environment-specific colors (fallback to default)
ENV_TYPE_LOWER=$(echo "${ENV_TYPE:-PERSONAL}" | tr '[:upper:]' '[:lower:]')
COLOR_FILE="$HOME/.config/sketchybar/colors-${ENV_TYPE_LOWER}.sh"
if [[ -f "$COLOR_FILE" ]]; then
    source "$COLOR_FILE"
else
    source "$HOME/.config/sketchybar/colors.sh"
fi
