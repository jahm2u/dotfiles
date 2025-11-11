# Krisp Automation System - Handoff Notes (Part 2)
**Date:** 2025-11-10
**Engineer:** John
**Context:** Fixed navigation bug, attempted unified classification - calendar matching is broken

---

## 1. Completed Work ✅

### Navigation Bug Fixed
- **File**: `krisp-download-transcripts-simple.py`
- **Issue**: Double navigation causing timeouts after processing meeting #15
- **Fix**: Removed duplicate navigation block (lines 354-357), changed `if` to `elif` so all code paths flow through single navigation at line 393-397
- **Status**: ✅ Script now completes successfully, processes all meetings without timeout

### Unified Classification Created (But Not Working)
- **Created**: `classify-meeting-unified.py` - Intended single source of truth
- **Created**: `krisp-create-queue-enhanced.py` - Queue creator with calendar matching
- **Updated**:
  - `meeting-prep.sh` → Uses classify-meeting-unified.py
  - `krisp-hourly-daemon.sh` → Uses enhanced queue creator
  - `krisp-process-transcript.py` → Uses unified classifier

---

## 2. Critical Problems Found 🚨

### Calendar Matching is Fundamentally Broken
**Current Results**: Out of 28 meetings, only 4 classified
- Claims to match "1on1 Thais Jeff" on Nov 7 and Nov 10
- **User confirms**: No meeting with Thais on Friday (one of those dates)
- **This means our calendar matching is returning WRONG data**

### Issues Identified
1. **Calendar query may be looking at wrong dates**
   - Krisp titles: "November 7"
   - Need to verify: Are we querying 2024-11-07 or 2025-11-07?
   - Transcripts downloaded Nov 7 2024, but code may assume 2025

2. **Time matching tolerance wrong**
   - Current: 30 minutes
   - User: Some meetings only 20 minutes long
   - **30-minute tolerance would SKIP meetings entirely**
   - Should be ±5-10 minutes max for matching

3. **Pattern matching also incorrect**
   - Detecting "1on1 Thais Jeff" format
   - But extracting wrong person (should exclude "Jeff")

---

## 3. What Actually Needs to Happen 🎯

### The Real Problem
- User has nearly ALL meetings in calendar (±10 min variance)
- 28 Krisp transcripts exist
- Calendar has events at those times
- **But our code can't match them**

### Root Causes to Fix
1. **Date parsing** - Krisp says "November 3" but what year?
2. **khal query** - Are we even calling it correctly?
3. **Time comparison** - 30 min tolerance is too wide, need 5-10 min
4. **Pattern extraction** - "1on1 Thais Jeff" should extract "Thais" not both names

---

## 4. Next Developer: Start Here 🔍

### Step 1: Verify Date Logic
```bash
# Check what year Krisp transcripts are from
ls -la ~/.config/sketchybar/krisp-transcripts/*.json | head -5

# Look at downloaded_at timestamps - are they 2024 or 2025?
cat ~/.config/sketchybar/krisp-transcripts/krisp-transcript-*.json | jq '.downloaded_at' | head -5
```

The year wrapping logic in `parse_krisp_date()` is likely wrong:
```python
# Current code assumes if month > now.month, use previous year
# But Nov 2024 meetings would appear as 2025 if run in Jan 2025!
```

### Step 2: Debug Calendar Query
Add logging to `query_calendar_events()` in `classify-meeting-unified.py`:
```python
def query_calendar_events(date_str):
    print(f"[DEBUG] Querying khal for date: {date_str}", file=sys.stderr)
    result = subprocess.run(
        ['khal', 'list', date_str, '1d', '--format', '{start-time} | {title}'],
        capture_output=True, text=True, timeout=30
    )
    print(f"[DEBUG] khal returned {result.returncode}", file=sys.stderr)
    print(f"[DEBUG] Output: {result.stdout[:200]}", file=sys.stderr)
```

### Step 3: Test Real Meeting
```bash
# User confirmed Nov 3 had meetings
# Test if we can match a specific one
khal list 2024-11-03 1d --format '{start-time} | {title}'

# Then test classifier
cd ~/.config/sketchybar
venv/bin/python3 helpers/classify-meeting-unified.py \
  --title "12:00 PM - Slack meeting November 3" \
  --date "2024-11-03" \
  --time "12:00 PM" 2>&1
```

### Step 4: Fix Time Tolerance
Change from 30 minutes to 10 minutes in `classify-meeting-unified.py`:
```python
# Line ~152: Look for close time match (within 30 minutes)
if diff <= 30:  # Change to: if diff <= 10:
```

### Step 5: Fix Pattern Extraction
The "1on1 Thais Jeff" pattern should only extract first name:
```python
# Current line 198:
r'1on1\s+(\w+)(?:\s+\w+)?',  # This captures "Thais" ✓

# But need to filter out "Jeff" from participant field
# Add check: if participant.lower() == 'jeff': continue
```

---

## 5. Files That Need Work 📁

**Primary**:
- `classify-meeting-unified.py` (lines 87-165: calendar matching)
- `krisp-create-queue-enhanced.py` (lines 44-95: date parsing)

**Secondary**:
- `meeting-prep.sh` (already updated, should work once classifier fixed)
- `krisp-hourly-daemon.sh` (already updated, should work once classifier fixed)

---

## 6. Test Data Available 📊

```
28 Krisp transcripts in ~/.config/sketchybar/krisp-transcripts/
Queue file: ~/.cache/sketchybar/krisp-pending-downloads.json

User calendar has events like:
- Nov 3: MP Product Team Meeting at 11:00 AM
- Nov 3: Mkt Headquarter at 12:00 PM
- Nov 4: 1on1 Otávio Jeff

Krisp captured:
- Nov 3: Slack meetings at 10:45 AM, 11:02 AM, 12:00 PM
- Nov 4: Discord meeting at 01:09 PM
```

**These SHOULD match but DON'T** - that's the bug.

---

## 7. Scripts to Remove (After Fix) 🗑️

Once unified classifier is working:
- `classify-meeting.py` - Old non-calendar version
- `krisp-match-meetings.py` - Functionality now in unified script
- `krisp-create-queue-from-transcripts.py` - Replaced by enhanced version

**Don't remove yet** - may need for reference during debugging.

---

## 8. Key Insight 💡

User said: "ALL of my meetings in my calendar are +-10 minutes, I VERY RARELY miss a meeting."

**This means**:
- Our 4/28 success rate is unacceptable (should be ~28/28)
- The calendar matching logic is critically broken
- Don't assume meetings are unscheduled - they're ALL scheduled
- Fix the matcher, don't change the tolerance expectations

---

## 9. Warning ⚠️

The "1on1 Thais Jeff" matches we found may be FALSE POSITIVES:
- User says no Thais meeting on Friday
- But we claimed to find one
- Calendar query might be returning cached/old data
- Or querying wrong date range entirely

**Verify everything before trusting any output.**

---

*Handoff prepared by: John*
*Status: Navigation fixed ✅, Classification broken ❌, needs calendar matching rewrite*
*Next dev: Start with date verification - that's likely the root cause*
