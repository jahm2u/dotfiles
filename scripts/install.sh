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

# Command-line flags
FLAG_VERBOSE=false
FLAG_DRY_RUN=false

# Show help message
show_help() {
    cat << EOF
Dotfiles Installation Script

USAGE:
    ./scripts/install.sh [OPTIONS]

DESCRIPTION:
    Clean four-phase installation script that gathers all configuration
    upfront, then executes the plan with minimal interruption.

    Phases:
      1. Detect system state (silent scan)
      2. Gather configuration (batched questions)
      3. Generate and display plan
      4. Execute plan (with approval)
      5. Generate summary report

OPTIONS:
    -h, --help       Show this help message and exit
    -v, --verbose    Show detailed output during execution
    -n, --dry-run    Show plan but don't execute (implies verbose)

EXAMPLES:
    # Standard installation (recommended)
    ./scripts/install.sh

    # See detailed output
    ./scripts/install.sh --verbose

    # Preview what would be done without executing
    ./scripts/install.sh --dry-run

LOGS:
    Full installation log: ~/.config/dotfiles-install.log

FEATURES:
    • Smart defaults (only asks what's unknown)
    • Idempotent (safe to run multiple times)
    • Clean progress indicators
    • Graceful error handling
    • Automatic backups before changes

MORE INFO:
    See CLAUDE.md for architecture details and troubleshooting.
EOF
    exit 0
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -v|--verbose)
            FLAG_VERBOSE=true
            shift
            ;;
        -n|--dry-run)
            FLAG_DRY_RUN=true
            FLAG_VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

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

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# PHASE 1: SYSTEM STATE DETECTION
# Silently scan system and store state in global variables
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Global state variables (populated by detect_system_state)
STATE_BREW_INSTALLED=""
STATE_KHAL_INSTALLED=""
STATE_SKETCHYBAR_INSTALLED=""
STATE_AEROSPACE_INSTALLED=""
STATE_ENV_EXISTS=""
STATE_ENV_HAS_CALENDAR=""
STATE_ENV_HAS_OPENAI=""
STATE_ENV_HAS_OBSIDIAN=""
STATE_ENV_HAS_KRISP=""
STATE_CALENDAR_LAUNCHAGENT_LOADED=""
STATE_KRISP_LAUNCHAGENT_LOADED=""
STATE_SYMLINKS_EXIST=()
STATE_MISSING_DEPS=()

detect_system_state() {
    # Detect Homebrew
    if command -v brew &>/dev/null; then
        STATE_BREW_INSTALLED="true"
    else
        STATE_BREW_INSTALLED="false"
        STATE_MISSING_DEPS+=("brew")
    fi

    # Detect required tools
    if command -v khal &>/dev/null; then
        STATE_KHAL_INSTALLED="true"
    else
        STATE_KHAL_INSTALLED="false"
        [[ "$STATE_BREW_INSTALLED" == "true" ]] && STATE_MISSING_DEPS+=("khal")
    fi

    if command -v sketchybar &>/dev/null; then
        STATE_SKETCHYBAR_INSTALLED="true"
    else
        STATE_SKETCHYBAR_INSTALLED="false"
        [[ "$STATE_BREW_INSTALLED" == "true" ]] && STATE_MISSING_DEPS+=("sketchybar")
    fi

    if command -v aerospace &>/dev/null; then
        STATE_AEROSPACE_INSTALLED="true"
    else
        STATE_AEROSPACE_INSTALLED="false"
    fi

    # Detect .env file and its contents
    if [[ -f "$DOTFILES_DIR/.env" ]]; then
        STATE_ENV_EXISTS="true"

        # Check for calendar URLs
        if grep -qE "CALENDAR_URL_|ICAL_URLS" "$DOTFILES_DIR/.env" 2>/dev/null; then
            STATE_ENV_HAS_CALENDAR="true"
        else
            STATE_ENV_HAS_CALENDAR="false"
        fi

        # Check for OpenAI API key
        if grep -q "OPENAI_API_KEY" "$DOTFILES_DIR/.env" 2>/dev/null; then
            STATE_ENV_HAS_OPENAI="true"
        else
            STATE_ENV_HAS_OPENAI="false"
        fi

        # Check for Obsidian vault path
        if grep -q "OBSIDIAN_VAULT_PATH" "$DOTFILES_DIR/.env" 2>/dev/null; then
            STATE_ENV_HAS_OBSIDIAN="true"
        else
            STATE_ENV_HAS_OBSIDIAN="false"
        fi

        # Check for Krisp automation flag
        if grep -q "KRISP_LAUNCHAGENT=TRUE" "$DOTFILES_DIR/.env" 2>/dev/null; then
            STATE_ENV_HAS_KRISP="true"
        else
            STATE_ENV_HAS_KRISP="false"
        fi
    else
        STATE_ENV_EXISTS="false"
        STATE_ENV_HAS_CALENDAR="false"
        STATE_ENV_HAS_OPENAI="false"
        STATE_ENV_HAS_OBSIDIAN="false"
        STATE_ENV_HAS_KRISP="false"
    fi

    # Detect LaunchAgents
    if launchctl list 2>/dev/null | grep -q "com.user.calendar-sync"; then
        STATE_CALENDAR_LAUNCHAGENT_LOADED="true"
    else
        STATE_CALENDAR_LAUNCHAGENT_LOADED="false"
    fi

    if launchctl list 2>/dev/null | grep -q "com.user.krisp-transcript-download"; then
        STATE_KRISP_LAUNCHAGENT_LOADED="true"
    else
        STATE_KRISP_LAUNCHAGENT_LOADED="false"
    fi

    # Detect existing symlinks
    local symlink_paths=(
        "$HOME/.config/aerospace"
        "$HOME/.config/sketchybar"
        "$HOME/.config/karabiner"
        "$HOME/.hammerspoon"
        "$HOME/.claude"
        "$HOME/.config/raycast"
        "$HOME/.config/khal"
    )

    STATE_SYMLINKS_EXIST=()
    for path in "${symlink_paths[@]}"; do
        if [[ -L "$path" ]]; then
            STATE_SYMLINKS_EXIST+=("$(basename "$path")")
        fi
    done
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# PHASE 2: CONFIGURATION GATHERING
# Batch all questions upfront based on detected state
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Configuration variables (populated by gather_configuration)
CONFIG_INSTALL_DEPS=""
CONFIG_CREATE_ENV=""
CONFIG_SETUP_CALENDAR=""
CONFIG_SETUP_OPENAI=""
CONFIG_SETUP_OBSIDIAN=""
CONFIG_SETUP_KRISP=""
CONFIG_INSTALL_CALENDAR_LAUNCHAGENT=""
CONFIG_INSTALL_KRISP_LAUNCHAGENT=""
CONFIG_OPENAI_API_KEY=""
CONFIG_OBSIDIAN_VAULT_PATH=""
CONFIG_CALENDAR_URL_NAME=""
CONFIG_CALENDAR_URL=""

gather_configuration() {
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "CONFIGURATION"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log "I'll ask you a few questions to configure your installation."
    log "All questions upfront, then we'll proceed with the plan."
    echo ""

    # ─────────────────────────────────────────────────────────────
    # GROUP A: Dependencies
    # ─────────────────────────────────────────────────────────────

    if [[ ${#STATE_MISSING_DEPS[@]} -gt 0 ]]; then
        log "━━ Dependencies ━━"
        log "Missing: ${STATE_MISSING_DEPS[*]}"
        echo ""

        if [[ "$STATE_BREW_INSTALLED" == "false" ]]; then
            warn "Homebrew is required but not installed."
            log "Install from: https://brew.sh"
            CONFIG_INSTALL_DEPS="false"
        else
            if ask_user "Install missing dependencies automatically?"; then
                CONFIG_INSTALL_DEPS="true"
            else
                CONFIG_INSTALL_DEPS="false"
            fi
        fi
        echo ""
    else
        CONFIG_INSTALL_DEPS="skip"  # All deps already installed
    fi

    # ─────────────────────────────────────────────────────────────
    # GROUP B: Environment Configuration
    # ─────────────────────────────────────────────────────────────

    if [[ "$STATE_ENV_EXISTS" == "false" ]]; then
        log "━━ Environment Setup ━━"
        if ask_user "Create .env file from template?"; then
            CONFIG_CREATE_ENV="true"
            CONFIG_SETUP_CALENDAR="prompt"
            CONFIG_SETUP_OPENAI="prompt"
            CONFIG_SETUP_OBSIDIAN="prompt"
        else
            CONFIG_CREATE_ENV="false"
            CONFIG_SETUP_CALENDAR="skip"
            CONFIG_SETUP_OPENAI="skip"
            CONFIG_SETUP_OBSIDIAN="skip"
        fi
        echo ""
    else
        CONFIG_CREATE_ENV="skip"  # Already exists

        # Check individual env values
        if [[ "$STATE_ENV_HAS_CALENDAR" == "false" ]]; then
            CONFIG_SETUP_CALENDAR="prompt"
        else
            CONFIG_SETUP_CALENDAR="skip"
        fi

        if [[ "$STATE_ENV_HAS_OPENAI" == "false" ]]; then
            CONFIG_SETUP_OPENAI="prompt"
        else
            CONFIG_SETUP_OPENAI="skip"
        fi

        if [[ "$STATE_ENV_HAS_OBSIDIAN" == "false" ]]; then
            CONFIG_SETUP_OBSIDIAN="prompt"
        else
            CONFIG_SETUP_OBSIDIAN="skip"
        fi
    fi

    # Prompt for OpenAI API key if needed
    if [[ "$CONFIG_SETUP_OPENAI" == "prompt" ]]; then
        log "━━ OpenAI API Key ━━"
        log "Required for meeting prep and AI analysis features."
        if ask_user "Configure OpenAI API key now?"; then
            echo ""
            log "Get your key from: https://platform.openai.com/api-keys"
            read -p "Enter your OpenAI API key (or press Enter to skip): " api_key
            if [[ -n "$api_key" ]]; then
                CONFIG_OPENAI_API_KEY="$api_key"
            else
                CONFIG_OPENAI_API_KEY=""
            fi
        else
            CONFIG_OPENAI_API_KEY=""
        fi
        echo ""
    fi

    # Prompt for Obsidian vault path if needed
    if [[ "$CONFIG_SETUP_OBSIDIAN" == "prompt" ]]; then
        log "━━ Obsidian Vault ━━"
        log "Required for meeting prep and note integration."

        # Try to auto-detect
        local common_vault="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents"
        if [[ -d "$common_vault" ]]; then
            log "Found vaults at: $common_vault"
            ls -1 "$common_vault" 2>/dev/null | head -3
            echo ""
        fi

        if ask_user "Configure Obsidian vault path now?"; then
            read -p "Enter full path to your Obsidian vault: " vault_path
            vault_path="${vault_path/#\~/$HOME}"  # Expand ~
            if [[ -d "$vault_path" ]]; then
                CONFIG_OBSIDIAN_VAULT_PATH="$vault_path"
            else
                warn "Directory not found: $vault_path"
                CONFIG_OBSIDIAN_VAULT_PATH=""
            fi
        else
            CONFIG_OBSIDIAN_VAULT_PATH=""
        fi
        echo ""
    fi

    # Prompt for calendar URL if needed
    if [[ "$CONFIG_SETUP_CALENDAR" == "prompt" ]]; then
        log "━━ Calendar Sync ━━"
        log "Required for automatic calendar synchronization."
        if ask_user "Configure a calendar URL now?"; then
            echo ""
            log "Examples:"
            log "  Google: https://calendar.google.com/calendar/ical/...ics"
            log "  iCloud: https://p##-caldav.icloud.com/published/#/..."
            echo ""
            read -p "Calendar name (e.g., GOOGLE, WORK): " cal_name
            read -p "Calendar URL: " cal_url
            if [[ -n "$cal_name" ]] && [[ -n "$cal_url" ]]; then
                CONFIG_CALENDAR_URL_NAME=$(echo "$cal_name" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_')
                CONFIG_CALENDAR_URL="$cal_url"
            else
                CONFIG_CALENDAR_URL_NAME=""
                CONFIG_CALENDAR_URL=""
            fi
        else
            CONFIG_CALENDAR_URL_NAME=""
            CONFIG_CALENDAR_URL=""
        fi
        echo ""
    fi

    # ─────────────────────────────────────────────────────────────
    # GROUP C: Features / LaunchAgents
    # ─────────────────────────────────────────────────────────────

    log "━━ Features ━━"

    # Calendar LaunchAgent
    if [[ "$STATE_CALENDAR_LAUNCHAGENT_LOADED" == "true" ]]; then
        CONFIG_INSTALL_CALENDAR_LAUNCHAGENT="skip"  # Already loaded
    else
        if ask_user "Install calendar sync LaunchAgent (auto-syncs every 15 min)?"; then
            CONFIG_INSTALL_CALENDAR_LAUNCHAGENT="true"
        else
            CONFIG_INSTALL_CALENDAR_LAUNCHAGENT="false"
        fi
    fi

    # Krisp automation
    if [[ "$STATE_ENV_HAS_KRISP" == "true" ]]; then
        if [[ "$STATE_KRISP_LAUNCHAGENT_LOADED" == "true" ]]; then
            CONFIG_INSTALL_KRISP_LAUNCHAGENT="skip"
        else
            if ask_user "Install Krisp transcript download LaunchAgent?"; then
                CONFIG_INSTALL_KRISP_LAUNCHAGENT="true"
            else
                CONFIG_INSTALL_KRISP_LAUNCHAGENT="false"
            fi
        fi
    else
        # Ask if they want to enable Krisp first
        if ask_user "Enable Krisp transcript automation?"; then
            CONFIG_SETUP_KRISP="true"
            if ask_user "Install Krisp LaunchAgent?"; then
                CONFIG_INSTALL_KRISP_LAUNCHAGENT="true"
            else
                CONFIG_INSTALL_KRISP_LAUNCHAGENT="false"
            fi
        else
            CONFIG_SETUP_KRISP="false"
            CONFIG_INSTALL_KRISP_LAUNCHAGENT="false"
        fi
    fi

    echo ""
    log "Configuration complete! Generating plan..."
    echo ""
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# PHASE 3: EXECUTION PLAN GENERATION
# Generate structured plan based on configuration
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Execution plan (array of steps)
PLAN=()
PLAN_TOTAL=0

generate_plan() {
    PLAN=()
    local step_num=0

    # Always create symlinks (core functionality)
    ((step_num++))
    PLAN+=("$step_num|symlinks|Create configuration symlinks|7 configs")

    # Install dependencies if needed
    if [[ "$CONFIG_INSTALL_DEPS" == "true" ]]; then
        ((step_num++))
        PLAN+=("$step_num|deps|Install missing dependencies|${STATE_MISSING_DEPS[*]}")
    fi

    # Brewfile dependencies
    if [[ "$STATE_BREW_INSTALLED" == "true" ]]; then
        ((step_num++))
        PLAN+=("$step_num|brewfile|Check Brewfile dependencies|Validate installations")
    fi

    # Create/update .env
    if [[ "$CONFIG_CREATE_ENV" == "true" ]]; then
        ((step_num++))
        PLAN+=("$step_num|env_create|Create .env from template|New configuration")
    fi

    if [[ -n "$CONFIG_OPENAI_API_KEY" ]]; then
        ((step_num++))
        PLAN+=("$step_num|env_openai|Configure OpenAI API key|Meeting prep features")
    fi

    if [[ -n "$CONFIG_OBSIDIAN_VAULT_PATH" ]]; then
        ((step_num++))
        PLAN+=("$step_num|env_obsidian|Configure Obsidian vault path|Note integration")
    fi

    if [[ -n "$CONFIG_CALENDAR_URL" ]]; then
        ((step_num++))
        PLAN+=("$step_num|env_calendar|Configure calendar URL|${CONFIG_CALENDAR_URL_NAME}")
    fi

    if [[ "$CONFIG_SETUP_KRISP" == "true" ]]; then
        ((step_num++))
        PLAN+=("$step_num|env_krisp|Enable Krisp automation|Transcript downloads")
    fi

    # Calendar infrastructure
    ((step_num++))
    PLAN+=("$step_num|calendar_infra|Initialize calendar infrastructure|Directories and scripts")

    # Install custom fonts for Sketchybar app icons
    ((step_num++))
    PLAN+=("$step_num|install_fonts|Install custom app icon fonts|SimpleIcons for Warp, VSCode, etc.")

    # LaunchAgents
    # Calendar LaunchAgent - always offer to install if not running
    if [[ "$CONFIG_INSTALL_CALENDAR_LAUNCHAGENT" == "true" ]]; then
        ((step_num++))
        PLAN+=("$step_num|launchagent_calendar|Install calendar sync LaunchAgent|Auto-sync every 15 min")
    fi

    # Krisp LaunchAgent - install or cleanup based on config
    if [[ "$CONFIG_INSTALL_KRISP_LAUNCHAGENT" == "true" ]]; then
        ((step_num++))
        PLAN+=("$step_num|launchagent_krisp|Install Krisp LaunchAgent|Auto-download every hour")
    elif [[ "$STATE_KRISP_LAUNCHAGENT_LOADED" == "true" ]]; then
        # Cleanup: unload if disabled but currently running
        ((step_num++))
        PLAN+=("$step_num|cleanup_krisp_launchagent|Remove Krisp LaunchAgent|Disabled in config")
    fi

    # Restart services
    if [[ "$STATE_AEROSPACE_INSTALLED" == "true" ]]; then
        ((step_num++))
        PLAN+=("$step_num|restart_aerospace|Reload AeroSpace configuration|Window manager")
    fi

    if [[ "$STATE_SKETCHYBAR_INSTALLED" == "true" ]]; then
        ((step_num++))
        PLAN+=("$step_num|restart_sketchybar|Restart Sketchybar service|Status bar")
    fi

    PLAN_TOTAL=$step_num
}

display_plan() {
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "INSTALLATION PLAN"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log "I will perform the following actions:"
    echo ""

    for plan_item in "${PLAN[@]}"; do
        IFS='|' read -r num action desc detail <<< "$plan_item"
        printf "  %2d. %-45s (%s)\n" "$num" "$desc" "$detail"
    done

    echo ""
    log "Total steps: $PLAN_TOTAL"
    echo ""
}

ask_approval() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if ask_user "Proceed with this plan?"; then
        echo ""
        log "Starting installation..."
        return 0
    else
        echo ""
        warn "Installation cancelled by user"
        return 1
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# PHASE 4: EXECUTION ENGINE
# Execute plan with clean progress indicators
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Execution state tracking
EXEC_LOG_FILE="$HOME/.config/dotfiles-install.log"
EXEC_SUCCESS_COUNT=0
EXEC_WARNING_COUNT=0
EXEC_ERROR_COUNT=0

# Progress indicator helpers
show_progress() {
    local current=$1
    local total=$2
    local message=$3
    printf "[%d/%d] %s... " "$current" "$total" "$message"
}

show_result() {
    local status=$1  # 0=success, 1=warning, 2=error
    case $status in
        0) echo "✓" ; EXEC_SUCCESS_COUNT=$((EXEC_SUCCESS_COUNT + 1)) ;;
        1) echo "⚠" ; EXEC_WARNING_COUNT=$((EXEC_WARNING_COUNT + 1)) ;;
        2) echo "✗" ; EXEC_ERROR_COUNT=$((EXEC_ERROR_COUNT + 1)) ;;
    esac
}

# Redirect verbose output to log file (or terminal if --verbose)
exec_quiet() {
    local description="$1"
    shift

    # Always log to file
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$EXEC_LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $description" >> "$EXEC_LOG_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$EXEC_LOG_FILE"

    if [[ "$FLAG_VERBOSE" == "true" ]]; then
        # Verbose mode: show output to terminal AND log
        "$@" 2>&1 | tee -a "$EXEC_LOG_FILE"
        return ${PIPESTATUS[0]}
    else
        # Quiet mode: only log to file
        "$@" >> "$EXEC_LOG_FILE" 2>&1
        return $?
    fi
}

execute_plan() {
    # Handle dry-run mode
    if [[ "$FLAG_DRY_RUN" == "true" ]]; then
        echo ""
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "DRY-RUN MODE (no changes will be made)"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        log "Would execute $PLAN_TOTAL steps:"
        for plan_item in "${PLAN[@]}"; do
            IFS='|' read -r num action desc detail <<< "$plan_item"
            log "  [$num] $desc"
        done
        echo ""
        log "Run without --dry-run to execute installation."
        return 0
    fi

    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "EXECUTING INSTALLATION"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Initialize log file
    mkdir -p "$(dirname "$EXEC_LOG_FILE")"
    echo "Dotfiles Installation Log - $(date)" > "$EXEC_LOG_FILE"
    echo "" >> "$EXEC_LOG_FILE"

    local current_step=0

    for plan_item in "${PLAN[@]}"; do
        IFS='|' read -r num action desc detail <<< "$plan_item"
        ((current_step++))

        show_progress "$current_step" "$PLAN_TOTAL" "$desc"

        case "$action" in
            symlinks)
                if exec_quiet "Creating symlinks" execute_symlinks; then
                    show_result 0
                else
                    show_result 2
                fi
                ;;

            deps)
                if exec_quiet "Installing dependencies" execute_install_deps; then
                    show_result 0
                else
                    show_result 1
                fi
                ;;

            brewfile)
                if exec_quiet "Checking Brewfile" execute_brewfile_check; then
                    show_result 0
                else
                    show_result 1
                fi
                ;;

            env_create)
                if execute_env_create; then
                    show_result 0
                else
                    show_result 2
                fi
                ;;

            env_openai)
                if execute_env_openai; then
                    show_result 0
                else
                    show_result 2
                fi
                ;;

            env_obsidian)
                if execute_env_obsidian; then
                    show_result 0
                else
                    show_result 2
                fi
                ;;

            env_calendar)
                if execute_env_calendar; then
                    show_result 0
                else
                    show_result 2
                fi
                ;;

            env_krisp)
                if execute_env_krisp; then
                    show_result 0
                else
                    show_result 2
                fi
                ;;

            calendar_infra)
                if exec_quiet "Calendar infrastructure" initialize_calendar_infrastructure; then
                    show_result 0
                else
                    show_result 1
                fi
                ;;

            install_fonts)
                if exec_quiet "Install custom fonts" install_custom_fonts; then
                    show_result 0
                else
                    show_result 1
                fi
                ;;

            launchagent_calendar)
                if exec_quiet "Calendar LaunchAgent" install_calendar_launchagent; then
                    show_result 0
                else
                    show_result 1
                fi
                ;;

            launchagent_krisp)
                if exec_quiet "Krisp LaunchAgent" install_krisp_transcript_launchagent; then
                    show_result 0
                else
                    show_result 1
                fi
                ;;

            cleanup_krisp_launchagent)
                if exec_quiet "Unload Krisp LaunchAgent" cleanup_krisp_launchagent; then
                    show_result 0
                else
                    show_result 1
                fi
                ;;

            restart_aerospace)
                if exec_quiet "AeroSpace reload" execute_restart_aerospace; then
                    show_result 0
                else
                    show_result 1
                fi
                ;;

            restart_sketchybar)
                if exec_quiet "Sketchybar restart" execute_restart_sketchybar; then
                    show_result 0
                else
                    show_result 1
                fi
                ;;

            *)
                echo "⚠ Unknown action: $action"
                ;;
        esac

    done

    echo ""
}

# Execution helper functions (wrap existing logic)

execute_symlinks() {
    create_symlink "$DOTFILES_DIR/config/aerospace" "$HOME/.config/aerospace" "Aerospace"
    create_symlink "$DOTFILES_DIR/config/sketchybar" "$HOME/.config/sketchybar" "Sketchybar"
    create_symlink "$DOTFILES_DIR/config/karabiner" "$HOME/.config/karabiner" "Karabiner"
    create_symlink "$DOTFILES_DIR/config/hammerspoon" "$HOME/.hammerspoon" "Hammerspoon"
    create_symlink "$DOTFILES_DIR/config/claude" "$HOME/.claude" "Claude"
    create_symlink "$DOTFILES_DIR/config/raycast" "$HOME/.config/raycast" "Raycast"
    create_symlink "$DOTFILES_DIR/config/khal" "$HOME/.config/khal" "Khal"
}

execute_install_deps() {
    for dep in "${STATE_MISSING_DEPS[@]}"; do
        case "$dep" in
            khal)
                brew install khal || return 1
                ;;
            sketchybar)
                brew install felixkratz/formulae/sketchybar || return 1
                ;;
        esac
    done
    return 0
}

execute_brewfile_check() {
    cd "$DOTFILES_DIR" || return 1

    # Informational check only - brew bundle check is too strict
    # Just verify the critical tools we actually need
    local all_good=true

    for tool in sketchybar aerospace khal; do
        if ! command -v "$tool" &>/dev/null; then
            echo "⚠ $tool not found (run: brew bundle install)"
            all_good=false
        fi
    done

    if $all_good; then
        echo "✓ Core dependencies installed"
        echo "  Run 'brew bundle install' to sync optional packages"
        return 0
    else
        echo "  Missing critical tools - run: brew bundle install"
        return 1
    fi
}

