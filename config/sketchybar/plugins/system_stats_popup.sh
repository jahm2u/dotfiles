#!/usr/bin/env bash

# System Stats Popup - Shows top 10 CPU and Memory consuming processes
# Usage: Called when CPU or Memory widget is clicked
# Shows: Top 10 CPU processes (% usage), Top 10 Memory processes (GB/MB usage matching Activity Monitor)

# Determine which popup to check
POPUP_WIDGET="${NAME:-cpu}"

# Check if popup is already open
POPUP_STATE=$(sketchybar --query "$POPUP_WIDGET" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('popup', {}).get('drawing', 'off'))")

# If already open, just close it and exit
if [[ "$POPUP_STATE" == "on" ]]; then
    sketchybar --set "$POPUP_WIDGET" popup.drawing=off
    exit 0
fi

# Close all other popups and show this one immediately
sketchybar --set todoist popup.drawing=off \
           --set meeting popup.drawing=off \
           --set week_num popup.drawing=off \
           --set cpu popup.drawing=off \
           --set memory popup.drawing=off \
           --set "$POPUP_WIDGET" popup.drawing=on

# Load environment colors
source "$HOME/.config/sketchybar/helpers/source-colors.sh"

# Function to get friendly app name from process name
get_app_name() {
    local proc_name="$1"

    # Common app name mappings
    case "$proc_name" in
        "stable") echo "Warp" ;;
        "Code Helper"*) echo "VS Code Helper" ;;
        "Google Chrome Hel"*) echo "Chrome Helper" ;;
        "Slack Helper"*) echo "Slack Helper" ;;
        *) echo "$proc_name" ;;
    esac
}

# Function to get top 10 CPU processes
get_top_cpu_processes() {
    # Get top 10 CPU consumers (excluding header)
    ps -A -o %cpu,comm | sort -nr | head -11 | tail -10 | while read -r cpu comm; do
        # Get friendly name
        comm=$(get_app_name "$(basename "$comm")")

        # Truncate if too long
        if [[ ${#comm} -gt 20 ]]; then
            comm="${comm:0:17}..."
        fi

        # Format CPU percentage
        cpu=$(printf "%.1f" "$cpu")

        echo "${cpu}%|${comm}"
    done
}

# Function to get top 10 memory processes with Activity Monitor-style formatting
get_top_memory_processes() {
    # Use top command to get memory values that match Activity Monitor
    # Then use ps to get better process names

    # First get PIDs sorted by memory
    top -l 1 -o mem -n 50 -stats pid,mem,command | \
        tail -n +2 | \
        grep -v -E '^(Processes|PhysMem|VM|Networks|Disks|MemRegions|SharedLibs):' | \
        while read -r pid mem comm; do
            # Skip empty lines and system categories
            [[ -z "$pid" ]] && continue
            [[ ! "$pid" =~ ^[0-9]+$ ]] && continue

            # Get the friendly app name using ps
            app_name=$(ps -p "$pid" -o comm= 2>/dev/null | xargs basename)
            [[ -z "$app_name" ]] && app_name="$comm"

            # Apply app name mapping
            app_name=$(get_app_name "$app_name")

            # Truncate if too long
            if [[ ${#app_name} -gt 20 ]]; then
                app_name="${app_name:0:17}..."
            fi

            # Parse memory value (format: 123M or 1.2G)
            if [[ "$mem" =~ ([0-9.]+)([MGT]) ]]; then
                value="${BASH_REMATCH[1]}"
                unit="${BASH_REMATCH[2]}"

                # Convert everything to MB for sorting
                case "$unit" in
                    G)
                        mb_value=$(echo "scale=2; $value * 1024" | bc)
                        ;;
                    M)
                        mb_value="$value"
                        ;;
                    T)
                        mb_value=$(echo "scale=2; $value * 1024 * 1024" | bc)
                        ;;
                    *)
                        continue
                        ;;
                esac

                # Format for display
                case "$unit" in
                    G)
                        formatted=$(printf "%.2f GB" "$value")
                        ;;
                    M)
                        if (( $(echo "$value >= 1000" | bc -l) )); then
                            gb=$(echo "scale=2; $value / 1024" | bc)
                            formatted=$(printf "%.2f GB" "$gb")
                        else
                            formatted=$(printf "%.1f MB" "$value")
                        fi
                        ;;
                    T)
                        formatted=$(printf "%.2f TB" "$value")
                        ;;
                esac

                # Output with MB value for sorting, formatted string, and app name
                echo "$mb_value|$formatted|$app_name"
            fi
        done | \
        sort -t'|' -k1 -nr | \
        head -10 | \
        cut -d'|' -f2,3
}

# Get top processes
CPU_PROCESSES=$(get_top_cpu_processes)
MEM_PROCESSES=$(get_top_memory_processes)

# Populate CPU section
INDEX=1
while IFS='|' read -r cpu_percent cpu_name; do
    [[ -z "$cpu_percent" ]] && break

    sketchybar --set stats.popup.cpu_$INDEX \
        label="$cpu_name  $cpu_percent" \
        label.color="0xCCFFFFFF" \
        icon="󰻠" \
        icon.color="$RED" \
        background.color="$TRANSPARENT" \
        drawing=on

    INDEX=$((INDEX + 1))
done <<< "$CPU_PROCESSES"

# Hide unused CPU slots
while [[ $INDEX -le 10 ]]; do
    sketchybar --set stats.popup.cpu_$INDEX drawing=off
    INDEX=$((INDEX + 1))
done

# Populate Memory section
INDEX=1
while IFS='|' read -r mem_size mem_name; do
    [[ -z "$mem_size" ]] && break

    sketchybar --set stats.popup.mem_$INDEX \
        label="$mem_name  $mem_size" \
        label.color="0xCCFFFFFF" \
        icon="󰍛" \
        icon.color="$GREEN" \
        background.color="$TRANSPARENT" \
        drawing=on

    INDEX=$((INDEX + 1))
done <<< "$MEM_PROCESSES"

# Hide unused Memory slots
while [[ $INDEX -le 10 ]]; do
    sketchybar --set stats.popup.mem_$INDEX drawing=off
    INDEX=$((INDEX + 1))
done

# Popup already shown at the start - no need to toggle again
