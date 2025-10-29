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

# Pre-flight checks to show what needs to be done
preflight_checks() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "PRE-INSTALLATION CHECKS"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local checks_passed=0
    local checks_total=0
    local missing_deps=()

    # Check Homebrew
    ((checks_total++))
    if command -v brew &> /dev/null; then
        log "✓ Homebrew installed"
        ((checks_passed++))
    else
        error "✗ Homebrew not installed"
        missing_deps+=("brew")
    fi

    # Check required tools for calendar automation
    ((checks_total++))
    if command -v khal &> /dev/null; then
        log "✓ khal installed ($(khal --version 2>&1 | head -1))"
        ((checks_passed++))
    else
        warn "✗ khal not installed (required for calendar automation)"
        missing_deps+=("khal")
    fi

    # Check Sketchybar
    ((checks_total++))
    if command -v sketchybar &> /dev/null; then
        log "✓ Sketchybar installed"
        ((checks_passed++))
    else
        warn "✗ Sketchybar not installed"
        missing_deps+=("sketchybar")
    fi

    # Check .env file
    ((checks_total++))
    if [[ -f "$DOTFILES_DIR/.env" ]]; then
        log "✓ .env file exists"
        ((checks_passed++))

        # Check for calendar URLs
        if grep -q "ICAL_URLS" "$DOTFILES_DIR/.env" 2>/dev/null; then
            log "  ↳ Calendar URLs configured"
        else
            warn "  ↳ No ICAL_URLS found in .env (calendar sync will fail)"
        fi
    else
        warn "✗ .env file not found (copy from .env.example)"
    fi

    # Check existing symlinks
    log ""
    log "Checking existing symlinks:"
    local symlinks=(
        "$HOME/.config/aerospace:Aerospace"
        "$HOME/.config/sketchybar:Sketchybar"
        "$HOME/.config/karabiner:Karabiner"
        "$HOME/.hammerspoon:Hammerspoon"
        "$HOME/.claude:Claude"
        "$HOME/.config/khal:Khal"
    )

    for entry in "${symlinks[@]}"; do
        IFS=':' read -r path name <<< "$entry"
        if [[ -L "$path" ]]; then
            log "  → $name: symlink exists (will be updated)"
        elif [[ -e "$path" ]]; then
            warn "  → $name: file/dir exists (will be backed up)"
        else
            log "  → $name: not installed (will be created)"
        fi
    done

    echo ""
    log "Pre-flight summary: $checks_passed/$checks_total checks passed"

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        warn "Missing dependencies: ${missing_deps[*]}"
        echo ""
        log "To install missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                brew)
                    log "  Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                    ;;
                khal)
                    log "  khal: brew install khal"
                    ;;
                sketchybar)
                    log "  Sketchybar: brew install felixkratz/formulae/sketchybar"
                    ;;
            esac
        done
    fi

    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        if ask_user "Continue installation despite missing dependencies?"; then
            return 0
        else
            error "Installation aborted by user"
            exit 1
        fi
    fi
}

# Post-installation validation
validate_installation() {
    log ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "POST-INSTALLATION VALIDATION"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local validations_passed=0
    local validations_total=0

    # Validate symlinks
    log "Validating symlinks:"
    local symlinks=(
        "$HOME/.config/aerospace|$DOTFILES_DIR/config/aerospace|Aerospace"
        "$HOME/.config/sketchybar|$DOTFILES_DIR/config/sketchybar|Sketchybar"
        "$HOME/.config/karabiner|$DOTFILES_DIR/config/karabiner|Karabiner"
        "$HOME/.hammerspoon|$DOTFILES_DIR/config/hammerspoon|Hammerspoon"
        "$HOME/.claude|$DOTFILES_DIR/config/claude|Claude"
        "$HOME/.config/khal|$DOTFILES_DIR/config/khal|Khal"
    )

    for entry in "${symlinks[@]}"; do
        IFS='|' read -r target source name <<< "$entry"
        ((validations_total++))
        if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
            log "  ✓ $name symlink valid"
            ((validations_passed++))
        else
            error "  ✗ $name symlink invalid or missing"
        fi
    done

    # Validate LaunchAgent
    log ""
    log "Validating calendar sync LaunchAgent:"
    ((validations_total++))
    local plist_path="$HOME/Library/LaunchAgents/com.user.calendar-sync.plist"
    if [[ -f "$plist_path" ]]; then
        log "  ✓ LaunchAgent plist exists"

        # Check if it has PATH configured
        if grep -q "<key>EnvironmentVariables</key>" "$plist_path"; then
            log "  ✓ PATH environment variable configured"
        else
            warn "  ✗ PATH environment variable missing (khal may fail)"
        fi

        # Check if loaded
        if launchctl list | grep -q "com.user.calendar-sync"; then
            log "  ✓ LaunchAgent loaded and running"
            ((validations_passed++))
        else
            warn "  ✗ LaunchAgent not loaded"
        fi
    else
        warn "  ✗ LaunchAgent plist not installed"
    fi

    # Validate calendar sync directories
    log ""
    log "Validating calendar sync infrastructure:"
    ((validations_total++))
    if [[ -d "$HOME/.config/sketchybar/logs" ]]; then
        log "  ✓ Logs directory exists"
        ((validations_passed++))
    else
        error "  ✗ Logs directory missing"
    fi

    ((validations_total++))
    if [[ -d "$HOME/.local/share/khal/calendars" ]] || command -v khal &>/dev/null; then
        log "  ✓ khal database directory ready"
        ((validations_passed++))
    else
        warn "  ✗ khal not configured"
    fi

    # Test calendar sync
    log ""
    log "Testing calendar sync:"
    ((validations_total++))
    if [[ -f "$HOME/.config/sketchybar/helpers/sync-calendars.sh" ]]; then
        log "  ✓ sync-calendars.sh script found"

        if [[ -x "$HOME/.config/sketchybar/helpers/sync-calendars.sh" ]]; then
            log "  ✓ Script is executable"
        else
            warn "  ✗ Script is not executable (fixing...)"
            chmod +x "$HOME/.config/sketchybar/helpers/sync-calendars.sh"
        fi

        # Try a dry-run if khal is available
        if command -v khal &>/dev/null && [[ -f "$DOTFILES_DIR/.env" ]]; then
            log "  → Running test sync..."
            if bash "$HOME/.config/sketchybar/helpers/sync-calendars.sh" &>/dev/null; then
                log "  ✓ Calendar sync executed successfully"
                ((validations_passed++))

                # Check sync status
                if [[ -f "$HOME/.cache/sketchybar/last_sync_status" ]]; then
                    local exit_code=$(grep "exit_code" "$HOME/.cache/sketchybar/last_sync_status" | cut -d'=' -f2)
                    if [[ "$exit_code" == "0" ]]; then
                        log "  ✓ Last sync status: SUCCESS"
                    else
                        warn "  ⚠ Last sync had errors (exit code: $exit_code)"
                        warn "    Check logs: tail -50 ~/.config/sketchybar/logs/calendar-sync.log"
                    fi
                fi
            else
                warn "  ⚠ Calendar sync failed (see logs for details)"
                warn "    Check: tail -50 ~/.config/sketchybar/logs/calendar-sync.log"
            fi
        else
            warn "  ⚠ Cannot test sync (missing khal or .env)"
        fi
    else
        error "  ✗ sync-calendars.sh script not found"
    fi

    echo ""
    log "Validation summary: $validations_passed/$validations_total checks passed"

    # Show next steps based on validation results
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ $validations_passed -eq $validations_total ]]; then
        log "🎉 All validations passed! Installation successful!"
    else
        warn "⚠️  Some validations failed. Please review and fix issues."
    fi
}

