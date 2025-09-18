#!/bin/bash

# macOS Calendar Permissions Fix Script
# Systematically grants calendar access to Cursor and SketchyBar

set -e

echo "🔧 macOS Calendar Permissions Fix"
echo "=================================="

# App information
CURSOR_BUNDLE_ID="com.todesktop.230313mzl4w4u92"
CURSOR_APP_PATH="/Applications/Cursor.app"
SKETCHYBAR_PATH="/opt/homebrew/bin/sketchybar"
SKETCHYBAR_REAL_PATH="/opt/homebrew/Cellar/sketchybar/2.22.1/bin/sketchybar"

echo -e "\n📋 Target Applications:"
echo "• Cursor: $CURSOR_BUNDLE_ID"
echo "• SketchyBar: $SKETCHYBAR_PATH"

# Check if apps exist
if [[ ! -d "$CURSOR_APP_PATH" ]]; then
    echo "⚠️  Cursor.app not found at $CURSOR_APP_PATH"
fi

if [[ ! -f "$SKETCHYBAR_PATH" ]]; then
    echo "⚠️  SketchyBar not found at $SKETCHYBAR_PATH"
fi

echo -e "\n🔍 Current TCC Calendar Permissions:"
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
    "SELECT client, auth_value FROM access WHERE service='kTCCServiceCalendar';" 2>/dev/null || echo "Cannot read TCC database"

echo -e "\n" 
echo "═══════════════════════════════════════════════════════════════════"
echo "MANUAL STEPS TO FIX CALENDAR PERMISSIONS:"
echo "═══════════════════════════════════════════════════════════════════"

echo -e "\n🎯 METHOD 1: GUI Permission Grant (RECOMMENDED)"
echo "1. Open System Settings → Privacy & Security → Calendars"
echo "2. Look for 'Cursor' in the list - if present, enable it"
echo "3. For SketchyBar, you may need to trigger a permission prompt:"
echo "   - Run a calendar-accessing script from SketchyBar"
echo "   - When macOS asks for permission, click 'OK'"

echo -e "\n🎯 METHOD 2: Install tccplus for Command-Line Control"
echo "If GUI method fails or you prefer automation:"
echo ""
echo "# Install tccplus"
echo "brew install jslegendre/tap/tccplus"
echo ""
echo "# Grant Calendar access to Cursor"
echo "sudo tccplus -p '$CURSOR_BUNDLE_ID' -d Calendar -s"
echo ""
echo "# Grant Calendar access to SketchyBar"
echo "sudo tccplus -p '$SKETCHYBAR_PATH' -d Calendar -s"

echo -e "\n🎯 METHOD 3: Full Disk Access (LAST RESORT)"
echo "Only if methods 1 & 2 fail:"
echo "1. System Settings → Privacy & Security → Full Disk Access"
echo "2. Click '+' and add:"
echo "   - /Applications/Cursor.app"
echo "   - $SKETCHYBAR_PATH"

echo -e "\n🧪 TESTING AFTER EACH METHOD:"
echo "Run these commands to verify success:"
echo ""
echo "# Test from Terminal (baseline - should work)"
echo "./test_calendar_access.sh"
echo ""
echo "# Test from Cursor's integrated terminal"
echo "# (Open Cursor → Terminal panel → run the test script)"
echo ""
echo "# Test from SketchyBar context"
echo "sketchybar --set test_item script='./test_calendar_access.sh'"

echo -e "\n⚡ TROUBLESHOOTING:"
echo "• If SketchyBar still fails, the issue may be with child processes"
echo "• Grant permissions to shell interpreters: /bin/bash, /bin/zsh"
echo "• Check that scripts run by SketchyBar use absolute paths"
echo "• Restart apps after granting permissions"

echo -e "\n✅ SUCCESS CRITERIA:"
echo "Both AppleScript and Swift EventKit methods should show SUCCESS"
echo "when run from Cursor and SketchyBar contexts"

echo -e "\n═══════════════════════════════════════════════════════════════════"