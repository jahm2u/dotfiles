#!/bin/bash

# Script: load-env-config.sh
# Purpose: Environment loader that orchestrates ENV_TYPE detection, display mode detection, padding selection, and color scheme loading
# Epic: Epic 1 - Environment Configuration
# Story: Story 1.4 - Create Environment Configuration Loader

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKETCHYBAR_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$SKETCHYBAR_DIR/.env"
LOG_DIR="$SKETCHYBAR_DIR/logs"
LOG_FILE="$LOG_DIR/environment-loader.log"
DETECT_DISPLAY_SCRIPT="$SCRIPT_DIR/detect-display-mode.sh"
COLORS_DIR="$SKETCHYBAR_DIR"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Log function with timestamp and level
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_FILE"
}

# ============================================================================
# Main Environment Loading Logic
# ============================================================================

log "INFO" "=========================================="
log "INFO" "Starting environment configuration loader"
log "INFO" "=========================================="

# ----------------------------------------------------------------------------
# Step 1: Load .env file and read ENV_TYPE
# ----------------------------------------------------------------------------

log "INFO" "Step 1: Loading .env file from $ENV_FILE"

# Default values for graceful degradation
DEFAULT_ENV_TYPE="PERSONAL"
DEFAULT_PADDING_LAPTOP=23
DEFAULT_PADDING_EXTERNAL=23

if [[ -f "$ENV_FILE" ]]; then
    # Source the .env file
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    log "INFO" ".env file sourced successfully"

    # Read ENV_TYPE variable
    if [[ -z "$ENV_TYPE" ]]; then
        log "WARN" "ENV_TYPE not set in .env, using default: $DEFAULT_ENV_TYPE"
        ENV_TYPE="$DEFAULT_ENV_TYPE"
    else
        log "INFO" "ENV_TYPE loaded: $ENV_TYPE"
    fi

    # Read padding values
    if [[ -z "$PADDING_LAPTOP" ]]; then
        log "WARN" "PADDING_LAPTOP not set in .env, using default: $DEFAULT_PADDING_LAPTOP"
        PADDING_LAPTOP="$DEFAULT_PADDING_LAPTOP"
    else
        log "INFO" "PADDING_LAPTOP loaded: $PADDING_LAPTOP"
    fi

    if [[ -z "$PADDING_EXTERNAL" ]]; then
        log "WARN" "PADDING_EXTERNAL not set in .env, using default: $DEFAULT_PADDING_EXTERNAL"
        PADDING_EXTERNAL="$DEFAULT_PADDING_EXTERNAL"
    else
        log "INFO" "PADDING_EXTERNAL loaded: $PADDING_EXTERNAL"
    fi
else
    log "WARN" ".env file not found at $ENV_FILE, using defaults"
    ENV_TYPE="$DEFAULT_ENV_TYPE"
    PADDING_LAPTOP="$DEFAULT_PADDING_LAPTOP"
    PADDING_EXTERNAL="$DEFAULT_PADDING_EXTERNAL"
fi

# ----------------------------------------------------------------------------
# Step 2: Detect display mode
# ----------------------------------------------------------------------------

log "INFO" "Step 2: Detecting display mode"

# Validate detect-display-mode.sh exists and is executable
if [[ ! -x "$DETECT_DISPLAY_SCRIPT" ]]; then
    log "ERROR" "Display detection script not found or not executable: $DETECT_DISPLAY_SCRIPT"
    log "ERROR" "Cannot proceed without display detection capability"
    exit 1
fi

# Call detect-display-mode.sh and capture output
DISPLAY_MODE=$(bash "$DETECT_DISPLAY_SCRIPT")
DETECT_EXIT_CODE=$?

if [[ $DETECT_EXIT_CODE -ne 0 ]]; then
    log "WARN" "Display detection failed with exit code $DETECT_EXIT_CODE, defaulting to laptop mode"
    DISPLAY_MODE="laptop"
else
    log "INFO" "Display mode detected: $DISPLAY_MODE"
fi

