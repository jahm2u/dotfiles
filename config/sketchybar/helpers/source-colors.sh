#!/bin/bash
# Helper to source environment-specific colors
# Used by both variant configs and plugins

# Try multiple locations to find .env file
ENV_FILE=""
for possible_location in \
    "$HOME/dotfiles/.env" \
    "$HOME/repos/02_personal/dotfiles/.env" \
    "$HOME/.config/sketchybar/../../.env" \
    "$(dirname "$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")")")/../../.env"
do
    if [[ -f "$possible_location" ]]; then
        ENV_FILE="$possible_location"
        break
    fi
done

if [[ -n "$ENV_FILE" ]] && [[ -f "$ENV_FILE" ]]; then
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
