#!/bin/bash

# Calendar Access Test Script
# Tests if the current process can access macOS Calendar data

echo "Testing Calendar access from: $(whoami) in $(pwd)"
echo "Process: $0"
echo "Parent PID: $PPID"

# Method 1: AppleScript (most compatible)
echo -e "\n🔍 Testing AppleScript method..."
if osascript -e 'tell application "Calendar" to get the name of every calendar' 2>/dev/null; then
    echo "✅ AppleScript Calendar access: SUCCESS"
else
    echo "❌ AppleScript Calendar access: FAILED"
fi

# Method 2: Swift EventKit (more direct)
echo -e "\n🔍 Testing Swift EventKit method..."
if command -v swift >/dev/null 2>&1; then
    swift_result=$(swift - 2>/dev/null <<'EOF'
import EventKit
import Foundation

let store = EKEventStore()
let semaphore = DispatchSemaphore(value: 0)
var result = "UNKNOWN"

store.requestAccess(to: .event) { granted, error in
    if granted {
        result = "GRANTED"
    } else {
        result = "DENIED: \(error?.localizedDescription ?? "Unknown error")"
    }
    semaphore.signal()
}

semaphore.wait()
print(result)
EOF
)
    if [[ "$swift_result" == "GRANTED" ]]; then
        echo "✅ Swift EventKit access: SUCCESS"
    else
        echo "❌ Swift EventKit access: $swift_result"
    fi
else
    echo "⚠️  Swift not available - skipping EventKit test"
fi

# Method 3: Check TCC database directly
echo -e "\n🔍 Checking TCC database..."
app_name=$(ps -p $PPID -o comm= 2>/dev/null || echo "unknown")
echo "Parent process: $app_name"

# Summary
echo -e "\n📋 SUMMARY:"
echo "Run this script from Terminal, Cursor, and SketchyBar to compare results"
echo "Expected: All should show SUCCESS if permissions are correct"