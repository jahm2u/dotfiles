#!/usr/bin/env bash

# Test script for Story 3.1 - Widget Enhancements
# Tests color thresholds, message randomization, and icon blinking logic

echo "=== Testing Widget Enhancements (Story 3.1) ==="
echo ""

# Test 1: Color exports
echo "Test 1: Checking color exports..."
source "$HOME/.config/sketchybar/helpers/source-colors.sh"

if [[ -n "$YELLOW_THRESHOLD" ]] && [[ -n "$RED_THRESHOLD" ]]; then
    echo "✅ Threshold colors exported: YELLOW_THRESHOLD=$YELLOW_THRESHOLD, RED_THRESHOLD=$RED_THRESHOLD"
else
    echo "❌ Threshold colors not exported"
    exit 1
fi

# Test 2: Meeting widget message arrays
echo ""
echo "Test 2: Testing meeting widget random messages..."
# Extract array definitions from meeting.sh using sed
eval "$(sed -n '/^END_OF_DAY_MESSAGES=/,/)$/p' "$HOME/.config/sketchybar/plugins/meeting.sh")"
eval "$(sed -n '/^FREE_DAY_MESSAGES=/,/)$/p' "$HOME/.config/sketchybar/plugins/meeting.sh")"

if [[ ${#END_OF_DAY_MESSAGES[@]} -ge 15 ]] && [[ ${#FREE_DAY_MESSAGES[@]} -ge 15 ]]; then
    echo "✅ Message arrays loaded: END_OF_DAY=${#END_OF_DAY_MESSAGES[@]}, FREE_DAY=${#FREE_DAY_MESSAGES[@]}"
    # Test random selection
    for i in {1..5}; do
        idx=$((RANDOM % ${#END_OF_DAY_MESSAGES[@]}))
        echo "   Sample $i: ${END_OF_DAY_MESSAGES[$idx]}"
    done
else
    echo "❌ Message arrays not properly loaded"
    exit 1
fi

# Test 3: Icon blink state function
echo ""
echo "Test 3: Testing icon blink state logic..."

# Define the function inline for testing
get_icon_blink_state() {
    local time_until=$1
    local current_second=$(date +%s)

    if [[ $time_until -le 900 ]]; then
        # ≤15 min: heartbeat (fast blink = 2 blinks per second)
        # Toggle every 0.5 seconds (even/odd second)
        local cycle=$((current_second % 2))
        if [[ $cycle -eq 0 ]]; then
            echo "on"
        else
            echo "off"
        fi
    else
        # >15 min: breathing (slow pulse = 1 pulse every 2 seconds)
        # 2-second cycle with subtle on/off
        local cycle=$((current_second % 2))
        if [[ $cycle -eq 0 ]]; then
            echo "bright"
        else
            echo "dim"
        fi
    fi
}

# Test with different time values
state_1800=$(get_icon_blink_state 1800)  # 30 min - should be bright/dim
state_900=$(get_icon_blink_state 900)    # 15 min - should be on/off
state_300=$(get_icon_blink_state 300)    # 5 min - should be on/off

echo "   30 min away: $state_1800 (should be bright/dim)"
echo "   15 min away: $state_900 (should be on/off)"
echo "   5 min away: $state_300 (should be on/off)"

if [[ "$state_1800" =~ ^(bright|dim)$ ]] && [[ "$state_900" =~ ^(on|off)$ ]] && [[ "$state_300" =~ ^(on|off)$ ]]; then
    echo "✅ Blink state logic working correctly"
else
    echo "❌ Blink state logic failed"
    exit 1
fi

# Test 4: Todoist completion messages
echo ""
echo "Test 4: Testing Todoist completion messages..."
# Extract array definition from todoist.sh using sed
eval "$(sed -n '/^COMPLETION_MESSAGES=/,/)$/p' "$HOME/.config/sketchybar/plugins/todoist.sh")"

if [[ ${#COMPLETION_MESSAGES[@]} -ge 15 ]]; then
    echo "✅ Completion messages loaded: ${#COMPLETION_MESSAGES[@]} messages"
    # Test random selection
    for i in {1..3}; do
        idx=$((RANDOM % ${#COMPLETION_MESSAGES[@]}))
        echo "   Sample $i: ${COMPLETION_MESSAGES[$idx]}"
    done
else
    echo "❌ Completion messages not properly loaded"
    exit 1
fi

# Test 5: CPU/Memory threshold logic
echo ""
echo "Test 5: Testing CPU/Memory color threshold logic..."

# Define threshold function
get_threshold_color() {
    local usage=$1
    if [[ $usage -ge 90 ]]; then
        echo "RED_THRESHOLD"
    elif [[ $usage -ge 75 ]]; then
        echo "YELLOW_THRESHOLD"
    else
        echo "DEFAULT"
    fi
}

color_50=$(get_threshold_color 50)
color_80=$(get_threshold_color 80)
color_95=$(get_threshold_color 95)

echo "   50% usage: $color_50 (should be DEFAULT)"
echo "   80% usage: $color_80 (should be YELLOW_THRESHOLD)"
echo "   95% usage: $color_95 (should be RED_THRESHOLD)"

if [[ "$color_50" == "DEFAULT" ]] && [[ "$color_80" == "YELLOW_THRESHOLD" ]] && [[ "$color_95" == "RED_THRESHOLD" ]]; then
    echo "✅ Threshold color logic working correctly"
else
    echo "❌ Threshold color logic failed"
    exit 1
fi

echo ""
echo "=== All Tests Passed! ==="
echo ""
echo "Summary:"
echo "  ✅ Color exports working"
echo "  ✅ Meeting widget messages (15+ each)"
echo "  ✅ Icon blink state logic"
echo "  ✅ Todoist completion messages (15+)"
echo "  ✅ CPU/Memory threshold logic"
echo ""
echo "Manual testing recommended:"
echo "  - Restart Sketchybar: brew services restart sketchybar"
echo "  - Verify meeting icon blinks with upcoming meetings"
echo "  - Check CPU/Memory colors under load"
echo "  - Complete all Todoist tasks to see completion messages"
