#!/bin/bash

# Test script for load-env-config.sh
echo "=== Testing Environment Loader ==="

# Source the loader
source "$(dirname "$0")/load-env-config.sh"

echo ""
echo "=== Exported Variables ==="
echo "ENV_TYPE: $ENV_TYPE"
echo "PADDING: $PADDING"
echo "PADDING_LAPTOP: $PADDING_LAPTOP"
echo "PADDING_EXTERNAL: $PADDING_EXTERNAL"
echo "DISPLAY_MODE: $DISPLAY_MODE"
echo "SKETCHYBAR_VARIANT: $SKETCHYBAR_VARIANT"
echo "BAR_COLOR: $BAR_COLOR"
echo "ACCENT_COLOR: $ACCENT_COLOR"
echo ""
echo "=== Test Complete ==="
