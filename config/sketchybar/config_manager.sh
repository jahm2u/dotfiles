#!/usr/bin/env zsh

# Sketchybar Configuration Manager
# Supports 4 modes: desktop, desktop-privacy, laptop, laptop-privacy

SKETCHYBAR_DIR="$HOME/.config/sketchybar"

# Find .env file
if [[ -f "$HOME/repos/02_personal/dotfiles/.env" ]]; then
    ENV_FILE="$HOME/repos/02_personal/dotfiles/.env"
elif [[ -f "$HOME/dotfiles/.env" ]]; then
    ENV_FILE="$HOME/dotfiles/.env"
else
    ENV_FILE=""
fi

# Helper: Read value from .env
read_env_value() {
    local key="$1"
    local default="$2"

    if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
        # Extract value, handling quotes and comments
        local value=$(grep "^${key}=" "$ENV_FILE" | head -1 | cut -d'=' -f2- | sed 's/^["'\'']//' | sed 's/["'\'']$//' | sed 's/#.*//')
        if [[ -n "$value" ]]; then
            echo "$value"
        else
            echo "$default"
        fi
    else
        echo "$default"
    fi
}

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

# Get device type (from .env or auto-detect)
get_device_type() {
    local device_type=$(read_env_value "SKETCHYBAR_DEVICE_TYPE" "")
    if [[ -z "$device_type" ]]; then
        detect_device_type
    else
        echo "$device_type"
    fi
}

# Get current config by reading sketchybarrc
get_current_config() {
    if [[ -f "$SKETCHYBAR_DIR/sketchybarrc" ]]; then
        # Extract config name from the source line
        local config=$(grep "source.*sketchybarrc-" "$SKETCHYBAR_DIR/sketchybarrc" | sed 's/.*sketchybarrc-//' | sed 's/".*//')
        if [[ -n "$config" ]]; then
            echo "$config"
        else
            get_device_type
        fi
    else
        get_device_type
    fi
}

# Get current privacy mode status
get_privacy_status() {
    local config=$(get_current_config)
    if [[ "$config" == *"-privacy" ]]; then
        echo "privacy"
    else
        echo "normal"
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

SKETCHYBAR_CONFIG="$SKETCHYBAR_DIR"
source "\$SKETCHYBAR_CONFIG/sketchybarrc-$config_name"
EOF

    # Make it executable
    chmod +x "$SKETCHYBAR_DIR/sketchybarrc"

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
        echo "  $0 config <name>       Switch to specific configuration"
        echo "  $0 help                Show this help"
        echo ""
        echo "Device type is set in .env file (SKETCHYBAR_DEVICE_TYPE=laptop or desktop)"
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