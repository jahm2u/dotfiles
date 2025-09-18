#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract data from JSON input
model_name=$(echo "$input" | jq -r '.model.display_name // .model.id')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
session_id=$(echo "$input" | jq -r '.session_id')

# Get directory name (last component of path)
dir_name=$(basename "$current_dir")

# Get git branch (suppress errors if not in git repo)
git_branch=$(cd "$current_dir" 2>/dev/null && git branch --show-current 2>/dev/null || echo "no-git")

# Calculate time until 5-hour session block reset
calculate_countdown() {
    # Default to 5h0m if no active session found
    local default_time="5h0m"
    
    # Find all entries from Claude projects
    local claude_dir="$HOME/.claude"
    local projects_dir="$claude_dir/projects"
    
    # Check if projects directory exists
    if [ ! -d "$projects_dir" ]; then
        echo "$default_time"
        return
    fi
    
    # Get current time and calculate cutoff (96 hours ago)
    local now_epoch=$(date +%s)
    local cutoff_epoch=$((now_epoch - 345600))  # 96 hours = 345600 seconds
    
    # Collect all entries from last 96 hours
    local temp_file=$(mktemp)
    
    # Find all .jsonl files recursively and process them
    find "$projects_dir" -name "*.jsonl" -type f 2>/dev/null | while read -r jsonl_file; do
        # Process each line in the JSONL file
        while IFS= read -r line; do
            # Skip empty lines
            [ -z "$line" ] && continue
            
            # Extract ISO 8601 timestamp using jq if available, otherwise use sed/grep
            if command -v jq >/dev/null 2>&1; then
                local timestamp=$(echo "$line" | jq -r '.timestamp // empty' 2>/dev/null)
            else
                # Fallback: extract ISO 8601 timestamp field value
                local timestamp=$(echo "$line" | grep -o '"timestamp":"[^"]*"' | sed 's/"timestamp":"\([^"]*\)"/\1/')
            fi
            
            # Skip if no timestamp found
            [ -z "$timestamp" ] && continue
            
            # Convert ISO 8601 timestamp to Unix epoch seconds
            local epoch_time
            if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
                # Handle legacy numeric timestamps (milliseconds or seconds)
                if [ "$timestamp" -gt 1000000000000 ]; then
                    epoch_time=$((timestamp / 1000))
                else
                    epoch_time=$timestamp
                fi
            else
                # Handle ISO 8601 timestamps like "2025-09-07T18:19:17.844Z"
                # Use date command to convert to epoch (handle both macOS and Linux)
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    # macOS date command - strip milliseconds and handle timezone
                    local clean_timestamp="${timestamp%.*}"  # Remove milliseconds
                    clean_timestamp="${clean_timestamp%Z}"    # Remove Z if present
                    epoch_time=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$clean_timestamp" "+%s" 2>/dev/null)
                else
                    # Linux date command
                    epoch_time=$(date -d "$timestamp" +%s 2>/dev/null)
                fi
                
                # If date conversion failed, skip this entry
                [ -z "$epoch_time" ] && continue
            fi
            
            # Only include entries from last 96 hours
            if [ "$epoch_time" -ge "$cutoff_epoch" ]; then
                echo "$epoch_time" >> "$temp_file"
            fi
        done < "$jsonl_file"
    done
    
    # If no entries found, return default
    if [ ! -s "$temp_file" ]; then
        rm -f "$temp_file"
        echo "$default_time"
        return
    fi
    
    # Sort timestamps and create session blocks
    sort -n "$temp_file" > "${temp_file}.sorted"
    rm -f "$temp_file"
    
    # Create 5-hour session blocks
    local blocks_file=$(mktemp)
    local current_block_start=""
    local current_block_end=""
    local previous_timestamp=""
    
    while read -r timestamp; do
        # Skip if timestamp is empty
        [ -z "$timestamp" ] && continue
        
        # If this is the first timestamp or we need a new block
        if [ -z "$current_block_start" ] || \
           [ "$timestamp" -ge "$current_block_end" ] || \
           ([ -n "$previous_timestamp" ] && [ $((timestamp - previous_timestamp)) -ge 18000 ]); then
            
            # Save previous block if it exists
            if [ -n "$current_block_start" ]; then
                echo "$current_block_start $current_block_end" >> "$blocks_file"
            fi
            
            # Start new block - align to hour of first message
            local block_start_hour=$(( (timestamp / 3600) * 3600 ))
            current_block_start=$block_start_hour
            current_block_end=$((block_start_hour + 18000))  # 5 hours later
        fi
        
        previous_timestamp=$timestamp
    done < "${temp_file}.sorted"
    
    # Don't forget the last block
    if [ -n "$current_block_start" ]; then
        echo "$current_block_start $current_block_end" >> "$blocks_file"
    fi
    
    rm -f "${temp_file}.sorted"
    
    # Find active block (where end_time > current_time)
    local active_block_end=""
    local most_recent_block_end=""
    
    while read -r block_start block_end; do
        # Skip empty lines
        [ -z "$block_start" ] && continue
        
        # Track most recent block
        if [ -z "$most_recent_block_end" ] || [ "$block_end" -gt "$most_recent_block_end" ]; then
            most_recent_block_end=$block_end
        fi
        
        # Check if block is still active
        if [ "$block_end" -gt "$now_epoch" ]; then
            active_block_end=$block_end
            break
        fi
    done < "$blocks_file"
    
    rm -f "$blocks_file"
    
    # Use active block if found, otherwise use most recent block
    local target_block_end
    if [ -n "$active_block_end" ]; then
        target_block_end=$active_block_end
    elif [ -n "$most_recent_block_end" ]; then
        target_block_end=$most_recent_block_end
    else
        echo "$default_time"
        return
    fi
    
    # Calculate countdown
    local seconds_until_reset=$((target_block_end - now_epoch))
    
    # If block has expired, return default
    if [ $seconds_until_reset -le 0 ]; then
        echo "$default_time"
        return
    fi
    
    # Convert to hours and minutes
    local hours=$((seconds_until_reset / 3600))
    local minutes=$(((seconds_until_reset % 3600) / 60))
    
    # Format countdown string
    if [ $hours -gt 0 ]; then
        if [ $minutes -gt 0 ]; then
            echo "${hours}h${minutes}m"
        else
            echo "${hours}h"
        fi
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}m"
    else
        echo "<1m"
    fi
}

countdown_timer=$(calculate_countdown)

# Calculate context window percentage from actual token usage
calculate_context_percentage() {
    # Default context percentage (assume full context available)
    local default_percentage=100
    
    # Build session file path: ~/.claude/projects/-{current_dir_with_slashes_replaced}/${session_id}.jsonl
    local projects_dir="$HOME/.claude/projects"
    local project_dir_name=$(echo "$current_dir" | sed 's/[/_]/-/g')
    local session_file="$projects_dir/${project_dir_name}/${session_id}.jsonl"
    
    # Check if session file exists
    if [ ! -f "$session_file" ]; then
        echo "$default_percentage"
        return
    fi
    
    # Find the latest message WITH usage data (search backwards through file)
    # Look for lines containing "usage":{ to find messages with token usage
    local latest_usage_message=$(grep '"usage":{' "$session_file" 2>/dev/null | tail -n 1)
    
    # Skip if no message with usage found
    if [ -z "$latest_usage_message" ]; then
        echo "$default_percentage"
        return
    fi
    
    # Extract token usage from message.usage - try jq first, fallback to grep/sed
    # Method 1: Try with cleaned JSON (remove control characters)
    local cleaned_message=$(echo "$latest_usage_message" | tr -d '\000-\037')
    local input_tokens=$(echo "$cleaned_message" | jq -r '.message.usage.input_tokens // 0' 2>/dev/null)
    local cache_read_tokens=$(echo "$cleaned_message" | jq -r '.message.usage.cache_read_input_tokens // 0' 2>/dev/null)
    local cache_creation_tokens=$(echo "$cleaned_message" | jq -r '.message.usage.cache_creation_input_tokens // 0' 2>/dev/null)
    
    # Method 2: If jq failed, use grep/sed extraction as fallback
    if [ -z "$input_tokens" ] || [ "$input_tokens" = "null" ] || [ "$input_tokens" = "0" ]; then
        input_tokens=$(echo "$latest_usage_message" | grep -o '"input_tokens":[0-9]*' | sed 's/.*://' | head -n1)
        cache_read_tokens=$(echo "$latest_usage_message" | grep -o '"cache_read_input_tokens":[0-9]*' | sed 's/.*://' | head -n1)
        cache_creation_tokens=$(echo "$latest_usage_message" | grep -o '"cache_creation_input_tokens":[0-9]*' | sed 's/.*://' | head -n1)
        
        # Set defaults for missing values
        [ -z "$input_tokens" ] && input_tokens=0
        [ -z "$cache_read_tokens" ] && cache_read_tokens=0
        [ -z "$cache_creation_tokens" ] && cache_creation_tokens=0
    fi
    
    # If still no input tokens found, return default
    if [ -z "$input_tokens" ] || [ "$input_tokens" = "null" ] || [ "$input_tokens" -eq 0 ]; then
        echo "$default_percentage"
        return
    fi
    
    # Calculate total tokens used (input + cache read + cache creation)
    local total_tokens=$((input_tokens + cache_read_tokens + cache_creation_tokens))
    
    # Claude models have 200K context window
    local max_context=200000
    
    # Calculate percentage remaining (not used)
    local percentage_used=$((total_tokens * 100 / max_context))
    local percentage_remaining=$((100 - percentage_used))
    
    # Ensure percentage is within bounds
    if [ $percentage_remaining -lt 0 ]; then
        percentage_remaining=0
    elif [ $percentage_remaining -gt 100 ]; then
        percentage_remaining=100
    fi
    
    echo "$percentage_remaining"
}

context_percentage=$(calculate_context_percentage)

# Determine context color based on percentage remaining
if [ $context_percentage -le 20 ]; then
    context_color="\033[31m"  # Red for low context remaining
elif [ $context_percentage -le 50 ]; then
    context_color="\033[33m"  # Yellow for medium context remaining
else
    context_color="\033[32m"  # Green for high context remaining
fi

# Format the status line with attractive ASCII styling and colors
# Shows: [Context%] ▪ Model (Countdown) ▪ Directory → Branch
printf "${context_color}[%d%%]\033[0m \033[2m▪\033[0m \033[36m%s\033[0m \033[2;36m(%s)\033[0m \033[2m▪\033[0m \033[35m%s\033[0m \033[2m→\033[0m \033[33m⌥ %s\033[0m" \
    "$context_percentage" \
    "$model_name" \
    "$countdown_timer" \
    "$dir_name" \
    "$git_branch"