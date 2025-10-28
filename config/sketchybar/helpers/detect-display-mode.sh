#!/bin/bash

# Script: detect-display-mode.sh
# Purpose: Detects current display mode (laptop screen vs external monitor)
# Epic: Epic 1 - Environment Configuration
# Story: Story 1.3 - Implement Display Mode Detection Helper

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs"
LOG_FILE="${LOG_DIR}/display-detection.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Log function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_FILE"
}

# Main display detection logic
detect_display_mode() {
    log "INFO" "Starting display mode detection"

    # Query Sketchybar for display information
    local display_info
    if ! display_info=$(sketchybar --query displays 2>&1); then
        log "ERROR" "Failed to query Sketchybar displays: $display_info"
        log "WARN" "Defaulting to laptop mode due to query failure"
        echo "laptop"
        return 1
    fi

    log "INFO" "Sketchybar query successful"

    # Count number of displays
    # The output is JSON with "arrangement-id" for each display
    local display_count
    display_count=$(echo "$display_info" | grep -c '"arrangement-id"' | tr -d ' ')

    # Ensure we have a valid number, default to 1 if parsing fails
    if ! [[ "$display_count" =~ ^[0-9]+$ ]] || [[ "$display_count" -eq 0 ]]; then
        log "WARN" "Invalid or zero display count detected, defaulting to 1"
        display_count=1
    fi

    log "INFO" "Detected $display_count display(s)"

    # Determine mode based on count
    if [[ $display_count -gt 1 ]]; then
        log "INFO" "Display mode: external (multiple displays detected)"
        echo "external"
    else
        log "INFO" "Display mode: laptop (single display detected)"
        echo "laptop"
    fi

    return 0
}

# Execute detection
detect_display_mode
exit_code=$?

log "INFO" "Display detection completed with exit code: $exit_code"
exit $exit_code
