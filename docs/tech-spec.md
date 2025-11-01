# dotfiles - Technical Specification

**Author:** Jeff
**Date:** 2025-11-01
**Project Level:** Level 1 (Coherent feature)
**Project Type:** Desktop application (macOS system configuration)
**Development Context:** Brownfield - Adding to existing clean codebase with well-documented Sketchybar configuration

---

## Source Tree Structure

```
config/sketchybar/
├── plugins/
│   ├── todoist.sh                    # MODIFY: Fix focus task display logic
│   ├── todoist_popup.sh              # MODIFY: Add precaching, remove [WORKING] label, fix click handler
│   └── meeting.sh                    # MODIFY: Fix "no meetings today" logic, add day boundary check
├── helpers/
│   ├── todoist-precache.sh          # NEW: Background task cache for instant popup
│   └── sync-calendars.sh            # READ-ONLY: Reference for precaching pattern
└── items/
    └── todoist.sh                    # MODIFY: Add precache trigger subscription

~/.cache/sketchybar/
├── todoist_working_task              # EXISTING: Stores focus task ID
├── todoist_tasks_cache               # NEW: Precached task list for popup
└── meeting_events_list               # EXISTING: Calendar event cache (reference pattern)

~/Library/LaunchAgents/
└── com.user.todoist-precache.plist   # NEW: LaunchAgent for periodic task precaching
```

---

## Technical Approach

### Problem 1: Todoist Focus Task Not Updating Main Widget

**Current Behavior:**
- Clicking task in popup writes task ID to `todoist_working_task` cache file
- Popup highlights the task with yellow background and "[WORKING]" label
- `todoist.sh` reads `todoist_working_task` but doesn't trigger widget update
- Main widget continues showing highest-priority task instead of focused task

**Root Cause:**
- `todoist.sh` plugin correctly reads working task ID and selects it for display
- BUT: Sketchybar doesn't know to re-run `todoist.sh` after the cache file changes
- Missing trigger/event to force widget refresh

**Solution:**
- Modify `todoist_popup.sh` click_script to trigger custom Sketchybar event after writing focus task
- Change from: `echo '$TASK_ID' > '$WORKING_TASK_FILE' && sketchybar --trigger todoist_update`
- Change to: `echo '$TASK_ID' > '$WORKING_TASK_FILE' && sketchybar --trigger todoist_focus_changed && sketchybar --set todoist popup.drawing=off`
- Modify `todoist.sh` to subscribe to `todoist_focus_changed` event
- Remove "[WORKING]" text from popup display (lines 134, 139 in todoist_popup.sh)
- Keep yellow highlight for visual feedback in popup only
- Close popup automatically after selection for better UX

### Problem 2: Popup Performance - Slow Load Times

**Current Behavior:**
- Popup click triggers `todoist_popup.sh` synchronously
- Script makes real-time API call to Todoist (200-800ms latency)
- Parses JSON with Python
- Populates 5 popup items
- User experiences noticeable lag before popup appears

**Root Cause:**
- No precaching - every popup open requires fresh API call
- API latency blocks popup rendering

**Solution - Precaching System (following calendar sync pattern):**

1. **Background Precache Script** (`helpers/todoist-precache.sh`):
   - Fetches tasks from Todoist API
   - Parses and formats task data
   - Writes to `~/.cache/sketchybar/todoist_tasks_cache`
   - Cache format: `TASK_ID|ICON|CONTENT|URL` (one per line)
   - Includes sync status header like calendar system
   - Runs every 5 minutes via LaunchAgent

2. **LaunchAgent** (`com.user.todoist-precache.plist`):
   - StartInterval: 300 seconds (5 minutes)
   - RunAtLoad: true (immediate first sync)
   - EnvironmentVariables: PATH with Homebrew paths
   - Logs to `~/.config/sketchybar/logs/todoist-precache.log`

3. **Modified Popup Script** (`todoist_popup.sh`):
   - Remove API call logic
   - Read from `todoist_tasks_cache` instead
   - Instant popup rendering (no network latency)
   - Fallback: Show "Refreshing..." if cache missing/stale

4. **Event Integration**:
   - Trigger precache on `system_woke` event (computer wake)
   - Subscribe todoist widget to `todoist_synced` custom event
   - Update main widget when precache completes

### Problem 3: Calendar Shows Tomorrow's Meeting When Today is Empty

