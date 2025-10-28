#!/usr/bin/env bash

# Script: handle-display-change.sh
# Purpose: Handle display configuration changes and trigger environment reconfiguration
# Epic: Epic 1 - Environment Configuration
# Story: Story 1.7 - Implement Display Change Event Subscription

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKETCHYBAR_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPERS_DIR="$SKETCHYBAR_DIR/helpers"
LOG_DIR="$SKETCHYBAR_DIR/logs"
LOG_FILE="$LOG_DIR/display-detection.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Log function with timestamp and level
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_FILE"
}

# ============================================================================
# Display Change Event Handler
# ============================================================================

log "INFO" "=========================================="
log "INFO" "Display change event triggered"
log "INFO" "=========================================="

# ----------------------------------------------------------------------------
# Step 1: Detect current display mode
# ----------------------------------------------------------------------------

log "INFO" "Step 1: Detecting current display mode"

DETECT_SCRIPT="$HELPERS_DIR/detect-display-mode.sh"

if [[ ! -x "$DETECT_SCRIPT" ]]; then
    log "ERROR" "Display detection script not found or not executable: $DETECT_SCRIPT"
    log "ERROR" "Cannot proceed without display detection capability"
    exit 1
fi

# Call detect-display-mode.sh
DISPLAY_MODE=$(bash "$DETECT_SCRIPT")
DETECT_EXIT_CODE=$?

if [[ $DETECT_EXIT_CODE -ne 0 ]]; then
    log "ERROR" "Display detection failed with exit code $DETECT_EXIT_CODE"
    log "WARN" "Handler will not reload configuration to avoid applying incorrect settings"
    exit 1
else
    log "INFO" "Display mode detected: $DISPLAY_MODE"
fi

# ----------------------------------------------------------------------------
# Step 2: Load .env and determine padding
# ----------------------------------------------------------------------------

log "INFO" "Step 2: Loading environment configuration"

ENV_FILE="$SKETCHYBAR_DIR/.env"

# Default padding values
DEFAULT_PADDING_LAPTOP=23
DEFAULT_PADDING_EXTERNAL=23

# Source .env file if it exists
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    log "INFO" ".env file sourced successfully"
else
    log "WARN" ".env file not found, using defaults"
    PADDING_LAPTOP="$DEFAULT_PADDING_LAPTOP"
    PADDING_EXTERNAL="$DEFAULT_PADDING_EXTERNAL"
fi

# Select appropriate padding based on display mode
if [[ "$DISPLAY_MODE" == "external" ]]; then
    PADDING="${PADDING_EXTERNAL:-$DEFAULT_PADDING_EXTERNAL}"
    log "INFO" "Selected external display padding: $PADDING"
else
    PADDING="${PADDING_LAPTOP:-$DEFAULT_PADDING_LAPTOP}"
    log "INFO" "Selected laptop display padding: $PADDING"
fi

# ----------------------------------------------------------------------------
# Step 3: Update Sketchybar bar padding (without full reload)
# ----------------------------------------------------------------------------

log "INFO" "Step 3: Updating Sketchybar padding"

# Update padding directly without triggering reload (prevents infinite loop)
if sketchybar --bar padding_left="$PADDING" padding_right="$PADDING" 2>/dev/null; then
    log "INFO" "Sketchybar padding updated successfully to $PADDING"
else
    log "WARN" "Failed to update Sketchybar padding"
fi

# ----------------------------------------------------------------------------
# Completion
# ----------------------------------------------------------------------------

log "INFO" "=========================================="
log "INFO" "Display change handler completed successfully"
log "INFO" "New display mode: $DISPLAY_MODE"
log "INFO" "=========================================="

exit 0
