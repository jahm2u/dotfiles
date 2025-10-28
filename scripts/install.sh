#!/usr/bin/env bash

# Dotfiles Installation Script
# This script creates symlinks for all configuration files

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where this script is located
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

backup_existing() {
    local target="$1"
    if [[ -e "$target" && ! -L "$target" ]]; then
        local backup="${target}.backup.$(date +%Y%m%d_%H%M%S)"
        warn "Backing up existing $target to $backup"
        mv "$target" "$backup"
    elif [[ -L "$target" ]]; then
        warn "Removing existing symlink: $target"
        rm "$target"
    fi
}

create_symlink() {
    local source="$1"
    local target="$2"
    local description="$3"
    
    log "Setting up $description"
    
    # Create parent directory if it doesn't exist
    mkdir -p "$(dirname "$target")"
    
    # Backup existing config
    backup_existing "$target"
    
    # Create symlink
    ln -sf "$source" "$target"
    
    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        log "✓ Successfully linked $description"
    else
        error "✗ Failed to link $description"
        return 1
    fi
}

main() {
    log "Starting dotfiles installation from: $DOTFILES_DIR"

    # Clean up old aerospace config location (deprecated)
    if [[ -e "$HOME/.aerospace.toml" ]]; then
        warn "Removing old aerospace config at ~/.aerospace.toml (deprecated location)"
        backup_existing "$HOME/.aerospace.toml"
    fi

    # Aerospace
    create_symlink \
        "$DOTFILES_DIR/config/aerospace" \
        "$HOME/.config/aerospace" \
        "Aerospace window manager config"
    
    # Sketchybar
    create_symlink \
        "$DOTFILES_DIR/config/sketchybar" \
        "$HOME/.config/sketchybar" \
        "Sketchybar status bar config"
    
    # Karabiner
    create_symlink \
        "$DOTFILES_DIR/config/karabiner" \
        "$HOME/.config/karabiner" \
        "Karabiner key mapping config"
    
    # Hammerspoon
    create_symlink \
        "$DOTFILES_DIR/config/hammerspoon" \
        "$HOME/.hammerspoon" \
        "Hammerspoon automation config"
    
    # Claude
    create_symlink \
        "$DOTFILES_DIR/config/claude" \
        "$HOME/.claude" \
        "Claude AI assistant config"
    
    # Raycast
    create_symlink \
        "$DOTFILES_DIR/config/raycast" \
        "$HOME/.config/raycast" \
        "Raycast launcher config"
    
    # Obsidian (to iCloud location)
    create_symlink \
        "$DOTFILES_DIR/config/obsidian" \
        "$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/.obsidian" \
        "Obsidian vault config"
    
    # Khal calendar
    create_symlink \
        "$DOTFILES_DIR/config/khal" \
        "$HOME/.config/khal" \
        "Khal calendar config"


    # Load environment configuration for Sketchybar
    log "Loading environment configuration..."
    local loader_script="$DOTFILES_DIR/config/sketchybar/helpers/load-env-config.sh"

    # Ensure loader script is executable
    if [[ -f "$loader_script" ]]; then
        chmod +x "$loader_script" 2>/dev/null || true

        # Run environment loader
        if bash "$loader_script"; then
            log "✓ Environment configuration loaded successfully"
        else
            warn "Environment loader failed, using defaults"
        fi
    else
        warn "Environment loader not found at $loader_script"
        warn "Sketchybar will use default configuration"
    fi

    # Restart Sketchybar with new configuration
    log "Restarting Sketchybar with environment configuration..."
    if command -v brew &> /dev/null; then
        if brew services restart sketchybar 2>/dev/null; then
            log "✓ Sketchybar restarted successfully"
        else
            warn "Failed to restart Sketchybar service"
            log "You may need to start it manually: brew services start sketchybar"
        fi
    else
        warn "Homebrew not found, cannot restart Sketchybar automatically"
        log "Please start Sketchybar manually"
    fi

    log ""
    log "🎉 Dotfiles installation completed successfully!"
    log ""
    log "Next steps:"
    log "1. Restart any running applications to pick up new configs"
    log "2. Launch AeroSpace: open -a AeroSpace"
    log "3. Reload Hammerspoon config if it's already running"
    log "4. Check Sketchybar logs if issues occur: tail -f ~/Library/Logs/sketchybar/sketchybar.log"
    log ""
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi