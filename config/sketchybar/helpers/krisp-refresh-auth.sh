#!/usr/bin/env bash
#
# Krisp Auth Refresh Helper
# Interactive script to collect fresh authentication data from browser
#
# Usage: bash krisp-refresh-auth.sh
#

set -euo pipefail

AUTH_FILE="$HOME/.config/sketchybar/krisp-auth.json"
TEMP_FILE="$HOME/.config/sketchybar/krisp-auth.json.tmp"

echo "========================================="
echo "  Krisp Authentication Refresh"
echo "========================================="
echo ""
echo "This script will help you update Krisp authentication."
echo ""
echo "You'll need to:"
echo "  1. Open browser DevTools (F12 or Cmd+Opt+I)"
echo "  2. Navigate to https://app.krisp.ai"
echo "  3. Login to your Krisp account"
echo "  4. Copy cookies and localStorage data"
echo ""
echo "Press Enter to continue..."
read -r

echo ""
echo "========================================="
echo "  Step 1: Export Cookies"
echo "========================================="
echo ""
echo "Using EditThisCookie Chrome extension (recommended):"
echo "  1. Install: https://chrome.google.com/webstore/detail/editthiscookie/"
echo "  2. Click extension icon on app.krisp.ai"
echo "  3. Click 'Export' button (download icon)"
echo "  4. Copy the JSON array"
echo ""
echo "Alternative - Manual export from DevTools:"
echo "  1. Open DevTools → Application tab"
echo "  2. Expand 'Cookies' → https://app.krisp.ai"
echo "  3. Right-click cookie table → Copy all as JSON"
echo ""
echo "Paste cookies JSON below (paste and press Ctrl+D when done):"
echo ""

# Read cookies from stdin
COOKIES_JSON=$(cat)

# Validate cookies JSON
if ! echo "$COOKIES_JSON" | jq . > /dev/null 2>&1; then
    echo "ERROR: Invalid JSON format for cookies"
    exit 1
fi

if ! echo "$COOKIES_JSON" | jq -e 'type == "array"' > /dev/null 2>&1; then
    echo "ERROR: Cookies must be a JSON array"
    exit 1
fi

COOKIE_COUNT=$(echo "$COOKIES_JSON" | jq 'length')
echo "✓ Validated $COOKIE_COUNT cookies"
echo ""

echo "========================================="
echo "  Step 2: Export localStorage"
echo "========================================="
echo ""
echo "In DevTools Console, run this command:"
echo ""
echo "  JSON.stringify(localStorage)"
echo ""
echo "Copy the output (the entire string including quotes)."
echo ""
echo "Paste localStorage JSON below (paste and press Ctrl+D when done):"
echo ""

# Read localStorage from stdin
LOCALSTORAGE_INPUT=$(cat)

# Remove outer quotes if present (from JSON.stringify output)
LOCALSTORAGE_JSON=$(echo "$LOCALSTORAGE_INPUT" | sed 's/^"//;s/"$//')

# Validate localStorage JSON
if ! echo "$LOCALSTORAGE_JSON" | jq . > /dev/null 2>&1; then
    echo "ERROR: Invalid JSON format for localStorage"
    exit 1
fi

if ! echo "$LOCALSTORAGE_JSON" | jq -e 'type == "object"' > /dev/null 2>&1; then
    echo "ERROR: localStorage must be a JSON object"
    exit 1
fi

LOCALSTORAGE_KEYS=$(echo "$LOCALSTORAGE_JSON" | jq 'keys | length')
echo "✓ Validated $LOCALSTORAGE_KEYS localStorage items"
echo ""

# Check for required auth key
if ! echo "$LOCALSTORAGE_JSON" | jq -e '.auth' > /dev/null 2>&1; then
    echo "WARNING: localStorage missing 'auth' key - authentication may fail"
fi

echo "========================================="
echo "  Creating Auth File"
echo "========================================="
echo ""

# Create combined JSON
CURRENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EXPIRES_ESTIMATE=$(date -u -v+60d +"%Y-%m-%d" 2>/dev/null || date -u -d "+60 days" +"%Y-%m-%d")

jq -n \
  --argjson cookies "$COOKIES_JSON" \
  --argjson localStorage "$LOCALSTORAGE_JSON" \
  --arg updated_at "$CURRENT_DATE" \
  --arg expires_estimate "$EXPIRES_ESTIMATE" \
  '{
    cookies: $cookies,
    localStorage: $localStorage,
    updated_at: $updated_at,
    expires_estimate: $expires_estimate
  }' > "$TEMP_FILE"

# Backup existing file if present
if [ -f "$AUTH_FILE" ]; then
    BACKUP_FILE="${AUTH_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$AUTH_FILE" "$BACKUP_FILE"
    echo "✓ Backed up existing auth to: $BACKUP_FILE"
fi

# Move temp file to final location
mv "$TEMP_FILE" "$AUTH_FILE"
chmod 600 "$AUTH_FILE"

echo "✓ Auth file created: $AUTH_FILE"
echo "✓ Permissions set to 600 (owner read/write only)"
echo ""

echo "========================================="
echo "  Testing Authentication"
echo "========================================="
echo ""

# Test auth
if python3 "$(dirname "$0")/krisp-download-transcripts.py" --test-auth; then
    echo ""
    echo "========================================="
    echo "  ✅ SUCCESS!"
    echo "========================================="
    echo ""
    echo "Authentication is working correctly."
    echo "Krisp automation is ready to use."
    echo ""
else
    echo ""
    echo "========================================="
    echo "  ❌ AUTH TEST FAILED"
    echo "========================================="
    echo ""
    echo "Authentication test failed. Possible issues:"
    echo "  - Cookies/localStorage data is incomplete"
    echo "  - You were not logged in when exporting"
    echo "  - Session has already expired"
    echo ""
    echo "Try running this script again and ensure you:"
    echo "  1. Are logged into app.krisp.ai"
    echo "  2. Export cookies AND localStorage"
    echo "  3. Copy the complete JSON output"
    echo ""
    exit 1
fi
