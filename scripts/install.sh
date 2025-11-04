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

        # Check for calendar URLs (both old and new format)
        if grep -qE "CALENDAR_URL_|ICAL_URLS" "$DOTFILES_DIR/.env" 2>/dev/null; then
            log "  ↳ Calendar URLs configured"
        else
            warn "  ↳ No CALENDAR_URL_* variables found in .env"
            warn "  ↳ Calendar sync requires at least one CALENDAR_URL_NAME variable"
            warn "  ↳ See .env.example for configuration format"
        fi
    else
        warn "✗ .env file not found"
        if [[ -f "$DOTFILES_DIR/.env.example" ]]; then
            echo ""
            if ask_user "Create .env file from .env.example now?"; then
                if cp "$DOTFILES_DIR/.env.example" "$DOTFILES_DIR/.env"; then
                    log "✓ Created .env from .env.example"
                    log "⚠️  IMPORTANT: Edit .env and configure your CALENDAR_URL_* variables"
                    ((checks_passed++))
                else
                    error "✗ Failed to create .env file"
                fi
            else
                warn "Skipping .env creation - you'll need to create it manually"
            fi
        else
            error ".env.example not found - cannot auto-create .env"
        fi
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
        "$HOME/.config/raycast:Raycast"
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

        # Only offer auto-install if brew is available
        if command -v brew &> /dev/null; then
            if ask_user "Install missing dependencies automatically?"; then
                log "Installing missing dependencies..."
                for dep in "${missing_deps[@]}"; do
                    case "$dep" in
                        khal)
                            log "Installing khal..."
                            if brew install khal; then
                                log "✓ khal installed successfully"
                            else
                                error "✗ Failed to install khal"
                            fi
                            ;;
                        sketchybar)
                            log "Installing Sketchybar..."
                            if brew install felixkratz/formulae/sketchybar; then
                                log "✓ Sketchybar installed successfully"
                            else
                                error "✗ Failed to install Sketchybar"
                            fi
                            ;;
                    esac
                done
            else
                log "Skipping automatic installation"
                log "Manual installation commands:"
                for dep in "${missing_deps[@]}"; do
                    case "$dep" in
                        khal)
                            log "  khal: brew install khal"
                            ;;
                        sketchybar)
                            log "  Sketchybar: brew install felixkratz/formulae/sketchybar"
                            ;;
                    esac
                done
            fi
        else
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
    fi

    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ ${#missing_deps[@]} -gt 0 ]] && ! command -v brew &> /dev/null; then
        if ask_user "Continue installation despite missing dependencies?"; then
            return 0
        else
            error "Installation aborted by user"
            exit 1
        fi
    fi
}