**Current Behavior:**
- `meeting.sh` queries khal for events from "now" to "7d" in future
- If no meetings today, it shows first meeting in next 7 days (tomorrow)
- User sees "weekly kpi start in tomorrow" on main widget
- Should instead show humorous "no meetings today" message

**Root Cause:**
- Lines 163-182 in `meeting.sh` iterate through cached events
- Finds first event where `EVENT_TIMESTAMP` is in future or within 10 min of start
- No logic to check if event is TODAY vs TOMORROW
- Missing day boundary check

**Solution - Add Day Boundary Logic:**

1. **Modify `update_display_from_cache()` function** in `meeting.sh`:
   - After finding NEXT_MEETING, add day boundary check
   - Calculate if event is today: Compare `EVENT_DATE` with `$(date +%Y-%m-%d)`
   - If next meeting is tomorrow or later:
     - Check if there were ANY meetings today using `check_meetings_today()`
     - If had meetings → Show random END_OF_DAY_MESSAGES
     - If no meetings today → Show random FREE_DAY_MESSAGES
   - Only display meeting countdown if meeting is TODAY

2. **Specific Code Changes:**
   - After line 182 (end of while loop finding next meeting)
   - Add conditional:
     ```bash
     if [[ -n "$NEXT_MEETING" ]]; then
         MEETING_DATE=$(echo "$NEXT_MEETING" | cut -d'|' -f3)
         TODAY=$(date +%Y-%m-%d)

         if [[ "$MEETING_DATE" != "$TODAY" ]]; then
             # Next meeting is tomorrow or later
             MEETING_STATUS=$(check_meetings_today)
             if [[ "$MEETING_STATUS" == "had_meetings" ]]; then
                 LABEL=$(get_random_message END_OF_DAY_MESSAGES)
             else
                 LABEL=$(get_random_message FREE_DAY_MESSAGES)
             fi
             sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="$LABEL"
             return 0
         fi
         # Continue with existing countdown logic for today's meetings
     fi
     ```

3. **Fix `check_meetings_today()` function** (lines 92-104):
   - Current implementation has logic error with date comparison
   - Should check if khal returned ANY events for today's date range
   - Simplify to: `khal list today today --format "{title}" 2>/dev/null | tail -n +2`
   - If output is non-empty → "had_meetings", else → "no_meetings"

---

## Implementation Stack

**Core Technologies:**
- **Bash 5.2+**: Primary scripting language for Sketchybar plugins
- **Sketchybar v2.20+**: Status bar with custom event system
- **Python 3.11**: JSON parsing for API responses
- **curl 8.4.0**: HTTP client for Todoist REST API
- **khal 0.11.2**: Calendar CLI for meeting queries

**Development Dependencies:**
- **jq 1.7**: JSON manipulation (optional, currently using Python)
- **launchctl**: macOS LaunchAgent management

**External APIs:**
- **Todoist REST API v2**: Task management
  - Endpoint: `https://api.todoist.com/rest/v2/tasks`
  - Authentication: Bearer token via `TODOIST_API_TOKEN` in `.env`
  - Rate limit: 450 requests per 15 minutes (precaching stays well under)
  - Filter: `today | overdue` (URL-encoded: `today%20%7C%20overdue`)

**Existing Patterns to Follow:**
- **Calendar precache system**: `sync-calendars.sh` + LaunchAgent (reference architecture)
- **Cache directory**: `~/.cache/sketchybar/` for all state persistence
- **Logging**: `~/.config/sketchybar/logs/` with timestamped entries
- **Event system**: Sketchybar custom events (`calendar_synced` pattern)
- **MD5 change detection**: Prevent unnecessary updates (optional for this scope)

---

## Technical Details

### Component 1: Todoist Focus Task Fix

**File:** `config/sketchybar/plugins/todoist.sh`

**Changes:**
1. **After line 6**: Add event handler check and subscription setup
   ```bash
   # Handle focus change events and subscribe to them
   if [[ "$SENDER" != "todoist_focus_changed" ]]; then
       sketchybar --subscribe "$NAME" todoist_focus_changed
   fi
   ```

2. **No other changes needed** - the existing logic already reads from `todoist_working_task` and displays the focused task correctly. The issue was just missing the trigger event.

**File:** `config/sketchybar/plugins/todoist_popup.sh`