ask_user() {
    local prompt="$1"
    local default="${2:-y}"

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -p "$prompt" -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY && "$default" == "y" ]]; then
        return 0
    else
        return 1
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

install_calendar_launchagent() {
    local label="com.user.calendar-sync"
    local plist_source="$DOTFILES_DIR/config/sketchybar/launchagents/$label.plist"
    local plist_target="$HOME/Library/LaunchAgents/$label.plist"
    local logs_dir="$HOME/.config/sketchybar/logs"

    log "Installing calendar sync LaunchAgent"

    # Ensure logs directory exists
    if [[ ! -d "$logs_dir" ]]; then
        mkdir -p "$logs_dir"
        log "Created logs directory: $logs_dir"
    fi

    # Check if plist source exists
    if [[ ! -f "$plist_source" ]]; then
        error "LaunchAgent plist not found at: $plist_source"
        return 1
    fi

    # Unload existing LaunchAgent if loaded
    if launchctl list | grep -q "$label"; then
        warn "Unloading existing LaunchAgent: $label"
        launchctl unload "$plist_target" 2>/dev/null || true
    fi

    # Backup existing plist if it exists
    if [[ -f "$plist_target" ]]; then
        backup_existing "$plist_target"
    fi

    # Copy plist and replace HOME_DIR placeholder
    sed "s|HOME_DIR|$HOME|g" "$plist_source" > "$plist_target"

    # Validate plist syntax
    if ! plutil -lint "$plist_target" &>/dev/null; then
        error "LaunchAgent plist validation failed"
        rm "$plist_target"
        return 1
    fi

    log "✓ LaunchAgent plist installed and validated"

    # Load LaunchAgent
    if launchctl load -w "$plist_target" 2>/dev/null; then
        log "✓ LaunchAgent loaded successfully"
        log "Calendar sync will run every 15 minutes"
        log "Manual trigger: launchctl start $label"
    else
        warn "Failed to load LaunchAgent (non-blocking)"
        warn "You can manually load it with: launchctl load -w $plist_target"
        return 0  # Non-blocking failure per graceful degradation pattern
    fi
}

main() {
    log "Starting dotfiles installation from: $DOTFILES_DIR"
    echo ""

    # Run pre-flight checks
    preflight_checks

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

    # Calendar sync LaunchAgent (optional)
    log ""
    if ask_user "Install calendar sync LaunchAgent (auto-syncs every 15 minutes)?"; then
        install_calendar_launchagent
    else
        log "Skipping calendar sync LaunchAgent installation"
        log "You can manually sync with: bash ~/.config/sketchybar/helpers/sync-calendars.sh"
    fi

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

    # Run post-installation validation
    validate_installation

    log ""
    log "Next steps:"
    log "1. Restart any running applications to pick up new configs"
    log "2. Launch AeroSpace: open -a AeroSpace"
    log "3. Reload Hammerspoon config if it's already running"
    log "4. Check calendar sync logs: tail -f ~/.config/sketchybar/logs/calendar-sync.log"
    log "5. Monitor LaunchAgent: launchctl list | grep calendar-sync"
    log ""
    log "Troubleshooting resources:"
    log "  - Documentation: cat ~/dotfiles/CLAUDE.md"
    log "  - Calendar sync status: cat ~/.cache/sketchybar/last_sync_status"
    log "  - Manual sync test: bash ~/.config/sketchybar/helpers/sync-calendars.sh"
    log ""
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi