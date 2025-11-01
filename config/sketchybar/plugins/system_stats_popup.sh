#!/usr/bin/env bash

# System Stats Popup - Shows top CPU and Memory consuming processes
# Usage: Called when CPU or Memory widget is clicked
# Shows: Top 5 CPU processes, Top 5 Memory processes, kill buttons, Activity Monitor link

# Close all other popups first
sketchybar --set todoist popup.drawing=off \
           --set meeting popup.drawing=off \
           --set week_num popup.drawing=off

# Load environment colors
source "$HOME/.config/sketchybar/helpers/source-colors.sh"

# Function to get top CPU processes
get_top_cpu_processes() {
    ps -A -o %cpu,pid,comm | sort -nr | head -6 | tail -5 | while read -r cpu pid comm; do
        # Truncate command name if too long
        comm=$(basename "$comm")
        if [[ ${#comm} -gt 25 ]]; then
            comm="${comm:0:22}..."
        fi

        # Format CPU percentage
        cpu=$(printf "%.1f" "$cpu")

        echo "${cpu}%|${comm}|${pid}"
    done
}

# Function to get top memory processes
get_top_memory_processes() {
    ps -A -o %mem,pid,comm | sort -nr | head -6 | tail -5 | while read -r mem pid comm; do
        # Truncate command name if too long
        comm=$(basename "$comm")
        if [[ ${#comm} -gt 25 ]]; then
            comm="${comm:0:22}..."
        fi

        # Format memory percentage
        mem=$(printf "%.1f" "$mem")

        echo "${mem}%|${comm}|${pid}"
    done
}

# Determine which stats to show based on sender
SHOW_CPU=true
SHOW_MEM=true

# Get process lists
CPU_PROCESSES=$(get_top_cpu_processes)
MEM_PROCESSES=$(get_top_memory_processes)

# Populate CPU section
INDEX=1
while IFS='|' read -r percent name pid; do
    [[ -z "$percent" ]] && continue

    item_name="stats.popup.cpu_$INDEX"
    action_name="stats.popup.cpu_action_$INDEX"

    sketchybar --set "$item_name" \
        label="$name ($percent)" \
        label.color="$LABEL_COLOR" \
        icon="󰻠" \
        icon.color="$RED" \
        background.color="$TRANSPARENT" \
        drawing=on

    sketchybar --set "$action_name" \
        label="󰅙" \
        label.color="$RED" \
        icon.drawing=off \
        background.color="$TRANSPARENT" \
        click_script="kill -9 $pid && sketchybar --trigger stats_update" \
        drawing=on

    INDEX=$((INDEX + 1))
done <<< "$CPU_PROCESSES"

# Hide unused CPU slots
while [[ $INDEX -le 5 ]]; do
    sketchybar --set "stats.popup.cpu_$INDEX" drawing=off \
               --set "stats.popup.cpu_action_$INDEX" drawing=off
    INDEX=$((INDEX + 1))
done

# Divider
sketchybar --set stats.popup.divider \
    label="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" \
    label.color="$BACKGROUND_LESS_TRANSPARENT" \
    icon.drawing=off \
    drawing=on

# Populate Memory section
INDEX=1
while IFS='|' read -r percent name pid; do
    [[ -z "$percent" ]] && continue

    item_name="stats.popup.mem_$INDEX"
    action_name="stats.popup.mem_action_$INDEX"

    sketchybar --set "$item_name" \
        label="$name ($percent)" \
        label.color="$LABEL_COLOR" \
        icon="󰍛" \
        icon.color="$GREEN" \
        background.color="$TRANSPARENT" \
        drawing=on

    sketchybar --set "$action_name" \
        label="󰅙" \
        label.color="$RED" \
        icon.drawing=off \
        background.color="$TRANSPARENT" \
        click_script="kill -9 $pid && sketchybar --trigger stats_update" \
        drawing=on

    INDEX=$((INDEX + 1))
done <<< "$MEM_PROCESSES"

# Hide unused Memory slots
while [[ $INDEX -le 5 ]]; do
    sketchybar --set "stats.popup.mem_$INDEX" drawing=off \
               --set "stats.popup.mem_action_$INDEX" drawing=off
    INDEX=$((INDEX + 1))
done

# Activity Monitor footer
sketchybar --set stats.popup.footer \
    label="Open Activity Monitor" \
    label.color="$BLUE" \
    icon="󰍛" \
    icon.color="$BLUE" \
    background.color="$BACKGROUND_LESS_TRANSPARENT" \
    background.padding_top=5 \
    background.padding_bottom=5 \
    click_script="open -a 'Activity Monitor'" \
    drawing=on

# Toggle popup visibility (check which widget triggered this)
if [[ "$NAME" == "cpu" ]]; then
    sketchybar --set cpu popup.drawing=toggle
else
    sketchybar --set memory popup.drawing=toggle
fi
