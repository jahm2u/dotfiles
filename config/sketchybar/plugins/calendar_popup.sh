#!/usr/bin/env bash

# Calendar Widget Popup - Shows 9-week calendar view
# Usage: Called when week_num widget is clicked
# Shows: 4 weeks behind, current week, 5 weeks ahead with week numbers

# Close all other popups first
sketchybar --set todoist popup.drawing=off \
           --set meeting popup.drawing=off \
           --set cpu popup.drawing=off \
           --set memory popup.drawing=off

# Load environment colors
source "$HOME/.config/sketchybar/helpers/source-colors.sh"

# Get current date info
CURRENT_DATE=$(date "+%Y-%m-%d")
CURRENT_DAY=$(date "+%d")
CURRENT_MONTH=$(date "+%m")
CURRENT_YEAR=$(date "+%Y")
CURRENT_WEEK=$(date "+%V")
CURRENT_DOW=$(date "+%u") # 1=Monday, 7=Sunday

# Calculate start date (4 weeks ago from start of current week)
# First, go to Monday of current week
MONDAY_OFFSET=$((CURRENT_DOW - 1))
CURRENT_MONDAY=$(date -j -v-${MONDAY_OFFSET}d "+%Y-%m-%d")

# Then go back 4 weeks (28 days)
START_DATE=$(date -j -f "%Y-%m-%d" "$CURRENT_MONDAY" -v-28d "+%Y-%m-%d")

# Function to get week number for a date
get_week_number() {
    date -j -f "%Y-%m-%d" "$1" "+%V" 2>/dev/null || echo "??"
}

# Function to check if date is current day
is_current_day() {
    local check_date="$1"
    [[ "$check_date" == "$CURRENT_DATE" ]] && echo "true" || echo "false"
}

# Function to check if date is in current week
is_current_week() {
    local check_week="$1"
    [[ "$check_week" == "$CURRENT_WEEK" ]] && echo "true" || echo "false"
}

# Function to get month name
get_month_name() {
    case "$1" in
        01) echo "Jan" ;;
        02) echo "Feb" ;;
        03) echo "Mar" ;;
        04) echo "Apr" ;;
        05) echo "May" ;;
        06) echo "Jun" ;;
        07) echo "Jul" ;;
        08) echo "Aug" ;;
        09) echo "Sep" ;;
        10) echo "Oct" ;;
        11) echo "Nov" ;;
        12) echo "Dec" ;;
    esac
}

# Generate calendar rows (9 weeks)
WEEK_INDEX=0
CURRENT_ITER_DATE="$START_DATE"
PREV_MONTH=""

for week in {0..8}; do
    # Calculate the Monday of this week
    WEEK_START=$(date -j -f "%Y-%m-%d" "$START_DATE" -v+$((week * 7))d "+%Y-%m-%d")
    WEEK_NUM=$(get_week_number "$WEEK_START")

    # Check if this is the current week
    IS_CURRENT_WEEK=$(is_current_week "$WEEK_NUM")

    # Get month for this week
    WEEK_MONTH=$(date -j -f "%Y-%m-%d" "$WEEK_START" "+%m")
    WEEK_MONTH_NAME=$(get_month_name "$WEEK_MONTH")
    WEEK_YEAR=$(date -j -f "%Y-%m-%d" "$WEEK_START" "+%Y")

    # Check if we're entering a new month
    SHOW_MONTH_HEADER="false"
    if [[ "$WEEK_MONTH" != "$PREV_MONTH" ]]; then
        SHOW_MONTH_HEADER="true"
        PREV_MONTH="$WEEK_MONTH"
    fi

    # Month header (if needed)
    if [[ "$SHOW_MONTH_HEADER" == "true" ]]; then
        item_name="calendar.popup.month_${week}"

        sketchybar --set "$item_name" \
            label="$WEEK_MONTH_NAME $WEEK_YEAR" \
            label.color="$BLUE" \
            label.font="JetBrainsMono Nerd Font:Bold:13.0" \
            icon.drawing=off \
            background.color="$TRANSPARENT" \
            drawing=on
    else
        sketchybar --set "calendar.popup.month_${week}" drawing=off
    fi

    # Week number
    item_name="calendar.popup.week_${week}"

    if [[ "$IS_CURRENT_WEEK" == "true" ]]; then
        WEEK_BG="$YELLOW"
        WEEK_LABEL_COLOR="$BLACK"
    else
        WEEK_BG="$SURFACE1"
        WEEK_LABEL_COLOR="$OVERLAY1"
    fi

    sketchybar --set "$item_name" \
        label="W$WEEK_NUM" \
        label.color="$WEEK_LABEL_COLOR" \
        label.font="JetBrainsMono Nerd Font:Bold:11.0" \
        icon.drawing=off \
        background.color="$WEEK_BG" \
        background.padding_left=5 \
        background.padding_right=5 \
        drawing=on

    # Generate 7 days for this week
    for day in {0..6}; do
        DAY_DATE=$(date -j -f "%Y-%m-%d" "$WEEK_START" -v+${day}d "+%Y-%m-%d")
        DAY_NUM=$(date -j -f "%Y-%m-%d" "$DAY_DATE" "+%d")
        DAY_MONTH=$(date -j -f "%Y-%m-%d" "$DAY_DATE" "+%m")

        item_name="calendar.popup.day_${week}_${day}"

        # Check if this is today
        IS_TODAY=$(is_current_day "$DAY_DATE")

        # Check if day is in different month (gray it out)
        if [[ "$DAY_MONTH" != "$WEEK_MONTH" ]]; then
            DAY_LABEL_COLOR="$OVERLAY0"
            DAY_BG="$TRANSPARENT"
        elif [[ "$IS_TODAY" == "true" ]]; then
            DAY_LABEL_COLOR="$BLACK"
            DAY_BG="$BLUE"
        elif [[ "$IS_CURRENT_WEEK" == "true" ]]; then
            DAY_LABEL_COLOR="$LABEL_COLOR"
            DAY_BG="$SURFACE2"
        else
            DAY_LABEL_COLOR="$LABEL_COLOR"
            DAY_BG="$TRANSPARENT"
        fi

        sketchybar --set "$item_name" \
            label="$DAY_NUM" \
            label.color="$DAY_LABEL_COLOR" \
            label.font="JetBrainsMono Nerd Font:Regular:11.0" \
            icon.drawing=off \
            background.color="$DAY_BG" \
            background.padding_left=4 \
            background.padding_right=4 \
            drawing=on
    done
done

# Toggle popup visibility
sketchybar --set week_num popup.drawing=toggle
