#!/bin/bash

# Test script for Story 1.5 - Dynamic Padding in Sketchybar Variants
# Tests all variants with and without PADDING environment variable

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKETCHYBAR_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Story 1.5: Variant Dynamic Padding Tests"
echo "=========================================="
echo ""

# Test function
test_variant() {
    local variant_file="$1"
    local expected_padding="$2"
    local test_name="$3"

    echo "TEST: $test_name"
    echo "  Variant: $(basename "$variant_file")"
    echo "  Expected padding: $expected_padding"

    # Source the variant and capture sketchybar command
    # We'll grep for the padding values in the file
    local actual_padding_left=$(grep "padding_left=" "$variant_file" | head -1 | sed 's/.*padding_left=//' | sed 's/ .*//')
    local actual_padding_right=$(grep "padding_right=" "$variant_file" | head -1 | sed 's/.*padding_right=//' | sed 's/ .*//')

    echo "  Config uses: padding_left=$actual_padding_left padding_right=$actual_padding_right"

    if [[ "$actual_padding_left" == "\$PADDING" ]] && [[ "$actual_padding_right" == "\$PADDING" ]]; then
        echo "  ✅ PASS: Variant uses dynamic \$PADDING variable"
    else
        echo "  ❌ FAIL: Variant still uses hardcoded values"
    fi
    echo ""
}

# Test 1: Verify all variants use $PADDING variable
echo "=== Test Suite 1: Verify Dynamic Padding Variable Usage ==="
echo ""

test_variant "$SKETCHYBAR_DIR/sketchybarrc-laptop" "23" "Laptop variant uses dynamic padding"
test_variant "$SKETCHYBAR_DIR/sketchybarrc-desktop" "10" "Desktop variant uses dynamic padding"
test_variant "$SKETCHYBAR_DIR/sketchybarrc-laptop-privacy" "23" "Laptop privacy variant uses dynamic padding"
test_variant "$SKETCHYBAR_DIR/sketchybarrc-desktop-privacy" "10" "Desktop privacy variant uses dynamic padding"
test_variant "$SKETCHYBAR_DIR/sketchybarrc-laptop-minimal" "23" "Laptop minimal variant uses dynamic padding"

# Test 2: Verify fallback defaults
echo "=== Test Suite 2: Verify Fallback Defaults ==="
echo ""

for variant in "$SKETCHYBAR_DIR"/sketchybarrc-*; do
    variant_name=$(basename "$variant")

    # Check if variant has PADDING fallback definition
    if grep -q "PADDING=\${PADDING:-" "$variant"; then
        fallback_value=$(grep "PADDING=\${PADDING:-" "$variant" | sed 's/.*:-//' | sed 's/}.*//')

        if [[ "$variant_name" == *"desktop"* ]]; then
            expected_fallback="10"
        else
            expected_fallback="23"
        fi

        echo "Variant: $variant_name"
        echo "  Fallback: $fallback_value"
        echo "  Expected: $expected_fallback"

        if [[ "$fallback_value" == "$expected_fallback" ]]; then
            echo "  ✅ PASS: Correct fallback default"
        else
            echo "  ❌ FAIL: Incorrect fallback default"
        fi
        echo ""
    fi
done

# Test 3: Verify NOTCH_WIDTH is configurable
echo "=== Test Suite 3: Verify NOTCH_WIDTH Configurability ==="
echo ""

for variant in "$SKETCHYBAR_DIR"/sketchybarrc-*; do
    variant_name=$(basename "$variant")

    if grep -q "NOTCH_WIDTH=\${NOTCH_WIDTH:-" "$variant"; then
        fallback_value=$(grep "NOTCH_WIDTH=\${NOTCH_WIDTH:-" "$variant" | sed 's/.*:-//' | sed 's/}.*//')
        echo "Variant: $variant_name"
        echo "  NOTCH_WIDTH fallback: $fallback_value"
        echo "  ✅ PASS: NOTCH_WIDTH is configurable"
    else
        # Check if variant has any notch_width reference
        if grep -q "notch_width=" "$variant"; then
            echo "Variant: $variant_name"
            echo "  ⚠️  WARNING: Uses notch_width but not configurable"
        fi
    fi
    echo ""
done

# Test 4: Syntax validation
echo "=== Test Suite 4: Shell Syntax Validation ==="
echo ""

for variant in "$SKETCHYBAR_DIR"/sketchybarrc-*; do
    variant_name=$(basename "$variant")
    echo "Checking: $variant_name"

    if bash -n "$variant" 2>/dev/null; then
        echo "  ✅ PASS: Valid shell syntax"
    else
        echo "  ❌ FAIL: Syntax errors detected"
        bash -n "$variant"
    fi
    echo ""
done

echo "=========================================="
echo "Test Suite Complete"
echo "=========================================="
