#!/usr/bin/env zsh

# Toggle between full and minimal Sketchybar configs

SKETCHYBAR_DIR="$HOME/.config/sketchybar"
CURRENT_CONFIG="$SKETCHYBAR_DIR/.current_config"

# Check which config is currently active
if [[ -f "$CURRENT_CONFIG" ]]; then
    ACTIVE=$(cat "$CURRENT_CONFIG")
else
    # Default to full config if no state file exists
    ACTIVE="full"
fi

# Toggle between configs
if [[ "$ACTIVE" == "full" ]]; then
    # Switch to minimal config
    cat > "$SKETCHYBAR_DIR/sketchybarrc" << 'EOF'
#!/usr/bin/env zsh

SKETCHYBAR_CONFIG="$HOME/.config/sketchybar"

# Use minimal config (no productivity items)
source "$SKETCHYBAR_CONFIG/sketchybarrc-laptop-minimal"
EOF
    echo "minimal" > "$CURRENT_CONFIG"
    /opt/homebrew/bin/brew services restart sketchybar
else
    # Switch to full config
    cat > "$SKETCHYBAR_DIR/sketchybarrc" << 'EOF'
#!/usr/bin/env zsh

SKETCHYBAR_CONFIG="$HOME/.config/sketchybar"

# Always use laptop config (works for both laptop and desktop)
source "$SKETCHYBAR_CONFIG/sketchybarrc-laptop"
EOF
    echo "full" > "$CURRENT_CONFIG"
    /opt/homebrew/bin/brew services restart sketchybar
fi