execute_env_create() {
    cp "$DOTFILES_DIR/.env.example" "$DOTFILES_DIR/.env"
}

execute_env_openai() {
    if ! grep -q "OPENAI_API_KEY" "$DOTFILES_DIR/.env" 2>/dev/null; then
        echo "OPENAI_API_KEY=$CONFIG_OPENAI_API_KEY" >> "$DOTFILES_DIR/.env"
    fi
}

execute_env_obsidian() {
    if ! grep -q "OBSIDIAN_VAULT_PATH" "$DOTFILES_DIR/.env" 2>/dev/null; then
        echo "OBSIDIAN_VAULT_PATH=$CONFIG_OBSIDIAN_VAULT_PATH" >> "$DOTFILES_DIR/.env"
    fi
}

execute_env_calendar() {
    if ! grep -q "CALENDAR_URL_${CONFIG_CALENDAR_URL_NAME}" "$DOTFILES_DIR/.env" 2>/dev/null; then
        echo "CALENDAR_URL_${CONFIG_CALENDAR_URL_NAME}=$CONFIG_CALENDAR_URL" >> "$DOTFILES_DIR/.env"
    fi
}

execute_env_krisp() {
    if ! grep -q "KRISP_LAUNCHAGENT" "$DOTFILES_DIR/.env" 2>/dev/null; then
        echo "" >> "$DOTFILES_DIR/.env"
        echo "# Krisp Automation" >> "$DOTFILES_DIR/.env"
        echo "KRISP_LAUNCHAGENT=TRUE" >> "$DOTFILES_DIR/.env"
    fi
}