# ----------------------------------------------------------------------------
# Step 3: Select appropriate padding value
# ----------------------------------------------------------------------------

log "INFO" "Step 3: Selecting padding configuration"

if [[ "$DISPLAY_MODE" == "external" ]]; then
    PADDING="$PADDING_EXTERNAL"
    log "INFO" "Selected external display padding: $PADDING (from PADDING_EXTERNAL)"
else
    PADDING="$PADDING_LAPTOP"
    log "INFO" "Selected laptop display padding: $PADDING (from PADDING_LAPTOP)"
fi

# Export PADDING for sketchybarrc variants
export PADDING
log "INFO" "PADDING variable exported: $PADDING"

# ----------------------------------------------------------------------------
# Step 4: Load environment-specific color scheme
# ----------------------------------------------------------------------------

log "INFO" "Step 4: Loading color scheme"

# Construct environment-specific color file path
# Convert ENV_TYPE to lowercase for file matching (colors-ipm.sh, colors-personal.sh)
ENV_TYPE_LOWER=$(echo "$ENV_TYPE" | tr '[:upper:]' '[:lower:]')
COLOR_FILE="$COLORS_DIR/colors-${ENV_TYPE_LOWER}.sh"
DEFAULT_COLOR_FILE="$COLORS_DIR/colors.sh"

log "INFO" "Looking for environment-specific color file: $COLOR_FILE"

if [[ -f "$COLOR_FILE" ]]; then
    # Source environment-specific color file
    # shellcheck source=/dev/null
    source "$COLOR_FILE"
    log "INFO" "Sourced environment-specific color file: $COLOR_FILE"

    # Verify key color variables are exported
    if [[ -z "$BAR_COLOR" ]] || [[ -z "$ACCENT_COLOR" ]]; then
        log "WARN" "Color variables not fully exported from $COLOR_FILE, falling back to default"
        # shellcheck source=/dev/null
        source "$DEFAULT_COLOR_FILE"
        log "INFO" "Fallback: sourced default color file: $DEFAULT_COLOR_FILE"
    fi
else
    log "WARN" "Environment-specific color file not found: $COLOR_FILE"
    log "INFO" "Falling back to default color file: $DEFAULT_COLOR_FILE"

    if [[ -f "$DEFAULT_COLOR_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$DEFAULT_COLOR_FILE"
        log "INFO" "Sourced default color file: $DEFAULT_COLOR_FILE"
    else
        log "ERROR" "Default color file not found: $DEFAULT_COLOR_FILE"
        log "WARN" "Continuing without color configuration (may cause display issues)"
    fi
fi

# ----------------------------------------------------------------------------
# Step 5: Export variant selection for sketchybarrc dispatcher
# ----------------------------------------------------------------------------

log "INFO" "Step 5: Exporting variant selection"

# Export display mode for sketchybarrc dispatcher to use
export DISPLAY_MODE
log "INFO" "DISPLAY_MODE exported: $DISPLAY_MODE"

# Determine which sketchybarrc variant should be loaded
if [[ "$DISPLAY_MODE" == "external" ]]; then
    SKETCHYBAR_VARIANT="sketchybarrc-desktop"
else
    SKETCHYBAR_VARIANT="sketchybarrc-laptop"
fi

export SKETCHYBAR_VARIANT
log "INFO" "SKETCHYBAR_VARIANT exported: $SKETCHYBAR_VARIANT"

# ----------------------------------------------------------------------------
# Step 6: Summary and completion
# ----------------------------------------------------------------------------

log "INFO" "=========================================="
log "INFO" "Environment configuration loaded successfully"
log "INFO" "Summary:"
log "INFO" "  - Environment Type: $ENV_TYPE"
log "INFO" "  - Display Mode: $DISPLAY_MODE"
log "INFO" "  - Selected Padding: $PADDING pixels"
log "INFO" "  - Color Scheme: $(basename "${COLOR_FILE:-$DEFAULT_COLOR_FILE}")"
log "INFO" "  - Variant: $SKETCHYBAR_VARIANT"
log "INFO" "=========================================="

exit 0