**Changes:**
1. **Line 148**: Modify click_script to trigger focus change event and close popup
   ```bash
   # OLD:
   click_script="echo '$TASK_ID' > '$WORKING_TASK_FILE' && sketchybar --trigger todoist_update"

   # NEW:
   click_script="echo '$TASK_ID' > '$WORKING_TASK_FILE' && sketchybar --trigger todoist_focus_changed && sketchybar --set todoist popup.drawing=off"
   ```

2. **Lines 134, 139**: Remove "[WORKING]" text
   ```bash
   # OLD (line 134):
   WORKING_INDICATOR=" [WORKING]"

   # NEW:
   WORKING_INDICATOR=""  # Remove visible indicator, keep yellow highlight only
   ```

### Component 2: Todoist Precache System

**NEW File:** `config/sketchybar/helpers/todoist-precache.sh`

```bash
#!/usr/bin/env bash

# Todoist Task Precache Script
# Runs every 5 minutes via LaunchAgent to provide instant popup performance
# Follows calendar sync architecture pattern

CACHE_DIR="$HOME/.cache/sketchybar"
TASKS_CACHE="$CACHE_DIR/todoist_tasks_cache"
LOG_FILE="$HOME/.config/sketchybar/logs/todoist-precache.log"

mkdir -p "$CACHE_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" >> "$LOG_FILE"
}

log "INFO" "Starting Todoist task precache sync"

# Source .env for TODOIST_API_TOKEN
ENV_FILE=""
for possible_location in \
    "$HOME/dotfiles/.env" \
    "$HOME/repos/02_personal/dotfiles/.env" \
    "$HOME/.config/sketchybar/../../.env"
do
    if [[ -f "$possible_location" ]]; then
        ENV_FILE="$possible_location"
        break
    fi
done

if [[ -z "$ENV_FILE" ]] || [[ ! -f "$ENV_FILE" ]]; then
    log "ERROR" "Cannot find .env file with TODOIST_API_TOKEN"
    exit 2
fi

source "$ENV_FILE"

if [[ -z "$TODOIST_API_TOKEN" ]]; then
    log "ERROR" "TODOIST_API_TOKEN not set in .env"
    exit 2
fi

# Fetch tasks with timeout
RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 30 -X GET \
    "https://api.todoist.com/rest/v2/tasks?filter=today%20%7C%20overdue" \
    -H "Authorization: Bearer $TODOIST_API_TOKEN" 2>&1)

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" != "200" ]]; then
    log "ERROR" "Todoist API returned HTTP $HTTP_CODE"
    echo "SYNC_STATUS=failed" > "$TASKS_CACHE"
    exit 1
fi

if [[ -z "$RESPONSE_BODY" ]] || [[ "$RESPONSE_BODY" == "[]" ]]; then
    log "INFO" "No tasks found (all completed)"
    echo "SYNC_STATUS=success" > "$TASKS_CACHE"
    echo "TASKS_START" >> "$TASKS_CACHE"
    sketchybar --trigger todoist_synced
    exit 0
fi

# Parse tasks (top 5 sorted by priority)
TASKS=$(echo "$RESPONSE_BODY" | python3 -c "
import sys, json

try:
    tasks = json.load(sys.stdin)
    if not tasks:
        sys.exit(0)

    # Sort by priority, then due date
    sorted_tasks = sorted(tasks, key=lambda x: (-x.get('priority', 1), x.get('due', {}).get('date', '9999-12-31')))
    top_tasks = sorted_tasks[:5]

    for task in top_tasks:
        task_id = task.get('id', '')
        content = task.get('content', 'No task')
        priority = task.get('priority', 1)
        url = task.get('url', '')

        # Truncate if too long
        if len(content) > 40:
            content = content[:37] + '...'

        # Priority icon
        if priority == 4:
            icon = '󰄴'
        elif priority == 3:
            icon = '󰄵'
        elif priority == 2:
            icon = '󰄶'
        else:
            icon = '󰃯'

        print(f'{task_id}|{icon}|{content}|{url}')

except Exception as e:
    print(f'error|󰃯|Error parsing tasks|', file=sys.stderr)
    sys.exit(1)
")

if [[ $? -ne 0 ]]; then
    log "ERROR" "Failed to parse tasks JSON"
    echo "SYNC_STATUS=failed" > "$TASKS_CACHE"
    exit 1
fi

# Write to cache
{
    echo "SYNC_STATUS=success"
    echo "TASKS_START"
    echo "$TASKS"
} > "$TASKS_CACHE"

log "INFO" "Successfully cached tasks"

# Trigger Sketchybar update
sketchybar --trigger todoist_synced

exit 0
```

**Permissions:** `chmod +x config/sketchybar/helpers/todoist-precache.sh`

**NEW File:** `~/Library/LaunchAgents/com.user.todoist-precache.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.todoist-precache</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/v/.config/sketchybar/helpers/todoist-precache.sh</string>
    </array>

    <key>StartInterval</key>
    <integer>300</integer>

    <key>RunAtLoad</key>
    <true/>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>

    <key>StandardOutPath</key>
    <string>/Users/v/.config/sketchybar/logs/todoist-precache-stdout.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/v/.config/sketchybar/logs/todoist-precache-stderr.log</string>
</dict>
</plist>
```

**Installation:**
```bash
launchctl load -w ~/Library/LaunchAgents/com.user.todoist-precache.plist
```

**Modified File:** `config/sketchybar/plugins/todoist_popup.sh`

**Changes:**
1. **Lines 52-61**: Replace API call with cache read
   ```bash
   # OLD:
   RESPONSE=$(curl -s -X GET \
       "https://api.todoist.com/rest/v2/tasks?filter=today%20%7C%20overdue" \
       -H "Authorization: Bearer $TODOIST_API_TOKEN")

   if [[ -z "$RESPONSE" ]] || [[ "$RESPONSE" == "[]" ]]; then
       sketchybar --set todoist.popup drawing=off
       exit 0
   fi

   # NEW:
   if [[ ! -f "$CACHE_DIR/todoist_tasks_cache" ]]; then
       # Trigger immediate sync and show loading state
       ~/.config/sketchybar/helpers/todoist-precache.sh &
       # Show one task item with loading message
       sketchybar --set "todoist.popup.task_1" \
           label="Refreshing tasks..." \
           icon="󰦖" \
           drawing=on \
           --set "todoist.popup.action_1" drawing=off
       # Hide other slots
       for i in {2..5}; do
           sketchybar --set "todoist.popup.task_$i" drawing=off \
                      --set "todoist.popup.action_$i" drawing=off
       done
       exit 0
   fi

   # Read from cache
   SYNC_STATUS=$(grep "^SYNC_STATUS=" "$CACHE_DIR/todoist_tasks_cache" | cut -d= -f2)
   TASKS=$(sed '1,/^TASKS_START$/d' "$CACHE_DIR/todoist_tasks_cache")

   if [[ "$SYNC_STATUS" == "failed" ]]; then
       sketchybar --set "todoist.popup.task_1" \
           label="Sync failed - click to retry" \
           icon="󰀨" \
           click_script="~/.config/sketchybar/helpers/todoist-precache.sh && sketchybar --set todoist popup.drawing=off && sketchybar --set todoist popup.drawing=on" \
           drawing=on
       exit 0
   fi
   ```

2. **Lines 63-101**: Remove Python parsing (now done in precache script)
   ```bash
   # DELETE entire TASKS= python block (lines 63-101)
   # TASKS variable now populated from cache read above
   ```

### Component 3: Calendar Day Boundary Logic

**File:** `config/sketchybar/plugins/meeting.sh`

**Changes:**

1. **Lines 92-104**: Fix `check_meetings_today()` function
   ```bash
   # OLD:
   check_meetings_today() {
       local today_start=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) 00:00:00" "+%s" 2>/dev/null)
       local now=$(date +%s)

       # Check khal for any meetings that started today
       local today_events=$(khal list today now --format "{title}|{start-time}|{start-date}" 2>/dev/null | tail -n +2 || echo "")

       if [[ -n "$today_events" ]]; then
           echo "had_meetings"
       else
           echo "no_meetings"
       fi
   }

   # NEW (simplified and fixed):
   check_meetings_today() {
       # Check if there were ANY meetings scheduled for today (past or future)
       local today_events=$(khal list today today --format "{title}" 2>/dev/null | tail -n +2 || echo "")

       if [[ -n "$today_events" ]]; then
           echo "had_meetings"
       else
           echo "no_meetings"
       fi
   }
   ```

2. **After line 182**: Add day boundary check before displaying meeting
   ```bash
   # Display next meeting or end-of-day message
   if [[ -n "$NEXT_MEETING" ]]; then
       TITLE=$(echo "$NEXT_MEETING" | cut -d'|' -f1)
       TIME=$(echo "$NEXT_MEETING" | cut -d'|' -f2)
       DATE=$(echo "$NEXT_MEETING" | cut -d'|' -f3)

       # NEW: Check if meeting is today
       TODAY=$(date +%Y-%m-%d)

       if [[ "$DATE" != "$TODAY" ]]; then
           # Next meeting is tomorrow or later - show appropriate message
           MEETING_STATUS=$(check_meetings_today)
           if [[ "$MEETING_STATUS" == "had_meetings" ]]; then
               LABEL=$(get_random_message END_OF_DAY_MESSAGES)
           else
               LABEL=$(get_random_message FREE_DAY_MESSAGES)
           fi
           sketchybar --set "$NAME" icon="󰃭" --set "${NAME}.name" label="$LABEL"
           return 0
       fi

       # EXISTING: Continue with countdown logic for today's meetings
       MEETING_TIMESTAMP=$(date -j -f "%Y-%m-%d %I:%M %p" "$DATE $TIME" "+%s" 2>/dev/null)
       # ... rest of existing countdown logic (lines 190-230) unchanged
   ```

---

## Development Setup

### Prerequisites

```bash
# Verify required tools
command -v sketchybar || brew install felixkratz/formulae/sketchybar
command -v khal || brew install khal
command -v python3 || brew install python@3.11

# Verify Todoist API token
if [[ -f ~/dotfiles/.env ]]; then
    source ~/dotfiles/.env
    [[ -n "$TODOIST_API_TOKEN" ]] && echo "✓ Token found" || echo "✗ Token missing"
else
    echo "✗ .env file missing"
fi
```

### Environment Configuration

**Required:** `TODOIST_API_TOKEN` in `.env` file
- Location: `~/dotfiles/.env` or `~/repos/02_personal/dotfiles/.env`
- Format: `TODOIST_API_TOKEN=your_token_here`
- Get token: https://todoist.com/app/settings/integrations/developer

**Cache Directory Structure:**
```bash
mkdir -p ~/.cache/sketchybar
mkdir -p ~/.config/sketchybar/logs
```

**Testing LaunchAgent PATH:**
```bash
# Verify Homebrew paths are accessible
launchctl setenv PATH "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
```

---

## Implementation Guide

### Phase 1: Todoist Focus Task Fix (30 minutes)

**Goal:** Make clicked task appear in main widget label

**Steps:**
1. Modify `todoist.sh` to subscribe to `todoist_focus_changed` event
2. Modify `todoist_popup.sh` click_script to trigger event and close popup
3. Remove "[WORKING]" text from popup (keep yellow highlight)
4. Test: Click task in popup → main widget updates immediately

**Verification:**
```bash
# Test clicking a task in popup
# Verify main widget shows the clicked task

# Check subscription
sketchybar --query todoist | grep subscribe
```

### Phase 2: Todoist Precache System (90 minutes)

**Goal:** Instant popup opens with precached data

**Steps:**
1. Create `todoist-precache.sh` script
2. Create LaunchAgent plist file
3. Modify `todoist_popup.sh` to read from cache
4. Install and start LaunchAgent
5. Test cache file creation and popup performance

**Implementation Order:**
```bash
# 1. Create precache script
cat > ~/.config/sketchybar/helpers/todoist-precache.sh << 'EOF'
# (Full script content from Technical Details section)
EOF
chmod +x ~/.config/sketchybar/helpers/todoist-precache.sh

# 2. Test script manually
bash ~/.config/sketchybar/helpers/todoist-precache.sh
cat ~/.cache/sketchybar/todoist_tasks_cache  # Verify output

# 3. Create LaunchAgent
cat > ~/Library/LaunchAgents/com.user.todoist-precache.plist << 'EOF'
# (Full plist content from Technical Details section)
EOF

# 4. Load LaunchAgent
launchctl load -w ~/Library/LaunchAgents/com.user.todoist-precache.plist
launchctl list | grep todoist-precache  # Verify running

# 5. Modify popup script to use cache (see Technical Details)

# 6. Restart Sketchybar
brew services restart sketchybar
```

**Verification:**
```bash
# Check LaunchAgent is running
launchctl list | grep todoist-precache

# Verify cache updates every 5 minutes
watch -n 5 "ls -lh ~/.cache/sketchybar/todoist_tasks_cache"

# Test popup performance (should be instant)
# Click todoist widget multiple times - no lag

# Check logs for errors
tail -f ~/.config/sketchybar/logs/todoist-precache.log
```

### Phase 3: Calendar Day Boundary Logic (45 minutes)

**Goal:** Show humorous messages when no meetings today, even if tomorrow has meetings

**Steps:**
1. Fix `check_meetings_today()` function
2. Add day boundary check in `update_display_from_cache()`
3. Test scenarios: no meetings today, meetings done, has upcoming

**Implementation:**
```bash
# 1. Backup original
cp ~/.config/sketchybar/plugins/meeting.sh ~/.config/sketchybar/plugins/meeting.sh.backup

# 2. Apply changes from Technical Details section

# 3. Reload Sketchybar
brew services restart sketchybar
```

**Test Scenarios:**
```bash
# Scenario A: No meetings today, has tomorrow
# Expected: Random FREE_DAY_MESSAGES

# Scenario B: Had meetings today, all done, has tomorrow
# Expected: Random END_OF_DAY_MESSAGES

# Scenario C: Has upcoming meeting today
# Expected: Countdown timer to next meeting

# Manual test by modifying khal database or waiting for real conditions
khal list today today   # Verify today's meetings
khal list tomorrow tomorrow  # Verify tomorrow's meetings
```

### Phase 4: Integration Testing (30 minutes)

**Test Matrix:**

| Test Case | Action | Expected Result |
|-----------|--------|-----------------|
| Focus task click | Click task in Todoist popup | Main widget updates to show clicked task |
| Focus persists | Restart Sketchybar | Focused task still displayed |
| Popup performance | Open Todoist popup | Opens instantly (<100ms) |
| Precache sync | Wait 5 minutes | Cache refreshes, logs updated |
| No meetings today | Clear today's calendar | Shows FREE_DAY_MESSAGES |
| Meetings done | After last meeting ends | Shows END_OF_DAY_MESSAGES |
| Upcoming meeting | Schedule meeting in 30min | Shows countdown timer |

**Automated Test Script:**
```bash
#!/usr/bin/env bash
# test-sketchybar-enhancements.sh

echo "Testing Todoist focus task..."
# Simulate click by writing to cache
echo "12345678" > ~/.cache/sketchybar/todoist_working_task
sketchybar --trigger todoist_focus_changed
sleep 2
WIDGET_LABEL=$(sketchybar --query todoist | jq -r '.label.value')
echo "Widget label: $WIDGET_LABEL"

echo "Testing Todoist precache..."
bash ~/.config/sketchybar/helpers/todoist-precache.sh
[[ -f ~/.cache/sketchybar/todoist_tasks_cache ]] && echo "✓ Cache created" || echo "✗ Cache missing"

echo "Testing calendar day boundary..."
# Check current state
sketchybar --query meeting | jq -r '.label.value'

echo "All tests complete!"
```

---

## Testing Approach

### Unit Testing

**Todoist Focus Task:**
```bash
# Test 1: Focus task file write and read
TASK_ID="test123"
echo "$TASK_ID" > ~/.cache/sketchybar/todoist_working_task
[[ "$(cat ~/.cache/sketchybar/todoist_working_task)" == "$TASK_ID" ]] && echo "PASS" || echo "FAIL"

# Test 2: Event trigger
sketchybar --trigger todoist_focus_changed
# Verify in Sketchybar logs
```

**Todoist Precache:**
```bash
# Test 1: API connectivity
curl -s -w "\n%{http_code}" -X GET \
    "https://api.todoist.com/rest/v2/tasks?filter=today%20%7C%20overdue" \
    -H "Authorization: Bearer $TODOIST_API_TOKEN" | tail -n 1
# Expected: 200

# Test 2: Cache write
bash ~/.config/sketchybar/helpers/todoist-precache.sh
[[ -f ~/.cache/sketchybar/todoist_tasks_cache ]] && echo "PASS" || echo "FAIL"

# Test 3: Cache format validation
head -n 3 ~/.cache/sketchybar/todoist_tasks_cache
# Expected:
# SYNC_STATUS=success
# TASKS_START
# {task_id}|{icon}|{content}|{url}
```

**Calendar Day Boundary:**
```bash
# Test 1: check_meetings_today function
source ~/.config/sketchybar/plugins/meeting.sh
RESULT=$(check_meetings_today)
echo "Result: $RESULT"
# Expected: "had_meetings" or "no_meetings"

# Test 2: Date comparison
TODAY=$(date +%Y-%m-%d)
TOMORROW=$(date -v+1d +%Y-%m-%d)
[[ "$TOMORROW" != "$TODAY" ]] && echo "PASS" || echo "FAIL"

# Test 3: Message randomization
source ~/.config/sketchybar/plugins/meeting.sh
get_random_message FREE_DAY_MESSAGES
get_random_message END_OF_DAY_MESSAGES
# Expected: Different messages on each run
```

### Integration Testing

**Full Workflow Tests:**

1. **Todoist Focus + Precache:**
   ```bash
   # Trigger precache
   bash ~/.config/sketchybar/helpers/todoist-precache.sh

   # Open popup (cache read)
   sketchybar --set todoist popup.drawing=toggle

   # Click task (focus)
   # Verify main widget updates

   # Wait 5 minutes
   # Verify cache refreshes via LaunchAgent
   ```

2. **Calendar State Transitions:**
   ```bash
   # Morning (no meetings yet)
   # Expected: Shows first meeting countdown

   # After last meeting
   # Expected: Shows END_OF_DAY_MESSAGES

   # Day with no meetings
   # Expected: Shows FREE_DAY_MESSAGES

   # Popup click
   # Expected: Shows next 7 days
   ```

### Performance Testing

**Popup Open Speed:**
```bash
# Benchmark popup open time
time (sketchybar --set todoist popup.drawing=on && sleep 0.1 && sketchybar --set todoist popup.drawing=off)

# Target: <100ms after precaching
# Before: 500-1000ms with API call
```

**LaunchAgent Resource Usage:**
```bash
# Monitor LaunchAgent execution
tail -f ~/Library/Logs/com.user.todoist-precache.stderr.log

# Check CPU/memory impact
ps aux | grep todoist-precache
```

### Error Scenarios

**Test Error Handling:**

1. **No Todoist API token:**
   ```bash
   # Remove token temporarily
   mv ~/dotfiles/.env ~/dotfiles/.env.backup
   sketchybar --trigger todoist_focus_changed
   # Expected: "No Todoist token" message
   mv ~/dotfiles/.env.backup ~/dotfiles/.env
   ```

2. **API failure:**
   ```bash
   # Simulate by corrupting token
   # Expected: Cache shows SYNC_STATUS=failed
   # Popup shows retry option
   ```

3. **Stale cache:**
   ```bash
   # Delete cache
   rm ~/.cache/sketchybar/todoist_tasks_cache
   # Open popup
   # Expected: "Refreshing tasks..." message
   ```

4. **No khal data:**
   ```bash
   # Temporarily rename khal calendars
   mv ~/.local/share/khal/calendars ~/.local/share/khal/calendars.backup
   sketchybar --trigger calendar_synced
   # Expected: "No calendar access" message
   mv ~/.local/share/khal/calendars.backup ~/.local/share/khal/calendars
   ```

---

## Deployment Strategy

### Deployment Checklist

**Pre-Deployment:**
- [ ] Backup existing Sketchybar configuration
- [ ] Verify `.env` file contains valid `TODOIST_API_TOKEN`
- [ ] Ensure cache and log directories exist
- [ ] Test all scripts manually before automation

**Deployment Steps:**

1. **Backup Current Configuration:**
   ```bash
   cp ~/.config/sketchybar/plugins/todoist.sh ~/.config/sketchybar/plugins/todoist.sh.backup
   cp ~/.config/sketchybar/plugins/todoist_popup.sh ~/.config/sketchybar/plugins/todoist_popup.sh.backup
   cp ~/.config/sketchybar/plugins/meeting.sh ~/.config/sketchybar/plugins/meeting.sh.backup
   ```

2. **Apply Changes (via symlinks from dotfiles repo):**
   ```bash
   cd ~/repos/02_personal/dotfiles
   git checkout -b feature/sketchybar-popup-enhancements

   # Make changes to files in config/sketchybar/
   # Changes automatically apply via symlinks
   ```

3. **Install LaunchAgent:**
   ```bash
   # Copy plist to LaunchAgents directory
   cp config/sketchybar/launchagents/com.user.todoist-precache.plist ~/Library/LaunchAgents/

   # Load agent
   launchctl load -w ~/Library/LaunchAgents/com.user.todoist-precache.plist

   # Verify running
   launchctl list | grep todoist-precache
   ```

4. **Restart Sketchybar:**
   ```bash
   brew services restart sketchybar

   # Verify restart
   pgrep -fl sketchybar
   ```

5. **Verify Functionality:**
   ```bash
   # Test focus task
   # Click Todoist widget → click a task → verify main widget updates

   # Test precache
   tail -f ~/.config/sketchybar/logs/todoist-precache.log

   # Test calendar
   # Verify appropriate message based on meeting status
   ```

**Rollback Plan:**
```bash
# If issues occur, restore backups
cp ~/.config/sketchybar/plugins/todoist.sh.backup ~/.config/sketchybar/plugins/todoist.sh
cp ~/.config/sketchybar/plugins/todoist_popup.sh.backup ~/.config/sketchybar/plugins/todoist_popup.sh
cp ~/.config/sketchybar/plugins/meeting.sh.backup ~/.config/sketchybar/plugins/meeting.sh

# Unload LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.user.todoist-precache.plist

# Restart Sketchybar
brew services restart sketchybar
```

### Post-Deployment Monitoring

**First 24 Hours:**
```bash
# Monitor LaunchAgent logs
tail -f ~/.config/sketchybar/logs/todoist-precache.log

# Check cache updates
watch -n 300 "ls -lh ~/.cache/sketchybar/todoist_tasks_cache"

# Monitor Sketchybar errors
tail -f /opt/homebrew/var/log/sketchybar/sketchybar.log
```

**Success Metrics:**
- Popup opens in <100ms (instant feel)
- Focus task updates immediately on click
- Calendar shows correct messages based on meeting status
- LaunchAgent runs every 5 minutes without errors
- No Sketchybar crashes or hangs

### Git Workflow

```bash
# Create feature branch
git checkout -b feature/sketchybar-popup-enhancements

# Commit changes incrementally
git add config/sketchybar/plugins/todoist.sh
git commit -m "feat(todoist): fix focus task not updating main widget"

git add config/sketchybar/plugins/todoist_popup.sh
git commit -m "feat(todoist): add precache system for instant popup"

git add config/sketchybar/helpers/todoist-precache.sh
git commit -m "feat(todoist): add background precache script"

git add config/sketchybar/plugins/meeting.sh
git commit -m "feat(calendar): fix day boundary logic for empty days"

# Push to remote
git push origin feature/sketchybar-popup-enhancements

# Merge to main after testing
git checkout main
git merge feature/sketchybar-popup-enhancements
git push origin main
```

### Documentation Updates

**Update CLAUDE.md:**
- Add Todoist precache architecture section (mirror calendar sync documentation)
- Document focus task persistence mechanism
- Add troubleshooting section for Todoist sync issues

**Section to Add:**
```markdown
#### Todoist Automation Architecture

The Todoist widget provides zero-touch task synchronization with instant popup performance through precaching.

**Complete Data Flow:**
```
.env (TODOIST_API_TOKEN) → LaunchAgent (5min) → todoist-precache.sh →
curl fetch (JSON) → python parse → cache → todoist_synced event →
todoist_popup.sh → instant widget display
```

**Component Details:**
1. **todoist-precache.sh**: Background sync every 5 minutes, writes to cache
2. **todoist_popup.sh**: Reads from cache for instant opens
3. **todoist.sh**: Displays focused task or highest priority
4. **Focus Task System**: Click-to-focus with persistence across restarts

**Manual Sync:**
```bash
bash ~/.config/sketchybar/helpers/todoist-precache.sh
```

**Troubleshooting:**
- Check LaunchAgent: `launchctl list | grep todoist-precache`
- View logs: `tail -f ~/.config/sketchybar/logs/todoist-precache.log`
- Force sync: `launchctl start com.user.todoist-precache`
```

---

_This tech spec is for Level 1 project (BMad Method v6). It provides definitive technical decisions for implementing Sketchybar popup enhancements with focus task functionality and calendar day boundary logic._
