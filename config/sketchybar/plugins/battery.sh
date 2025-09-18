#!/usr/bin/env zsh

source "$HOME/.config/sketchybar/colors.sh"

PERCENTAGE="$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)"
CHARGING="$(pmset -g batt | grep 'AC Power')"

if [ "$PERCENTAGE" = "" ]; then
  exit 0
fi

# Set icon and color based on charging status and percentage
if [[ "$CHARGING" != "" ]]; then
    # Charging - use charging icon
    ICON="󰂄"
    COLOR=$TEAL  # Match your theme
elif [[ $PERCENTAGE -le 10 ]]; then
    # Critical battery
    ICON="󰂃"
    COLOR=$RED
elif [[ $PERCENTAGE -le 20 ]]; then
    # Low battery
    ICON="󰁺"
    COLOR=$YELLOW
elif [[ $PERCENTAGE -le 40 ]]; then
    ICON="󰁾"
    COLOR=$PEACH  # Match your volume widget color
elif [[ $PERCENTAGE -le 60 ]]; then
    ICON="󰂀"
    COLOR=$PEACH
elif [[ $PERCENTAGE -le 80 ]]; then
    ICON="󰂂"
    COLOR=$PEACH
else
    # Full battery
    ICON="󰁹"
    COLOR=$PEACH
fi

# Match the volume widget style exactly
sketchybar --set $NAME icon=$ICON icon.color=$COLOR label="$PERCENTAGE%"