cleanup_krisp_launchagent() {
    local label="com.user.krisp-transcript-download"
    local plist_path="$HOME/Library/LaunchAgents/$label.plist"

    log "Removing Krisp LaunchAgent (disabled in config)"

    # Unload if currently loaded
    if launchctl list | grep -q "$label"; then
        if launchctl unload "$plist_path" 2>/dev/null; then
            log "✓ Unloaded $label"
        else
            warn "Failed to unload $label"
        fi
    fi

    # Remove plist file
    if [[ -f "$plist_path" ]]; then
        if rm "$plist_path" 2>/dev/null; then
            log "✓ Removed $plist_path"
        else
            warn "Failed to remove $plist_path"
        fi
    fi

    return 0
}

install_custom_fonts() {
    log "Installing custom app icon fonts for Sketchybar"

    local fonts_dir="$HOME/Library/Fonts"
    local source_font="$HOME/.config/sketchybar/simple-icons/font/SimpleIcons.ttf"
    local dest_font="$fonts_dir/SimpleIcons.ttf"

    # Check if source font exists
    if [[ ! -f "$source_font" ]]; then
        warn "SimpleIcons.ttf not found in repo"
        warn "Sketchybar app icons may not display correctly"
        return 1
    fi

    # Create fonts directory if needed
    mkdir -p "$fonts_dir"

    # Check if font is already installed and up-to-date
    if [[ -f "$dest_font" ]]; then
        # Compare modification times or checksums
        if cmp -s "$source_font" "$dest_font"; then
            log "✓ SimpleIcons.ttf already installed and up-to-date"
            return 0
        else
            log "Updating existing SimpleIcons.ttf"
        fi
    fi

    # Copy font file
    if cp "$source_font" "$dest_font" 2>/dev/null; then
        log "✓ Installed SimpleIcons.ttf to $fonts_dir"
        log "  Provides icons for: Warp, VSCode, Discord, Slack, Obsidian, etc."

        # Clear font cache to make it available immediately
        if command -v fc-cache &>/dev/null; then
            fc-cache -f "$fonts_dir" 2>/dev/null
            log "✓ Font cache refreshed"
        fi

        return 0
    else
        warn "Failed to copy font file"
        return 1
    fi
}

