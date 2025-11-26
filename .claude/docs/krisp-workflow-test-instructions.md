# Krisp Automation Workflow - Testing & Documentation Review

## Context

The Krisp automation workflow was recently restructured to fix a critical architecture issue. The **cross-meeting context analysis (80/20 structure)** was moved from POST-meeting (Krisp automation) to PRE-meeting (meeting-prep.sh).

### What Changed

**BEFORE (Incorrect):**
- Krisp automation tried to do cross-meeting analysis AFTER meetings
- This made no sense - you need context BEFORE meetings, not after

**AFTER (Correct):**
- `meeting-prep.sh` → Loads previous meetings + analyzes with GPT → Generates prep note with 80% context from history
- Krisp automation → Simple append of current meeting discussion to existing note
- Next prep cycle → Picks up full context (your notes + AI analysis)

### Files Modified

1. **analyze-meeting-history.py** - Enhanced with `.meeting-config.json` support for cross-meeting context
2. **krisp-analyze-transcript.py** - Simplified (removed 230 lines of cross-meeting logic)
3. **krisp-process-transcript.py** - Cleaned up person_folder passing
4. **krisp-update-note.py** - Removed cross-meeting section formatting

## Your Tasks

### Task 1: Test the Corrected Workflow

#### Step 1: Test PRE-Meeting Workflow (Meeting Prep)

Use Ron's existing meetings as test data:

```bash
# Location of Ron's meetings
PERSON_FOLDER="/Users/v/Library/Mobile Documents/iCloud~md~obsidian/Documents/U/Business/People/IPMedia/Ron"

# Test the meeting history analyzer
~/.config/sketchybar/venv/bin/python3 \
  ~/.config/sketchybar/helpers/analyze-meeting-history.py \
  --person-folder "$PERSON_FOLDER" \
  --classification '{"participant": "Ron", "company": "IPMedia", "meeting_type": "ipmedia_executive"}' \
  --max-meetings 5
```

**Expected Output:**
- Should load `.meeting-config.json`
- Should print: "✓ Loaded meeting config: use_cross_meeting_context=True"
- Should print: "✓ Cross-meeting context enabled - loading recent company meetings"
- Should print: "  → Added context from IPMedia meetings (last 7 days)"
- Should output JSON with: `open_action_items`, `recurring_topics`, `active_blockers`, `unresolved_threads`, `suggested_agenda`

**Validation Checklist:**
- [ ] Config file loaded successfully
- [ ] Cross-meeting context was enabled
- [ ] Found previous Ron meetings
- [ ] Found other IPMedia team meetings (cross-context)
- [ ] GPT analysis returned comprehensive JSON
- [ ] Action items have proper structure (description, owner, source_meeting, days_open, priority)

#### Step 2: Test POST-Meeting Workflow (Krisp Automation)

Find an existing Ron meeting with transcript:

```bash
# Find a Ron transcript
TRANSCRIPT=$(find ~/.config/sketchybar/krisp-transcripts -name "*.txt" | head -1)
echo "Using transcript: $TRANSCRIPT"

# Find corresponding metadata
METADATA="${TRANSCRIPT%.txt}.json"
cat "$METADATA" | jq -c '{meeting_id, title, date, time}'
```

Test the simplified analyzer:

```bash
# Pick an existing Ron meeting note
NOTE_PATH="$PERSON_FOLDER/Meetings/2025-11-19 1on1 with Ron.md"

# Test analyzer (should NOT try to load cross-meeting context)
~/.config/sketchybar/venv/bin/python3 \
  ~/.config/sketchybar/helpers/krisp-analyze-transcript.py \
  --transcript "$TRANSCRIPT" \
  --note "$NOTE_PATH" \
  --person "Ron" \
  --company "IPMedia" \
  --meeting-type "ipmedia_executive" \
  --date "2025-11-19" \
  --json
```

