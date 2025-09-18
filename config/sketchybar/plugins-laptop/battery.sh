#!/usr/bin/env sh

# Battery is here bcause the ICON_COLOR doesn't play well with all background colors
source "$HOME/.config/sketchybar/colors.sh"

PERCENTAGE=$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)
CHARGING=$(pmset -g batt | grep 'AC Power')

if [ $PERCENTAGE = "" ]; then
    exit 0
fi

case ${PERCENTAGE} in
[8-9][0-9] | 100)
    ICON=""
    ICON_COLOR=$GREEN
    ;;
7[0-9])
    ICON=""
    ICON_COLOR=$GREEN
    ;;
[4-6][0-9])
    ICON=""
    ICON_COLOR=$GREEN
    ;;
[1-3][0-9])
    ICON=""
    ICON_COLOR=$GREEN
    ;;
[0-9])
    ICON=""
    ICON_COLOR=$GREEN
    ;;
esac

if [[ $CHARGING != "" ]]; then
    ICON=""
    ICON_COLOR=$GREEN
fi

sketchybar --set $NAME \
    icon=$ICON \
    label="${PERCENTAGE}%" \
    icon.color=${ICON_COLOR}
