#!/usr/bin/env bash

# AI-powered meeting message generator
# Uses GPT-4o via MCP to create contextual, work-focused messages
# Messages cached for 1 hour to avoid excessive API calls

CACHE_DIR="$HOME/.cache/sketchybar"
MESSAGE_CACHE="$CACHE_DIR/meeting_ai_message"
MESSAGE_TIMESTAMP="$CACHE_DIR/meeting_ai_message_timestamp"
MESSAGE_CONTEXT="$CACHE_DIR/meeting_ai_message_context"
CACHE_DURATION=3600  # 1 hour in seconds

mkdir -p "$CACHE_DIR"

# Get current time context
get_time_context() {
    local hour=$(date +%H)
    local day=$(date +%A)
    local is_weekend=false

    if [[ "$day" == "Saturday" ]] || [[ "$day" == "Sunday" ]]; then
        is_weekend=true
    fi

    local time_of_day
    if [[ $hour -ge 6 && $hour -lt 12 ]]; then
        time_of_day="morning"
    elif [[ $hour -ge 12 && $hour -lt 18 ]]; then
        time_of_day="afternoon"
    elif [[ $hour -ge 18 && $hour -lt 22 ]]; then
        time_of_day="evening"
    else
        time_of_day="late_night"
    fi

    echo "${time_of_day}|${day}|${is_weekend}"
}

# Check if cache is valid (less than 1 hour old and same context)
is_cache_valid() {
    if [[ ! -f "$MESSAGE_CACHE" ]] || [[ ! -f "$MESSAGE_TIMESTAMP" ]] || [[ ! -f "$MESSAGE_CONTEXT" ]]; then
        return 1
    fi

    local cached_timestamp=$(cat "$MESSAGE_TIMESTAMP" 2>/dev/null || echo 0)
    local current_timestamp=$(date +%s)
    local age=$((current_timestamp - cached_timestamp))

    # Check if cache expired
    if [[ $age -ge $CACHE_DURATION ]]; then
        return 1
    fi

    # Check if context changed (different time of day)
    local cached_context=$(cat "$MESSAGE_CONTEXT" 2>/dev/null)
    local current_context=$(get_time_context)

    if [[ "$cached_context" != "$current_context" ]]; then
        return 1
    fi

    return 0
}

# Generate new AI message using GPT-4o
generate_ai_message() {
    local message_type=$1  # "free_day" or "end_of_day"
    local context=$(get_time_context)
    local time_of_day=$(echo "$context" | cut -d'|' -f1)
    local day=$(echo "$context" | cut -d'|' -f2)
    local is_weekend=$(echo "$context" | cut -d'|' -f3)

    # Build contextual prompt
    local prompt
    if [[ "$message_type" == "free_day" ]]; then
        prompt="You're a motivating assistant for a focused developer. It's $time_of_day on a $day. They have NO meetings scheduled today - a perfect opportunity for deep work. Generate ONE short, direct message (max 4-5 words) that:
- Acknowledges their free calendar
- Motivates them to use this uninterrupted time wisely
- Is direct and personal (use 'you' or imperative)
- Work-focused and action-oriented
- Slightly playful but professional

Examples of the tone:
- \"Deep work time! 🎯\"
- \"Focus mode activated\"
- \"Ship something today\"
- \"Build without interruptions\"
- \"Your canvas awaits\"

Generate ONE message only, no explanation:"
    else
        prompt="You're a motivating assistant for a focused developer. It's $time_of_day on a $day. They've COMPLETED all their meetings for today. Generate ONE short, direct message (max 4-5 words) that:
- Acknowledges they finished their meetings
- Encourages them to either wind down or keep momentum
- Is direct and personal (use 'you' or imperative)
- Work-focused but acknowledges accomplishment
- Slightly playful but professional

Examples of the tone:
- \"Meetings crushed! 💪\"
- \"Calendar: cleared ✓\"
- \"Now: focus time\"
- \"Inbox zero mindset\"
- \"Ship mode: enabled\"

Generate ONE message only, no explanation:"
    fi

    # Call GPT-4o via MCP zen chat tool (using Claude Code's MCP integration)
    # Note: This requires the zen MCP server to be configured
    local ai_message=$(claude mcp call mcp__zen__chat "{\"message\": \"$prompt\", \"model\": \"gpt-4o\"}" 2>/dev/null | grep -v "^{" | head -1)

    # Fallback if MCP fails
    if [[ -z "$ai_message" ]] || [[ "$ai_message" =~ "error" ]]; then
        if [[ "$message_type" == "free_day" ]]; then
            ai_message="Focus time! 🎯"
        else
            ai_message="Meetings done! ✓"
        fi
    fi

    # Clean up the message (remove quotes, extra whitespace)
    ai_message=$(echo "$ai_message" | sed 's/^["'"'"']//; s/["'"'"']$//' | xargs)

    echo "$ai_message"
}

# Main function
get_meeting_message() {
    local message_type=${1:-free_day}  # "free_day" or "end_of_day"

    # Check cache validity
    if is_cache_valid; then
        cat "$MESSAGE_CACHE"
        return 0
    fi

    # Generate new message
    local new_message=$(generate_ai_message "$message_type")

    # Cache the message
    echo "$new_message" > "$MESSAGE_CACHE"
    date +%s > "$MESSAGE_TIMESTAMP"
    get_time_context > "$MESSAGE_CONTEXT"

    echo "$new_message"
}

# Run main function
get_meeting_message "$@"
