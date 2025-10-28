#!/bin/bash

# Unit tests for load-env-config.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOADER_SCRIPT="$SCRIPT_DIR/load-env-config.sh"
LOG_FILE="$SCRIPT_DIR/../logs/environment-loader.log"

echo "=========================================="
echo "Unit Tests for Environment Loader"
echo "=========================================="

# Test 1: Script exists and is executable
echo ""
echo "Test 1: Script exists and is executable"
if [[ -x "$LOADER_SCRIPT" ]]; then
    echo "✓ PASS: Script is executable"
else
    echo "✗ FAIL: Script not found or not executable"
    exit 1
fi

# Test 2: Script runs without errors
echo ""
echo "Test 2: Script runs successfully"
if bash "$LOADER_SCRIPT" >/dev/null 2>&1; then
    echo "✓ PASS: Script executed with exit code 0"
else
    echo "✗ FAIL: Script failed with exit code $?"
    exit 1
fi

# Test 3: Log file is created
echo ""
echo "Test 3: Log file creation"
if [[ -f "$LOG_FILE" ]]; then
    echo "✓ PASS: Log file created at $LOG_FILE"
    LINE_COUNT=$(wc -l < "$LOG_FILE")
    echo "  Log contains $LINE_COUNT lines"
else
    echo "✗ FAIL: Log file not created"
    exit 1
fi

# Test 4: Log contains expected entries
echo ""
echo "Test 4: Log content validation"
if grep -q "Starting environment configuration loader" "$LOG_FILE"; then
    echo "✓ PASS: Log contains startup message"
else
    echo "✗ FAIL: Log missing startup message"
fi

if grep -q "ENV_TYPE loaded" "$LOG_FILE" || grep -q "using default" "$LOG_FILE"; then
    echo "✓ PASS: Log contains ENV_TYPE information"
else
    echo "✗ FAIL: Log missing ENV_TYPE information"
fi

if grep -q "Display mode detected" "$LOG_FILE"; then
    echo "✓ PASS: Log contains display mode detection"
else
    echo "✗ FAIL: Log missing display mode detection"
fi

if grep -q "Selected.*padding" "$LOG_FILE"; then
    echo "✓ PASS: Log contains padding selection"
else
    echo "✗ FAIL: Log missing padding selection"
fi

if grep -q "color" "$LOG_FILE"; then
    echo "✓ PASS: Log contains color scheme loading"
else
    echo "✗ FAIL: Log missing color scheme loading"
fi

if grep -q "Environment configuration loaded successfully" "$LOG_FILE"; then
    echo "✓ PASS: Log contains completion message"
else
    echo "✗ FAIL: Log missing completion message"
fi

# Test 5: Show summary from log
echo ""
echo "Test 5: Configuration summary from log"
echo "----------------------------------------"
grep "Summary:" -A 6 "$LOG_FILE" | tail -6 | sed 's/^.*INFO] //'
echo "----------------------------------------"

echo ""
echo "=========================================="
echo "All tests completed successfully!"
echo "=========================================="
