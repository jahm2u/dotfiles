#!/usr/bin/env zsh

# Sketchybar Configuration Manager
# Supports 4 modes: desktop, desktop-privacy, laptop, laptop-privacy

SKETCHYBAR_DIR="$HOME/.config/sketchybar"
CONFIG_STATE_FILE="$SKETCHYBAR_DIR/.config_state"
DEVICE_TYPE_FILE="$SKETCHYBAR_DIR/.device_type"

# Function to detect device type (can be overridden manually)
detect_device_type() {
    # Check if battery is present - more reliable than display count
    local battery_info=$(pmset -g batt 2>/dev/null)

    # If pmset returns battery info, it's a laptop
    if [[ "$battery_info" == *"InternalBattery"* ]] || [[ "$battery_info" == *"Battery"* ]]; then
        echo "laptop"
    else
        echo "desktop"
    fi
}

# Get current device type (from file or auto-detect)
get_device_type() {
    if [[ -f "$DEVICE_TYPE_FILE" ]]; then
        cat "$DEVICE_TYPE_FILE"
    else
        detect_device_type
    fi
}

# Get current privacy mode status
get_privacy_status() {
    if [[ -f "$CONFIG_STATE_FILE" ]]; then
        local state=$(cat "$CONFIG_STATE_FILE")
        if [[ "$state" == *"-privacy" ]]; then
            echo "privacy"
        else
            echo "normal"
        fi
    else
        echo "normal"
    fi
}

# Get current full config name
get_current_config() {
    if [[ -f "$CONFIG_STATE_FILE" ]]; then
        cat "$CONFIG_STATE_FILE"
    else
        local device_type=$(get_device_type)
        echo "$device_type"
    fi
}

# Set device type manually
set_device_type() {
    local device_type="$1"

    if [[ "$device_type" != "desktop" && "$device_type" != "laptop" ]]; then
        echo "Error: Device type must be 'desktop' or 'laptop'"
        return 1
    fi

    echo "$device_type" > "$DEVICE_TYPE_FILE"
    echo "Device type set to: $device_type"

    # Update config to match new device type
    local privacy_status=$(get_privacy_status)
    if [[ "$privacy_status" == "privacy" ]]; then
        switch_to_config "${device_type}-privacy"
    else
        switch_to_config "$device_type"
    fi
}

# Toggle privacy mode for current device
toggle_privacy() {
    local device_type=$(get_device_type)
    local current_privacy=$(get_privacy_status)

    if [[ "$current_privacy" == "privacy" ]]; then
        # Switch to normal mode
        switch_to_config "$device_type"
        echo "Privacy mode OFF - showing meetings and Todoist"
    else
        # Switch to privacy mode
        switch_to_config "${device_type}-privacy"
        echo "Privacy mode ON - hiding meetings and Todoist"
    fi
}

# Switch to specific configuration
switch_to_config() {
    local config_name="$1"
    local config_file="$SKETCHYBAR_DIR/sketchybarrc-$config_name"

    # Validate config file exists
    if [[ ! -f "$config_file" ]]; then
        echo "Error: Configuration file not found: $config_file"
        echo "Available configs:"
        ls -1 "$SKETCHYBAR_DIR"/sketchybarrc-* | sed 's/.*sketchybarrc-/  /'
        return 1
    fi

    # Create the main sketchybarrc that sources the selected config
    cat > "$SKETCHYBAR_DIR/sketchybarrc" << EOF
#!/usr/bin/env zsh

# Auto-generated configuration switcher
# Current config: $config_name
# Generated: $(date)

SKETCHYBAR_CONFIG="$SKETCHYBAR_DIR"
source "\$SKETCHYBAR_CONFIG/sketchybarrc-$config_name"
EOF

    # Make it executable
    chmod +x "$SKETCHYBAR_DIR/sketchybarrc"

    # Save current state
    echo "$config_name" > "$CONFIG_STATE_FILE"

    # Restart sketchybar
    /opt/homebrew/bin/brew services restart sketchybar

    echo "Switched to configuration: $config_name"
}

# Show current status
show_status() {
    local device_type=$(get_device_type)
    local current_config=$(get_current_config)
    local privacy_status=$(get_privacy_status)

    echo "=== Sketchybar Configuration Status ==="
    echo "Device Type: $device_type"
    echo "Current Config: $current_config"
    echo "Privacy Mode: $privacy_status"
    echo ""
    echo "Available configurations:"
    ls -1 "$SKETCHYBAR_DIR"/sketchybarrc-* | sed 's/.*sketchybarrc-/  /'
}

# Main command handler
case "$1" in
    "toggle-privacy"|"privacy")
        toggle_privacy
        ;;
    "desktop")
        set_device_type "desktop"
        ;;
    "laptop")
        set_device_type "laptop"
        ;;
    "config")
        if [[ -n "$2" ]]; then
            switch_to_config "$2"
        else
            echo "Usage: $0 config <config-name>"
            echo "Available configs:"
            ls -1 "$SKETCHYBAR_DIR"/sketchybarrc-* | sed 's/.*sketchybarrc-/  /'
        fi
        ;;
    "status"|"")
        show_status
        ;;
    "help")
        echo "Sketchybar Configuration Manager"
        echo ""
        echo "Usage:"
        echo "  $0                     Show current status"
        echo "  $0 status              Show current status"
        echo "  $0 toggle-privacy      Toggle privacy mode (hide/show meetings & Todoist)"
        echo "  $0 privacy             Toggle privacy mode (alias)"
        echo "  $0 desktop             Set device type to desktop"
        echo "  $0 laptop              Set device type to laptop"
        echo "  $0 config <name>       Switch to specific configuration"
        echo "  $0 help                Show this help"
        echo ""
        echo "Available configurations:"
        ls -1 "$SKETCHYBAR_DIR"/sketchybarrc-* | sed 's/.*sketchybarrc-/  /'
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac