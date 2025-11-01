#!/usr/bin/env bash

# Calendar Widget Popup - Shows 9-week calendar view
# Simple version that actually works with BSD date

# Check if popup is already open
POPUP_STATE=$(sketchybar --query week_num | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('popup', {}).get('drawing', 'off'))")

# If already open, just close it and exit
if [[ "$POPUP_STATE" == "on" ]]; then
    sketchybar --set week_num popup.drawing=off
    exit 0
fi

# Close all other popups and show this one immediately
sketchybar --set todoist popup.drawing=off \
           --set meeting popup.drawing=off \
           --set cpu popup.drawing=off \
           --set memory popup.drawing=off \
           --set week_num popup.drawing=on

# Load environment colors
source "$HOME/.config/sketchybar/helpers/source-colors.sh"

# Get current week and date
CURRENT_WEEK=$(date "+%V")
TODAY=$(date "+%Y-%m-%d")

# Function to get full week row
get_week_row() {
    local days_offset=$1  # offset in days from today

    # Get the target date
    if [[ $days_offset -eq 0 ]]; then
        local target_date="$TODAY"
        local dow=$(date "+%u")
    elif [[ $days_offset -gt 0 ]]; then
        local target_date=$(date -v+${days_offset}d "+%Y-%m-%d")
        local dow=$(date -v+${days_offset}d "+%u")
    else
        local positive_offset=$((0 - days_offset))
        local target_date=$(date -v-${positive_offset}d "+%Y-%m-%d")
        local dow=$(date -v-${positive_offset}d "+%u")
    fi

    # Get Monday of that week
    local days_to_monday=$((dow - 1))

    if [[ $days_to_monday -eq 0 ]]; then
        local monday_offset=$days_offset
    elif [[ $days_offset -ge 0 ]]; then
        local monday_offset=$((days_offset - days_to_monday))
    else
        local monday_offset=$((days_offset - days_to_monday))
    fi

    # Get week number and month from Monday
    if [[ $monday_offset -eq 0 ]]; then
        local week_num=$(date "+%V")
        local week_month=$(date "+%m")
    elif [[ $monday_offset -gt 0 ]]; then
        local week_num=$(date -v+${monday_offset}d "+%V")
        local week_month=$(date -v+${monday_offset}d "+%m")
    else
        local positive_monday=$((0 - monday_offset))
        local week_num=$(date -v-${positive_monday}d "+%V")
        local week_month=$(date -v-${positive_monday}d "+%m")
    fi

    # Build row
    local row=$(printf "W%-2s" "$week_num")

    # Add 7 days
    for day_of_week in {0..6}; do
        local day_offset=$((monday_offset + day_of_week))

        if [[ $day_offset -eq 0 ]]; then
            local day_date=$(date "+%Y-%m-%d")
            local day_num=$(date "+%e" | tr -d ' ')
            local day_month=$(date "+%m")
        elif [[ $day_offset -gt 0 ]]; then
            local day_date=$(date -v+${day_offset}d "+%Y-%m-%d")
            local day_num=$(date -v+${day_offset}d "+%e" | tr -d ' ')
            local day_month=$(date -v+${day_offset}d "+%m")
        else
            local positive_day=$((0 - day_offset))
            local day_date=$(date -v-${positive_day}d "+%Y-%m-%d")
            local day_num=$(date -v-${positive_day}d "+%e" | tr -d ' ')
            local day_month=$(date -v-${positive_day}d "+%m")
        fi

        if [[ "$day_date" == "$TODAY" ]]; then
            row="${row}[$(printf "%2s" "$day_num")]"
        elif [[ "$day_month" != "$week_month" ]]; then
            row="${row} $(printf "%2s" "$day_num")·"
        else
            row="${row} $(printf "%2s" "$day_num") "
        fi
    done

    echo "$row|$week_num"
}

# Header
sketchybar --set week_num.popup.header \
    label="Wk  Mo Tu We Th Fr Sa Su" \
    label.color="0x60FFFFFF" \
    label.font="JetBrainsMono Nerd Font:Medium:12.0" \
    label.padding_top=14 \
    label.padding_bottom=8 \
    label.padding_left=12 \
    label.padding_right=12 \
    drawing=on

# Calculate weeks to show (-4 to +4 weeks = 9 weeks)
WEEK_INDEX=1

# Loop through each week offset
for week_offset in -4 -3 -2 -1 0 1 2 3 4; do
    days_offset=$((week_offset * 7))

    # Get week row data
    WEEK_DATA=$(get_week_row $days_offset)
    WEEK_ROW=$(echo "$WEEK_DATA" | cut -d'|' -f1)
    WEEK_NUM=$(echo "$WEEK_DATA" | cut -d'|' -f2)

    # Determine if current week
    if [[ "$WEEK_NUM" == "$CURRENT_WEEK" ]]; then
        ROW_BG="0x30FABD2F"
        ROW_LABEL_COLOR="0xFFFFFFFF"
        ROW_FONT="JetBrainsMono Nerd Font:Bold:11.0"
        ROW_CORNER_RADIUS=10
    else
        ROW_BG="$TRANSPARENT"
        ROW_LABEL_COLOR="0xCCFFFFFF"
        ROW_FONT="JetBrainsMono Nerd Font:Regular:11.0"
        ROW_CORNER_RADIUS=0
    fi

    sketchybar --set "week_num.popup.week_$WEEK_INDEX" \
        label="$WEEK_ROW" \
        label.color="$ROW_LABEL_COLOR" \
        label.font="$ROW_FONT" \
        background.color="$ROW_BG" \
        background.corner_radius=$ROW_CORNER_RADIUS \
        background.padding_left=12 \
        background.padding_right=12 \
        background.padding_top=4 \
        background.padding_bottom=4 \
        label.padding_left=4 \
        label.padding_right=4 \
        drawing=on

    WEEK_INDEX=$((WEEK_INDEX + 1))
done

# Popup already shown at the start - no need to toggle again