execute_restart_aerospace() {
    if pgrep -x "AeroSpace" >/dev/null; then
        aerospace reload-config || return 1
    fi
    return 0
}

execute_restart_sketchybar() {
    brew services restart sketchybar 2>&1 || return 1
    return 0
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# PHASE 5: SUMMARY REPORT
# Display final results and next steps
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

generate_report() {
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "INSTALLATION COMPLETE"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Summary counts
    if [[ $EXEC_ERROR_COUNT -eq 0 ]]; then
        log "✓ $EXEC_SUCCESS_COUNT step(s) completed successfully"
    else
        log "✓ $EXEC_SUCCESS_COUNT successful"
    fi

    if [[ $EXEC_WARNING_COUNT -gt 0 ]]; then
        warn "⚠ $EXEC_WARNING_COUNT warning(s)"
    fi

    if [[ $EXEC_ERROR_COUNT -gt 0 ]]; then
        error "✗ $EXEC_ERROR_COUNT error(s)"
    fi

    echo ""

    # Next steps based on what was installed
    local has_next_steps=false

    if [[ "$CONFIG_INSTALL_CALENDAR_LAUNCHAGENT" == "true" ]] ||
       [[ "$CONFIG_INSTALL_KRISP_LAUNCHAGENT" == "true" ]]; then
        if [[ $has_next_steps == false ]]; then
            log "Next steps:"
            has_next_steps=true
        fi

        if [[ "$CONFIG_INSTALL_CALENDAR_LAUNCHAGENT" == "true" ]]; then
            log "  • Monitor calendar sync: tail -f ~/.config/sketchybar/logs/calendar-sync.log"
        fi

        if [[ "$CONFIG_INSTALL_KRISP_LAUNCHAGENT" == "true" ]]; then
            log "  • Check Krisp setup: ~/.config/sketchybar/helpers/KRISP_DAEMON_SETUP.md"
        fi
    fi

    if [[ "$STATE_AEROSPACE_INSTALLED" == "true" ]] && pgrep -x "AeroSpace" >/dev/null; then
        if [[ $has_next_steps == false ]]; then
            log "Next steps:"
            has_next_steps=true
        fi
        log "  • AeroSpace configuration reloaded automatically"
    fi

    if [[ $has_next_steps == false ]]; then
        log "All set! Your dotfiles are configured."
    fi

    echo ""
    log "Full installation log: $EXEC_LOG_FILE"
    echo ""

    # Final status
    if [[ $EXEC_ERROR_COUNT -eq 0 ]]; then
        log "🎉 Installation completed successfully!"
    elif [[ $EXEC_ERROR_COUNT -gt 0 ]] && [[ $EXEC_SUCCESS_COUNT -gt 0 ]]; then
        warn "⚠️  Installation completed with errors. Check log for details."
    else
        error "❌ Installation failed. Check log for details."
    fi

    echo ""
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

    # Clear old cache and database to ensure fresh sync
    log "Clearing stale calendar cache..."
    local cache_files=(
        "$HOME/.cache/sketchybar/last_sync_status"
        "$HOME/.cache/sketchybar/last_meeting.txt"
        "$HOME/.cache/sketchybar/meeting_cache"
    )

    for cache_file in "${cache_files[@]}"; do
        if [[ -f "$cache_file" ]]; then
            rm -f "$cache_file" 2>/dev/null && log "✓ Cleared: $(basename "$cache_file")"
        fi
    done

    # Clear khal database for fresh import
    if [[ -d "$HOME/.local/share/khal/calendars" ]]; then
        local calendar_count=$(find "$HOME/.local/share/khal/calendars" -type d -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
        if [[ $calendar_count -gt 0 ]]; then
            rm -rf "$HOME/.local/share/khal/calendars/"* 2>/dev/null
            log "✓ Cleared khal database (will resync)"
        fi
    fi

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

    # Setup Python virtual environment for meeting-prep and Krisp automation
    local venv_path="$HOME/.config/sketchybar/venv"
    local requirements_file="$HOME/.config/sketchybar/requirements.txt"

    if [[ ! -d "$venv_path" ]]; then
        log "Creating Python virtual environment..."
        if python3 -m venv "$venv_path" 2>/dev/null; then
            log "✓ Created Python venv at $venv_path"
        else
            warn "Failed to create Python venv"
            warn "Meeting-prep and Krisp automation may not work"
            return 1
        fi
    else
        log "✓ Python venv exists"
    fi

    # Install Python dependencies
    if [[ -f "$requirements_file" ]]; then
        log "Installing Python dependencies..."
        if "$venv_path/bin/pip" install --quiet --upgrade pip setuptools 2>&1 | tee -a "$EXEC_LOG_FILE" > /dev/null; then
            if "$venv_path/bin/pip" install --quiet -r "$requirements_file" 2>&1 | tee -a "$EXEC_LOG_FILE" > /dev/null; then
                log "✓ Installed Python dependencies"

                # Install Playwright browsers for Krisp automation
                if "$venv_path/bin/playwright" install chromium 2>&1 | tee -a "$EXEC_LOG_FILE" > /dev/null; then
                    log "✓ Installed Playwright browsers"
                else
                    warn "Playwright browser installation failed (non-critical)"
                fi
            else
                warn "Failed to install Python dependencies"
                warn "Check log: $EXEC_LOG_FILE"
            fi
        else
            warn "Failed to upgrade pip/setuptools"
        fi
    else
        warn "requirements.txt not found at $requirements_file"
    fi

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
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "DOTFILES INSTALLATION"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log "Location: $DOTFILES_DIR"
    echo ""

    # Clean up old aerospace config location (deprecated)
    if [[ -e "$HOME/.aerospace.toml" ]]; then
        warn "Removing deprecated ~/.aerospace.toml"
        backup_existing "$HOME/.aerospace.toml"
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # PHASE 1: DETECT SYSTEM STATE
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    log "Scanning system..."
    detect_system_state

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # PHASE 2: GATHER CONFIGURATION
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    gather_configuration

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # PHASE 3: GENERATE & DISPLAY PLAN
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    generate_plan
    display_plan

    # Get user approval
    if ! ask_approval; then
        exit 0
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # PHASE 4: EXECUTE PLAN
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    execute_plan

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # PHASE 5: SUMMARY REPORT
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    generate_report
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi