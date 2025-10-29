# Bug Fix: Meeting Widget Shows "No Meetings" After Event Ends

**Date:** 2025-10-29
**Severity:** Medium (Production Bug)
**Component:** config/sketchybar/plugins/meeting.sh
**Status:** ✅ FIXED

## Summary

Meeting widget incorrectly displayed "No meetings" after a meeting ended, even when there were upcoming meetings within the next 7 days. Widget failed to show the next meeting (Slackbot Weekly at 09:30 AM) after Paul's meeting ended at 08:45 AM.

## Bug Details

### Symptoms
- After Paul's meeting ended (08:45 AM), widget showed "No meetings"
- Next meeting (Slackbot Weekly at 09:30 AM) was not displayed
- Current time: 09:01 AM (16 minutes after Paul's meeting started)
- khal database contained upcoming meetings

### Root Cause

**Logic Flaw in meeting.sh (line 130):**

The widget took the FIRST event from `khal list now 7d` without filtering out past meetings:

```bash
# BUGGY CODE:
NEXT_MEETING=$(echo "$EVENTS" | head -n 1)  # Takes first event blindly
```

**Problem Flow:**
1. `khal list now 7d` returns all events starting from today (including past ones)
2. Widget takes first event (Paul's meeting at 08:45 AM)
3. Checks if meeting is in future (line 147) - NO (it's 09:01 now)
4. Checks if meeting started within last 10 minutes (line 183) - NO (started 16 minutes ago)
5. Falls through to else clause (line 190) - displays "No meetings"

### Why khal Returns Past Meetings

The `khal list now 7d` command returns events that START today, even if they've already ended. It doesn't filter by "hasn't ended yet".

## The Fix

**Added filtering logic BEFORE selecting the first event:**

```bash
# FIXED CODE:
# Filter out past meetings - only show meetings that haven't ended yet
# Meetings are considered "ended" if they started more than 10 minutes ago
CURRENT_TIMESTAMP=$(date "+%s")
FUTURE_EVENTS=""

while IFS= read -r event; do
    [[ -z "$event" ]] && continue

    # Parse event timestamp
    EVENT_TIME=$(echo "$event" | cut -d'|' -f2)
    EVENT_DATE=$(echo "$event" | cut -d'|' -f3)
    EVENT_TIMESTAMP=$(date -j -f "%Y-%m-%d %I:%M %p" "$EVENT_DATE $EVENT_TIME" "+%s" 2>/dev/null)

    # Include events that are in the future OR started within last 10 minutes
    if [[ -n "$EVENT_TIMESTAMP" ]] && [[ $((CURRENT_TIMESTAMP - EVENT_TIMESTAMP)) -le 600 ]]; then
        if [[ -z "$FUTURE_EVENTS" ]]; then
            FUTURE_EVENTS="$event"
        else
            FUTURE_EVENTS="$FUTURE_EVENTS"$'\n'"$event"
        fi
    fi
done <<< "$EVENTS"

# NOW take the first event from filtered list
NEXT_MEETING=$(echo "$FUTURE_EVENTS" | head -n 1)
```

## Fix Behavior

The new logic:
1. **Filters** all events to only include:
   - Future meetings (start time > current time)
   - OR meetings that started within last 10 minutes (for "started Xm ago" display)
2. **Then selects** the first event from the filtered list
3. Displays correct next meeting

## Testing

### Test Case 1: Multiple Upcoming Meetings
**Scenario:** Paul's meeting ended 16 minutes ago, Slackbot Weekly in 28 minutes

**Before Fix:**
```
Widget display: "No meetings"
khal list: 1on1 Paul Jeff (08:45 AM), Slackbot Weekly (09:30 AM), ...
```

**After Fix:**
```
Widget display: "Slackbot Weekly in 28m"
khal list: (same data)
```

### Test Case 2: Meeting Just Started
**Scenario:** Meeting started 5 minutes ago (within 10-minute window)

**Expected:** Shows "Meeting Title (started 5m ago)"
**Result:** ✅ Works correctly (preserved existing logic)

### Test Case 3: All Meetings Past
**Scenario:** All meetings started more than 10 minutes ago

**Expected:** Shows "No meetings"
**Result:** ✅ Works correctly (no future events in filtered list)

## Verification

```bash
# Manual test
NAME=meeting bash /Users/v/.config/sketchybar/plugins/meeting.sh

# Check cached output
cat /Users/v/.cache/sketchybar/meeting_data_cache
# Output: "Slackbot Weekly in 28m" ✅

# Restart Sketchybar
brew services restart sketchybar
```

## Impact

**Before:**
- Widget showed "No meetings" for 10+ minutes after each meeting ended
- User couldn't see upcoming meetings during this window
- Reduced trust in calendar automation system

**After:**
- Widget correctly shows next meeting immediately after previous meeting ends (beyond 10-minute grace period)
- Maintains "started Xm ago" display for meetings that just began
- Improved user experience and system reliability

## Files Changed

- `config/sketchybar/plugins/meeting.sh` (lines 128-159)
  - Added FUTURE_EVENTS filtering loop
  - Filters events before selecting first one
  - Preserved existing "started Xm ago" logic

## Lessons Learned

1. **Don't trust external command output blindly** - `khal list now 7d` includes past events
2. **Filter data BEFORE selection** - Don't select first then validate
3. **E2E testing with real time progression** - Bug only appears after meetings end
4. **Grace periods need careful consideration** - 10-minute window for "started Xm ago" vs filtering

## Related Issues

- Original implementation in Story 2.6: Update meeting widget for reliable display
- Tested during Story 2.7 but only validated event addition/deletion, not time-based filtering
- **Gap:** E2E testing didn't include "wait for meeting to end and check next meeting appears"

## Recommendations

### Additional Testing
1. Add test case: "After meeting ends, verify next meeting appears within 15 seconds"
2. Monitor widget behavior over next 1-2 days to validate fix in production
3. Consider automated tests that simulate time progression

### Future Enhancements
1. Consider making the 10-minute grace period configurable in .env
2. Add logging when filtering removes events (for debugging)
3. Consider whether `khal list` has a flag to exclude past events

## Deployment

**Status:** ✅ Deployed to production
**Date:** 2025-10-29 09:05 AM
**Method:** Direct edit + `brew services restart sketchybar`
**Rollback:** Revert commit or restore from backup

## Monitoring

**Next 24 hours:**
- Verify widget correctly updates after each meeting ends
- Check for any new "No meetings" false positives
- Monitor logs for any timestamp parsing errors

**Success Criteria:**
- Widget shows correct next meeting within 15 seconds after previous meeting ends (beyond 10-minute grace)
- No "No meetings" false positives when upcoming meetings exist
- "Started Xm ago" display still works for meetings in progress

---

**Fixed by:** Development Team
**Reviewed by:** User (Jeff) - Production validation
**Approved for deployment:** 2025-10-29