# Install Nerd Font from local repo or download if missing
install_nerd_font() {
    local fonts_dir="$DOTFILES_DIR/fonts"
    local installed_count=0

    # First, try to install from local fonts directory
    if [[ -d "$fonts_dir" ]] && ls "$fonts_dir"/*.ttf &>/dev/null; then
        log "  → Installing fonts from repository..."

        while IFS= read -r -d '' font_file; do
            local font_basename=$(basename "$font_file")
            cp "$font_file" "$HOME/Library/Fonts/"
            ((installed_count++))
        done < <(find "$fonts_dir" -name "*.ttf" -print0)

        if [[ $installed_count -gt 0 ]]; then
            log "  → Installed $installed_count font files from repo"
            return 0
        fi
    fi

    # Fallback: Download from GitHub if local fonts not found
    log "  → Local fonts not found, downloading from GitHub..."
    local font_name="JetBrainsMono"
    local nerd_fonts_version="v3.2.1"
    local download_url="https://github.com/ryanoasis/nerd-fonts/releases/download/${nerd_fonts_version}/${font_name}.zip"
    local temp_dir=$(mktemp -d)

    # Download font zip
    if ! curl -sL "$download_url" -o "$temp_dir/${font_name}.zip"; then
        error "  ✗ Failed to download font"
        rm -rf "$temp_dir"
        return 1
    fi

    # Extract to temp directory
    if ! unzip -q "$temp_dir/${font_name}.zip" -d "$temp_dir" 2>/dev/null; then
        error "  ✗ Failed to extract font"
        rm -rf "$temp_dir"
        return 1
    fi

    # Install only essential weights
    local essential_fonts=(
        "JetBrainsMonoNLNerdFont-Regular.ttf"
        "JetBrainsMonoNLNerdFont-Medium.ttf"
        "JetBrainsMonoNLNerdFont-Bold.ttf"
        "JetBrainsMonoNLNerdFont-SemiBold.ttf"
        "JetBrainsMonoNLNerdFont-Italic.ttf"
        "JetBrainsMonoNLNerdFont-BoldItalic.ttf"
    )

    installed_count=0
    for font_name in "${essential_fonts[@]}"; do
        if [[ -f "$temp_dir/$font_name" ]]; then
            cp "$temp_dir/$font_name" "$HOME/Library/Fonts/"
            ((installed_count++))
        fi
    done

    # Clean up temp directory
    rm -rf "$temp_dir"

    if [[ $installed_count -gt 0 ]]; then
        log "  → Downloaded and installed $installed_count font files"
        return 0
    else
        error "  ✗ No font files found in download"
        return 1
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
        "$HOME/.config/raycast|$DOTFILES_DIR/config/raycast|Raycast"
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

    # Validate critical Brewfile dependencies
    log ""
    log "Validating critical dependencies:"

    # Check JetBrainsMono Nerd Font (use macOS-native font check)
    ((validations_total++))
    if ls ~/Library/Fonts/JetBrainsMono*NerdFont*.ttf &>/dev/null 2>&1 || \
       ls /Library/Fonts/JetBrainsMono*NerdFont*.ttf &>/dev/null 2>&1; then
        log "  ✓ JetBrains Mono Nerd Font installed"
        ((validations_passed++))
    else
        log "  → JetBrains Mono Nerd Font not found, installing..."
        if install_nerd_font; then
            log "  ✓ JetBrains Mono Nerd Font installed successfully"
            ((validations_passed++))
        else
            warn "  ✗ Could not auto-install font (try: brew install --cask font-jetbrains-mono-nerd-font)"
        fi
    fi

    # Check SimpleIcons font (required for app icons in Sketchybar)
    ((validations_total++))
    if ls ~/Library/Fonts/SimpleIcons.ttf &>/dev/null 2>&1; then
        log "  ✓ SimpleIcons font installed"
        ((validations_passed++))
    else
        log "  → SimpleIcons font not found, installing..."
        local simpleicons_font="$DOTFILES_DIR/config/sketchybar/simple-icons/font/SimpleIcons.ttf"
        if [[ -f "$simpleicons_font" ]]; then
            if cp "$simpleicons_font" "$HOME/Library/Fonts/"; then
                log "  ✓ SimpleIcons font installed successfully"
                ((validations_passed++))
            else
                warn "  ✗ Failed to install SimpleIcons font"
            fi
        else
            warn "  ✗ SimpleIcons font not found in repo at: $simpleicons_font"
        fi
    fi

    # Check AeroSpace
    ((validations_total++))
    if command -v aerospace &>/dev/null; then
        log "  ✓ AeroSpace installed"
        ((validations_passed++))
    else
        warn "  ✗ AeroSpace not installed (window management disabled)"
    fi

    # Check Sketchybar
    ((validations_total++))
    if command -v sketchybar &>/dev/null; then
        log "  ✓ Sketchybar installed"
        ((validations_passed++))
    else
        error "  ✗ Sketchybar not installed (status bar disabled)"
    fi

    # Check khal
    ((validations_total++))
    if command -v khal &>/dev/null; then
        log "  ✓ khal installed"
        ((validations_passed++))
    else
        warn "  ✗ khal not installed (calendar sync disabled)"
    fi

    # Check if all Brewfile dependencies are satisfied
    ((validations_total++))
    if command -v brew &>/dev/null && [[ -f "$DOTFILES_DIR/Brewfile" ]]; then
        cd "$DOTFILES_DIR"
        if brew bundle check &>/dev/null; then
            log "  ✓ All Brewfile dependencies installed"
            ((validations_passed++))
        else
            warn "  ✗ Some Brewfile dependencies missing"
            log "    Run: cd $DOTFILES_DIR && brew bundle"
        fi
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

check_and_install_brewfile_dependencies() {
    log "Checking Brewfile dependencies..."

    # Check if brew is available
    if ! command -v brew &>/dev/null; then
        error "Homebrew not installed - cannot check/install dependencies"
        log "Install Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        log "Then run: brew bundle in the dotfiles directory"
        return 1
    fi

    # Check if Brewfile exists
    if [[ ! -f "$DOTFILES_DIR/Brewfile" ]]; then
        error "Brewfile not found at $DOTFILES_DIR/Brewfile"
        return 1
    fi

    # Use brew bundle check to see if anything is missing
    cd "$DOTFILES_DIR"

    log "Checking which dependencies are missing..."

    # Capture missing dependencies
    local missing_output
    if missing_output=$(brew bundle check 2>&1); then
        log "✓ All Brewfile dependencies are installed"
        return 0
    else
        # Parse the output to show what's missing
        warn "Some Brewfile dependencies are missing:"
        echo "$missing_output" | grep -i "missing" || echo "$missing_output"

        log ""
        if ask_user "Install missing dependencies with 'brew bundle install'?"; then
            log "Installing missing Brewfile dependencies..."
            if brew bundle install; then
                log "✓ Successfully installed Brewfile dependencies"
                return 0
            else
                error "Failed to install some dependencies"
                log "You can retry manually with: cd $DOTFILES_DIR && brew bundle"
                return 1
            fi
        else
            warn "Skipping dependency installation"
            log "Install later with: cd $DOTFILES_DIR && brew bundle"
            return 1
        fi
    fi
}

initialize_calendar_infrastructure() {
    log "Initializing calendar automation infrastructure"

    # Create required directories
    local dirs=(
        "$HOME/.local/share/khal"
        "$HOME/.local/share/khal/calendars"
        "$HOME/.cache/sketchybar"
        "$HOME/.config/sketchybar/logs"
    )

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            if mkdir -p "$dir" 2>/dev/null; then
                log "✓ Created directory: $dir"
            else
                error "✗ Failed to create directory: $dir"
                return 1
            fi
        else
            log "✓ Directory exists: $dir"
        fi
    done

    # Make helper scripts executable
    local scripts=(
        "$HOME/.config/sketchybar/helpers/sync-calendars.sh"
        "$HOME/.config/sketchybar/helpers/trigger-calendar-sync.sh"
        "$HOME/.config/sketchybar/helpers/load-env-config.sh"
    )

    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            if chmod +x "$script" 2>/dev/null; then
                log "✓ Made executable: $(basename "$script")"
            else
                warn "Failed to set executable: $(basename "$script")"
            fi
        else
            warn "Script not found: $(basename "$script")"
        fi
    done

    # Verify khal can initialize its database
    if command -v khal &>/dev/null; then
        log "Testing khal database initialization..."
        if khal list today 1d &>/dev/null; then
            log "✓ khal database initialized successfully"
        else
            warn "khal database test failed (non-blocking)"
            warn "This is normal for first-time setup - will work after first sync"
        fi
    else
        warn "khal not installed - calendar sync will not work"
        warn "Install with: brew install khal"
    fi

    log "✓ Calendar infrastructure initialization complete"
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

setup_core_env_variables() {
    log "Core automation setup"
    echo ""

    # Check for OPENAI_API_KEY (required for meeting-prep and transcript analysis)
    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        log "OpenAI API key is required for meeting prep and AI analysis features."
        if ask_user "Would you like to configure your OpenAI API key now?"; then
            log ""
            log "To get your OpenAI API key:"
            log "  1. Visit: https://platform.openai.com/api-keys"
            log "  2. Sign in or create an account"
            log "  3. Click 'Create new secret key'"
            log "  4. Copy the key (starts with 'sk-')"
            echo ""
            read -p "Enter your OpenAI API key (or press Enter to skip): " api_key

            if [[ -n "$api_key" ]]; then
                if ! grep -q "OPENAI_API_KEY" "$DOTFILES_DIR/.env"; then
                    echo "OPENAI_API_KEY=$api_key" >> "$DOTFILES_DIR/.env"
                    log "✓ Added OPENAI_API_KEY to .env"
                    export OPENAI_API_KEY="$api_key"
                fi
            else
                warn "Skipping OpenAI API key - meeting prep features will not work"
            fi
        fi
    fi

    # Check for OBSIDIAN_VAULT_PATH (required for meeting-prep)
    if [[ -z "${OBSIDIAN_VAULT_PATH:-}" ]]; then
        log ""
        log "Obsidian vault path is required for meeting prep and note integration."

        # Try to auto-detect common Obsidian vault location
        local common_vault="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents"
        if [[ -d "$common_vault" ]]; then
            log "Found Obsidian vaults directory at: $common_vault"
            log "Available vaults:"
            ls -1 "$common_vault" 2>/dev/null | head -5
        fi

        if ask_user "Would you like to configure your Obsidian vault path now?"; then
            echo ""
            read -p "Enter full path to your Obsidian vault (or press Enter to skip): " vault_path

            if [[ -n "$vault_path" ]]; then
                # Expand ~ to home directory
                vault_path="${vault_path/#\~/$HOME}"

                if [[ -d "$vault_path" ]]; then
                    if ! grep -q "OBSIDIAN_VAULT_PATH" "$DOTFILES_DIR/.env"; then
                        echo "OBSIDIAN_VAULT_PATH=$vault_path" >> "$DOTFILES_DIR/.env"
                        log "✓ Added OBSIDIAN_VAULT_PATH to .env"
                        export OBSIDIAN_VAULT_PATH="$vault_path"
                    fi
                else
                    warn "Directory does not exist: $vault_path"
                    warn "You can add OBSIDIAN_VAULT_PATH to .env manually later"
                fi
            else
                warn "Skipping Obsidian vault path - meeting prep features will not work"
            fi
        fi
    fi

    # Check for calendar URLs (required for calendar sync)
    local has_calendar_url=false
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        # Bash 4+: Check for any CALENDAR_URL_* variables
        for var_name in ${!CALENDAR_URL_@}; do
            has_calendar_url=true
            break
        done
    else
        # Bash 3.2 fallback
        if compgen -v | grep -q '^CALENDAR_URL_'; then
            has_calendar_url=true
        fi
    fi

    if ! $has_calendar_url && [[ -z "${ICAL_URLS:-}" ]]; then
        log ""
        log "Calendar URLs are required for automatic calendar sync."
        if ask_user "Would you like to configure a calendar URL now?"; then
            log ""
            log "Calendar URL format examples:"
            log "  - Google: https://calendar.google.com/calendar/ical/...ics"
            log "  - iCloud: https://p##-caldav.icloud.com/published/#/..."
            log "  - Outlook: https://outlook.office365.com/owa/calendar/..."
            echo ""
            read -p "Enter a name for this calendar (e.g., GOOGLE, WORK, PERSONAL): " cal_name
            read -p "Enter calendar URL (or press Enter to skip): " cal_url

            if [[ -n "$cal_name" ]] && [[ -n "$cal_url" ]]; then
                # Sanitize calendar name (uppercase, alphanumeric + underscore only)
                cal_name=$(echo "$cal_name" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_')

                if ! grep -q "CALENDAR_URL_${cal_name}" "$DOTFILES_DIR/.env"; then
                    echo "CALENDAR_URL_${cal_name}=$cal_url" >> "$DOTFILES_DIR/.env"
                    log "✓ Added CALENDAR_URL_${cal_name} to .env"
                    export "CALENDAR_URL_${cal_name}=$cal_url"
                fi
            else
                warn "Skipping calendar URL - calendar sync will not work"
            fi
        fi
    fi

    return 0
}

setup_krisp_env_variables() {
    log ""
    log "Krisp automation setup"
    echo ""

    # Check if user wants to enable Krisp automation
    if [[ "${KRISP_LAUNCHAGENT:-}" != "TRUE" ]]; then
        log "Krisp automation is currently disabled."
        if ask_user "Would you like to enable Krisp transcript downloads?"; then
            # Add KRISP_LAUNCHAGENT=TRUE to .env
            if [[ -f "$DOTFILES_DIR/.env" ]]; then
                if ! grep -q "KRISP_LAUNCHAGENT" "$DOTFILES_DIR/.env"; then
                    echo "" >> "$DOTFILES_DIR/.env"
                    echo "# Krisp Automation (Story 4-2)" >> "$DOTFILES_DIR/.env"
                    echo "KRISP_LAUNCHAGENT=TRUE" >> "$DOTFILES_DIR/.env"
                    log "✓ Added KRISP_LAUNCHAGENT=TRUE to .env"
                    export KRISP_LAUNCHAGENT=TRUE
                else
                    # Variable exists but is not TRUE - update it
                    sed -i '' 's/^KRISP_LAUNCHAGENT=.*/KRISP_LAUNCHAGENT=TRUE/' "$DOTFILES_DIR/.env"
                    log "✓ Updated KRISP_LAUNCHAGENT=TRUE in .env"
                    export KRISP_LAUNCHAGENT=TRUE
                fi
            else
                error ".env file not found - cannot enable Krisp automation"
                return 1
            fi
        else
            log "Skipping Krisp automation setup"
            return 0
        fi
    fi

    # Check for optional Telegram notification variables
    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]] || [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        log ""
        log "Telegram notifications are optional but recommended for monitoring."
        if ask_user "Would you like to configure Telegram notifications?"; then

            # Get bot token
            if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
                log ""
                log "To create a Telegram bot:"
                log "  1. Message @BotFather on Telegram"
                log "  2. Send /newbot and follow instructions"
                log "  3. Copy the bot token provided"
                echo ""
                read -p "Enter your Telegram bot token (or press Enter to skip): " bot_token

                if [[ -n "$bot_token" ]]; then
                    if ! grep -q "TELEGRAM_BOT_TOKEN" "$DOTFILES_DIR/.env"; then
                        echo "TELEGRAM_BOT_TOKEN=$bot_token" >> "$DOTFILES_DIR/.env"
                        log "✓ Added TELEGRAM_BOT_TOKEN to .env"
                        export TELEGRAM_BOT_TOKEN="$bot_token"
                    fi
                fi
            fi

            # Get chat ID
            if [[ -z "${TELEGRAM_CHAT_ID:-}" ]] && [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
                log ""
                log "To get your chat ID:"
                log "  1. Message your bot on Telegram"
                log "  2. Visit: https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates"
                log "  3. Find 'chat' -> 'id' in the JSON response"
                echo ""
                read -p "Enter your Telegram chat ID (or press Enter to skip): " chat_id

                if [[ -n "$chat_id" ]]; then
                    if ! grep -q "TELEGRAM_CHAT_ID" "$DOTFILES_DIR/.env"; then
                        echo "TELEGRAM_CHAT_ID=$chat_id" >> "$DOTFILES_DIR/.env"
                        log "✓ Added TELEGRAM_CHAT_ID to .env"
                        export TELEGRAM_CHAT_ID="$chat_id"
                    fi
                fi
            fi
        fi
    fi

    # Remind about Krisp auth file
    log ""
    log "NOTE: Krisp authentication file required at:"
    log "  ~/.config/sketchybar/krisp-auth.json"
    log ""
    log "To create this file, run:"
    log "  bash ~/.config/sketchybar/helpers/krisp-refresh-auth.sh"
    log "  (See config/sketchybar/helpers/KRISP_AUTH_SETUP.md for details)"

    return 0
}

install_krisp_transcript_launchagent() {
    local label="com.user.krisp-transcript-download"
    local plist_source="$DOTFILES_DIR/config/sketchybar/launchagents/$label.plist"
    local plist_target="$HOME/Library/LaunchAgents/$label.plist"
    local logs_dir="$HOME/.config/sketchybar/logs"

    log "Installing Krisp transcript download LaunchAgent"

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
        log "Krisp transcript download will run every hour"
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

    # Source .env file if it exists (for optional feature flags like KRISP_LAUNCHAGENT)
    if [[ -f "$DOTFILES_DIR/.env" ]]; then
        log "Loading environment configuration from .env"
        set -a  # Export all variables
        source "$DOTFILES_DIR/.env"
        set +a
    fi

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

    # Khal calendar
    create_symlink \
        "$DOTFILES_DIR/config/khal" \
        "$HOME/.config/khal" \
        "Khal calendar config"

    # Check and install all Brewfile dependencies
    log ""
    check_and_install_brewfile_dependencies

    # Initialize calendar automation infrastructure
    log ""
    initialize_calendar_infrastructure

    # Calendar sync LaunchAgent (optional)
    log ""
    if ask_user "Install calendar sync LaunchAgent (auto-syncs every 15 minutes)?"; then
        install_calendar_launchagent
    else
        log "Skipping calendar sync LaunchAgent installation"
        log "You can manually sync with: bash ~/.config/sketchybar/helpers/sync-calendars.sh"
    fi

    # Core environment variables setup (OpenAI, Obsidian, Calendar)
    log ""
    setup_core_env_variables

    # Krisp transcript download setup and LaunchAgent (optional)
    log ""
    setup_krisp_env_variables

    # Install LaunchAgent if enabled
    if [[ "${KRISP_LAUNCHAGENT:-FALSE}" == "TRUE" ]]; then
        log ""
        if ask_user "Install Krisp transcript download LaunchAgent (auto-downloads every hour)?"; then
            install_krisp_transcript_launchagent
        else
            log "Skipping Krisp transcript download LaunchAgent installation"
            log "You can manually download with: python3 ~/.config/sketchybar/helpers/krisp-download-transcripts.py --download-new --days-back 1 --limit 20 --headless"
        fi
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

    # Restart AeroSpace with new configuration
    log "Reloading AeroSpace configuration..."
    if command -v aerospace &>/dev/null; then
        if pgrep -x "AeroSpace" >/dev/null; then
            # AeroSpace is running, reload config
            if aerospace reload-config; then
                log "✓ AeroSpace configuration reloaded"
            else
                warn "Failed to reload AeroSpace config"
                log "You may need to restart AeroSpace manually"
            fi
        else
            # AeroSpace not running, suggest launching
            log "AeroSpace not currently running"
            if ask_user "Launch AeroSpace now?"; then
                if open -a AeroSpace; then
                    log "✓ AeroSpace launched successfully"
                else
                    warn "Failed to launch AeroSpace"
                    log "You can launch manually: open -a AeroSpace"
                fi
            else
                log "You can launch AeroSpace later: open -a AeroSpace"
            fi
        fi
    else
        warn "AeroSpace not installed"
        log "Install with: brew install --cask nikitabobko/tap/aerospace"
    fi

    # Restart Sketchybar with new configuration
    log ""
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
    log "1. Reload Hammerspoon config if it's already running"
    log "2. Check calendar sync logs: tail -f ~/.config/sketchybar/logs/calendar-sync.log"
    log "3. Monitor LaunchAgent: launchctl list | grep calendar-sync"
    log "4. Test popup menus by clicking Todoist, Meeting, Week, or CPU/Memory widgets"
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