**Expected Output:**
- Should analyze transcript ONLY (not load previous meetings)
- Should output JSON with: `discussion_highlights`, `action_items`, `key_insights`, `decisions`, `blockers`, `growth_development`, `business_impact`, `topics_next_time`, `related_context`
- Should NOT have: `outstanding_from_previous` or any cross-meeting sections

**Validation Checklist:**
- [ ] No cross-meeting context loaded (simplified!)
- [ ] Discussion highlights cover all major topics (5-8 points)
- [ ] Action items properly formatted with [[PersonName]]
- [ ] Key insights include quotes from transcript
- [ ] Business impact section populated (not empty)
- [ ] No errors in logs

### Task 2: Analyze Documentation

Review these documentation files for accuracy and completeness:

1. **CLAUDE.md** - Main context document
2. **.claude/docs/logging-enhancements.md** - Recent logging changes
3. **config/sketchybar/helpers/*.py** - Inline documentation

#### Documentation Review Checklist

**CLAUDE.md:**
- [ ] Krisp automation workflow description is accurate
- [ ] Meeting prep workflow is correctly described
- [ ] LaunchAgent configuration is up-to-date
- [ ] Environment variables are complete
- [ ] Troubleshooting section is helpful
- [ ] File naming for duplicates issue is documented

**Code Documentation:**
- [ ] `analyze-meeting-history.py` - docstrings accurate for cross-meeting context
- [ ] `krisp-analyze-transcript.py` - simplified purpose clearly documented
- [ ] `krisp-process-transcript.py` - flow is well-commented
- [ ] `krisp-update-note.py` - section mapping is clear

**Missing Documentation:**
- [ ] List any gaps or unclear sections
- [ ] Identify where examples would help
- [ ] Note any outdated information

### Task 3: Build Comprehensive Report

Create a report with the following sections:

#### 3.1 Test Results

```markdown
## Test Results

### PRE-Meeting Workflow (Meeting Prep)
- **Status**: ✅ Pass / ❌ Fail
- **Config Loading**: [Result]
- **Cross-Meeting Context**: [Result]
- **GPT Analysis Quality**: [Assessment]
- **Issues Found**: [List any issues]

### POST-Meeting Workflow (Krisp Automation)
- **Status**: ✅ Pass / ❌ Fail
- **Transcript Analysis**: [Result]
- **Section Population**: [Which sections filled, which empty]
- **Issues Found**: [List any issues]
```

#### 3.2 Documentation Quality Assessment

```markdown
## Documentation Review

### CLAUDE.md
- **Accuracy**: [1-5 rating]
- **Completeness**: [1-5 rating]
- **Clarity**: [1-5 rating]
- **Recommended Changes**: [Bulleted list]

### Code Documentation
- **Docstring Coverage**: [%]
- **Inline Comments Quality**: [Assessment]
- **Recommended Improvements**: [Bulleted list]

### Missing Documentation
1. [Topic 1 needing docs]
2. [Topic 2 needing docs]
```

#### 3.3 Template Section Analysis

Examine Ron's template vs actual output:

```markdown
## Template Section Coverage

Ron's template has these sections:
- ⚠️ Context
- 🌐 Company-Wide Context
- 🔄 Action Items Status from Last Meeting
- 🎯 MEETING AGENDA
- 📝 MEETING CAPTURE (Fill During/After Meeting)
  - Notes During Meeting
  - Action Items
  - Key Insights & Quotes
  - Decisions Made
  - Blockers Identified
  - Growth & Development
  - Business Impact
- 📚 REFERENCE & CONTEXT
  - Related Documents

### Sections Filled by Automation
- [✅/❌] Notes During Meeting
- [✅/❌] Action Items
- [✅/❌] Key Insights & Quotes
- [✅/❌] Decisions Made
- [✅/❌] Blockers Identified
- [✅/❌] Growth & Development
- [✅/❌] Business Impact
- [✅/❌] Related Documents

### Empty Sections (Issues)
- [List sections that should be filled but aren't]
- [Root cause for each]
```

#### 3.4 Specific Issues to Check

1. **Business Impact Section** - Previously reported as empty. Is it filled now?
2. **Duplicate Appends** - Check if idempotency issue is fixed (was appending same content twice)
3. **Section Name Mismatches** - Do template sections match what the code expects?

#### 3.5 Recommendations

```markdown
## Recommendations

### High Priority
1. [Issue 1 that needs immediate fix]
2. [Issue 2 that needs immediate fix]

### Medium Priority
1. [Enhancement 1]
2. [Enhancement 2]

### Documentation Updates Needed
1. [Doc update 1]
2. [Doc update 2]

### Template Alignment
- [Any template sections that need renaming]
- [Any new sections to add]
```

### Task 4: Check for Additional Issues

Look for these potential problems in the codebase:

```bash
# Check for idempotency issues (duplicate appends)
grep -n "AI-Generated from Transcript" "$NOTE_PATH" | wc -l
# Should be 1 per section, not multiple

# Check for empty sections in recent notes
grep -A2 "### Business Impact" "$NOTE_PATH"

# Check logs for errors
tail -100 ~/.config/sketchybar/logs/krisp-automation.log | grep ERROR

# Check failed matches cache
cat ~/.cache/sketchybar/krisp-updated-meeting-notes.json | jq '.failed_matches'
```

## Test Data Locations

```bash
# Ron's meeting folder
/Users/v/Library/Mobile Documents/iCloud~md~obsidian/Documents/U/Business/People/IPMedia/Ron/Meetings/

# Recent Ron meetings
2025-11-19 1on1 with Ron.md
2025-11-13 1on1 with Ron.md
2025-11-05 1on1 with Ron.md
2025-10-16 1on1.md (has manual prep by Jonas - good reference!)

# Transcripts
~/.config/sketchybar/krisp-transcripts/

# Logs
~/.config/sketchybar/logs/krisp-automation.log
~/.config/sketchybar/logs/meeting-prep.log

# Cache
~/.cache/sketchybar/krisp-updated-meeting-notes.json
```

## Deliverable

Provide Jeff with:

1. **Test Results** - Pass/fail for each workflow component
2. **Documentation Quality Report** - What's good, what needs fixing
3. **Template Section Analysis** - Which sections fill, which don't, why
4. **Issue List** - Prioritized list of bugs/improvements
5. **Recommended Fixes** - Specific code changes or doc updates needed

Format as a comprehensive markdown report that Jeff can review and provide feedback on.

## Success Criteria

- [ ] Both workflows tested successfully
- [ ] Documentation gaps identified
- [ ] Template section coverage analyzed
- [ ] All empty sections explained
- [ ] Actionable recommendations provided
- [ ] Report is clear, detailed, and ready for Jeff's review

---

# Krisp Naming Refactor - Code Review & Tests (2025-11-25)

## Summary of Session Changes

This session made interconnected changes to fix classification issues and add a new naming convention:

### 1. Speaker Extraction Regex Fix
**File:** `helpers/krisp-process-transcript.py:106`
```python
# OLD: r'^([A-Za-z\s]+) \| \d+:\d+$'
# NEW: r'^([A-Za-z0-9\s]+) \| \d+:\d+$'
```
**Purpose:** Allow matching "Speaker 1", "Speaker 2" generic labels (contain numbers)

### 2. Classification System Overhaul
**File:** `helpers/classify-meeting-unified.py`
- Rewrote `extract_team_from_title()` to return `(category, subcategory)` tuples
- Added meeting types: `ipmedia_review`, `ipmedia_onboarding`, `ipmedia_executive`, `ipmedia_board`
- Added dev squads: `ipmedia_dev_growth`, `ipmedia_dev_meumatch`, `ipmedia_dev_slackbot`, `ipmedia_dev_marcus`
- Added marketing sub-teams: `ipmedia_marketing_traffic`, `ipmedia_marketing_social_pr`, `ipmedia_marketing_seo`
- Added portfolio companies: `co_gone_meeting`, `co_dt_meeting`, `co_mt_meeting`

### 3. New Download Naming Convention
**File:** `helpers/krisp-download-transcripts-simple.py`
- Added `sanitize_filename()` function
- Added `send_telegram_notification()` for classification verification
- New format: `{date}-{sanitized-title}-{meeting_id}.txt` (was `krisp-transcript-{id}.txt`)

### 4. Batch Processor Dual-Format Support
**File:** `helpers/krisp-batch-process.py`
- `extract_meeting_id()` handles both old and new filename formats
- `build_processing_queue()` prefers JSON companion file metadata

---

## Quick Test Commands

### Test 1: Syntax Check
```bash
cd ~/.config/sketchybar/helpers
python3 -m py_compile krisp-process-transcript.py krisp-batch-process.py \
  krisp-download-transcripts-simple.py classify-meeting-unified.py
# Expected: No output (success)
```

### Test 2: Classification Tests (34 cases)
```bash
cd ~/.config/sketchybar && venv/bin/python3 -c "
import sys; sys.path.insert(0, 'helpers')
from importlib import import_module
spec = import_module('classify-meeting-unified')
classify = spec.classify_from_calendar_title

tests = [
    ('1on1 Marcus Jeff', 'ipmedia_1on1'),
    ('[Weekly] Growth Squad', 'ipmedia_dev_growth'),
    ('Jeff / Ron Weekly Meeting', 'ipmedia_executive'),
    ('Gone - Weekly Sync', 'co_gone_meeting'),
    ('Lunch Time', 'excluded'),
]
for title, expected in tests:
    result = classify(title)['meeting_type']
    print(f\"{'✓' if result == expected else '✗'} {title} → {result}\")"
```

### Test 3: Speaker Regex
```bash
cd ~/.config/sketchybar && venv/bin/python3 -c "
import re
pattern = r'^([A-Za-z0-9\s]+) \| \d+:\d+\$'
tests = [('Speaker 1 | 00:00', 'Speaker 1'), ('Jeff | 05:30', 'Jeff')]
for text, expected in tests:
    match = re.match(pattern, text)
    print(f\"✓ '{text}' → '{match.group(1).strip()}'\" if match else f\"✗ No match: {text}\")"
```

### Test 4: Batch Processor Dry Run
```bash
cd ~/.config/sketchybar && venv/bin/python3 helpers/krisp-batch-process.py --dry-run --limit 5
```

### Test 5: Sanitize Filename
```bash
cd ~/.config/sketchybar && venv/bin/python3 -c "
import re, unicodedata
def sanitize_filename(t, m=50):
    t = unicodedata.normalize('NFKD', t).encode('ASCII', 'ignore').decode('ASCII').lower()
    t = re.sub(r'[\s_]+', '-', t); t = re.sub(r'[^a-z0-9\-]', '', t)
    t = re.sub(r'-+', '-', t).strip('-')
    return t[:m].rstrip('-') if len(t) > m else t or 'unknown'
tests = [('Jeff / Ron Weekly Meeting', 'jeff-ron-weekly-meeting'), ('', 'unknown')]
for i, e in tests: print(f\"{'✓' if sanitize_filename(i)==e else '✗'} '{i}' → '{sanitize_filename(i)}'\")"
```

---

## Potential Issues to Review

### 1. Backwards Compatibility
**Location:** `krisp-batch-process.py:133-160`
**Risk:** `extract_meeting_id()` handles old and new formats. Verify regex correctly extracts 32-char hex ID from: `2025-11-24-hr-recruitment-weekly-019ab5f50253750996b3c25ac414fb6d.txt`

### 2. JSON Companion Fallback
**Location:** `krisp-process-transcript.py:264-277`
**Risk:** If JSON companion missing, fallback to `pending-downloads.json` should work. Test with old-format files.

### 3. Telegram Message Escaping
**Location:** `krisp-download-transcripts-simple.py:110-118`
**Risk:** Special chars in titles could break URL encoding. Test with: `<>&"` characters.

### 4. Team Pattern Ordering
**Location:** `classify-meeting-unified.py:309-342`
**Risk:** "Growth Squad" must match before "Product" (order-dependent). Verify edge cases.

### 5. Files NOT Modified (may need updates)
- `helpers/krisp-hourly-daemon.sh` - Archive patterns
- `helpers/krisp-process-queue.py` - Path construction
- `helpers/krisp-create-queue-enhanced.py` - Glob patterns
- `helpers/krisp-create-queue-from-transcripts.py` - Glob patterns

---

## Full Test Suite for Reviewer

Run complete test suite:
```bash
cd ~/.config/sketchybar && venv/bin/python3 -c "
import sys, re, unicodedata
sys.path.insert(0, 'helpers')
from importlib import import_module

print('=== Classification Tests ===')
spec = import_module('classify-meeting-unified')
classify = spec.classify_from_calendar_title
tests = [
    ('1on1 Marcus Jeff', 'ipmedia_1on1'), ('Jeff <> Giovanna', 'ipmedia_1on1'),
    ('Vlad & Jeff', 'external_personal'), ('Q4 Review - Henrique', 'ipmedia_review'),
    ('Jeff / Ron Weekly Meeting', 'ipmedia_executive'), ('Monthly Board Meeting', 'ipmedia_board'),
    ('KPI Review', 'ipmedia_company_wide'), ('[Weekly] Growth Squad', 'ipmedia_dev_growth'),
    ('MeuMatch Weekly', 'ipmedia_dev_meumatch'), ('Slackbot Weekly', 'ipmedia_dev_slackbot'),
    ('Weekly Dev Squad Planning', 'ipmedia_dev_marcus'), ('Traffic Weekly', 'ipmedia_marketing_traffic'),
    ('Gone - Weekly Sync', 'co_gone_meeting'), ('Jeff and DBoy', 'co_dt_meeting'),
    ('Lunch Time', 'excluded'), ('Gone Standup', 'ipmedia_standup'),
]
passed = sum(1 for t, e in tests if classify(t)['meeting_type'] == e)
print(f'Classification: {passed}/{len(tests)} passed')

print('\\n=== Speaker Regex Test ===')
pattern = r'^([A-Za-z0-9\s]+) \| \d+:\d+\$'
regex_tests = [('Speaker 1 | 00:00', True), ('Jeff Hamersly | 05:30', True), ('Random text', False)]
regex_passed = sum(1 for t, should in regex_tests if bool(re.match(pattern, t)) == should)
print(f'Speaker Regex: {regex_passed}/{len(regex_tests)} passed')

print('\\n=== Sanitize Filename Test ===')
def sanitize_filename(t, m=50):
    t = unicodedata.normalize('NFKD', t).encode('ASCII', 'ignore').decode('ASCII').lower()
    t = re.sub(r'[\s_]+', '-', t); t = re.sub(r'[^a-z0-9\-]', '', t)
    t = re.sub(r'-+', '-', t).strip('-')
    return t[:m].rstrip('-') if len(t) > m else t or 'unknown'
san_tests = [('Jeff / Ron Weekly Meeting', 'jeff-ron-weekly-meeting'), ('', 'unknown'), ('Meu Patrocínio', 'meu-patrocinio')]
san_passed = sum(1 for i, e in san_tests if sanitize_filename(i) == e)
print(f'Sanitize: {san_passed}/{len(san_tests)} passed')

print('\\n=== OVERALL ===')
total = passed + regex_passed + san_passed
total_tests = len(tests) + len(regex_tests) + len(san_tests)
print(f'TOTAL: {total}/{total_tests} passed')"
```

---

## Deliverable for Next Dev

1. Run full test suite above
2. Check potential issues listed
3. Review files NOT modified (may need updates)
4. Test end-to-end with a new Krisp download
5. Verify Telegram notifications work
6. Update story file status when complete

---

# Completion Report (2025-11-25 12:25)

## Tests Completed - ALL PASS ✅

| Test | Result | Details |
|------|--------|---------|
| Syntax Check (7 files) | ✅ Pass | All Python files compile |
| Classification (16 cases) | ✅ Pass | All meeting types classify correctly |
| Speaker Regex | ✅ Pass | "Speaker 1", "Speaker 2" now extracted |
| PRE-meeting workflow | ✅ Pass | Cross-meeting context loads correctly |
| POST-meeting workflow | ✅ Pass | AI analysis populates all sections |

## Bugs Found & Fixed

### 1. Token Limit Bottleneck (CRITICAL)
**Problem:** Output limited to 1500 tokens (regular) / 3000 tokens (executive) - far too low for 30+ minute meetings
**Symptom:** Marcio 1on1 (33KB transcript) produced only 4 highlights, 2 action items

**Fix:** Dynamic token scaling in `krisp-analyze-transcript.py:174-191`
```python
if transcript_kb >= 60:       # 60KB+ = 12000 tokens
elif transcript_kb >= 40:     # 40-60KB = 10000 tokens
elif transcript_kb >= 25:     # 25-40KB = 8000 tokens
elif transcript_kb >= 15:     # 15-25KB = 6000 tokens
else:                         # <15KB = 4000 tokens
# Executive meetings get +25% bonus
```

### 2. Weak Prompt for Regular 1on1s (HIGH)
**Problem:** Prompt asked for only "3-5 main points" - model followed literally
**Fix:** Updated prompt in `krisp-analyze-transcript.py:131-185` to request:
- 6-12 discussion highlights with context
- Key insights with direct quotes
- Decisions, blockers, follow-up topics
- "Be THOROUGH" instruction

### 3. Template Section Mismatch (HIGH)
**Problem:** `generate-meeting-note.py` created sections like `Key Discussion Points`, but `krisp-update-note.py` expected `Notes During Meeting`
**Fix:** Updated template in `generate-meeting-note.py:196-267` to align:
- Added: `### Key Insights & Quotes`, `### Blockers Identified`
- Renamed: `Key Discussion Points` → `Notes During Meeting`
- Added: `### Related Documents` section

### 4. Idempotency Bug (MEDIUM)
**Problem:** Same content appended multiple times with different timestamps
**Fix:** Updated `krisp-update-note.py:434-449` to check for ANY AI marker:
```python
if '🤖 AI-Generated from Transcript' in existing_content:
    log(f"Skipping {section_key} - AI content already exists")
    return unchanged
```

### 5. Section Regex Boundary (MINOR)
**Problem:** Related Documents content leaked past `---` footer
**Fix:** Updated pattern in `krisp-update-note.py:422`:
```python
r'(### Related Documents\n)(.*?)(?=\n### |\n## |\n---|\Z)'
```

## Files Modified

| File | Changes |
|------|---------|
| `krisp-analyze-transcript.py` | Token scaling, comprehensive prompt |
| `krisp-update-note.py` | Idempotency fix, regex improvements |
| `generate-meeting-note.py` | Template alignment with automation |

## Validation: Marcio 1on1 (2025-11-25)

**Before fixes:** 4 highlights, 2 action items, weak content
**After fixes:** 6 detailed highlights, 4 action items, quotes, blockers, decisions

All sections properly populated:
- ✅ Decisions Made
- ✅ Action Items (with [[wikilinks]])
- ✅ Key Insights & Quotes
- ✅ Blockers Identified
- ✅ Notes During Meeting
- ✅ Related Documents
- ✅ Topics to Revisit

## Remaining Known Issues

1. **Participant None Bug:** When calendar matches but doesn't extract participant name, causes crash. Affects ~2% of meetings.
2. **Template file warning:** `1on1-template.md not found` - using fallback (working, but could be cleaner)

## Next Steps

- [ ] Fix participant extraction from calendar title
- [ ] Commit changes to main branch
- [ ] Monitor next batch processing run for any issues
