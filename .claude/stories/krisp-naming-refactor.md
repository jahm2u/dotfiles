# Story: Krisp Transcript Naming Refactor

**Created:** 2025-11-25
**Status:** In Progress
**Priority:** High

## Problem Statement

The current Krisp automation system has several naming and classification issues:

1. **Opaque transcript filenames**: Files are named `krisp-transcript-{meeting_id}.txt` which is impossible to identify without looking up metadata
2. **Duplicate classification**: Calendar matching happens twice - once at download, again at processing
3. **Classification mismatches**: Some meetings are incorrectly categorized (e.g., "Growth Squad" → Product instead of Growth)
4. **No feedback loop**: When classification happens, there's no visibility to correct mistakes
5. **Scattered source of truth**: Metadata exists in multiple places (JSON companion file, pending-downloads.json, processed cache)

## Solution Overview

Refactor the naming system to:
1. **Rename transcript files** at download time using resolved calendar title
2. **Single source of truth**: Download step does classification once, everything else references it
3. **Telegram feedback**: Send notification with chosen name so user can verify/correct
4. **Fix classification patterns**: Update team mappings for accuracy
5. **No backwards compatibility**: Clean break, reprocess existing transcripts

## Acceptance Criteria

- [ ] Transcript files named: `{date}-{sanitized-calendar-title}-{meeting_id}.txt`
- [ ] JSON metadata files named: `{date}-{sanitized-calendar-title}-{meeting_id}.json`
- [ ] Processing scripts read from JSON companion file, not re-classify
- [ ] Telegram notification shows: meeting title, resolved name, classification
- [ ] User can reply to Telegram with correction (future: auto-learn from corrections)
- [ ] Growth Squad → Growth team (not Product)
- [ ] All existing scripts updated to new naming convention
- [ ] Old transcripts can be migrated or reprocessed

## Files to Modify

### Core Download/Naming (Primary Changes)
- [ ] `krisp-download-transcripts-simple.py` - Rename files at download time
- [ ] `classify-meeting-unified.py` - Fix Growth Squad and other classification patterns

### Processing Scripts (Update References)
- [ ] `krisp-batch-process.py` - Update glob pattern and ID extraction
- [ ] `krisp-process-transcript.py` - Read from JSON companion instead of re-classifying
- [ ] `krisp-process-queue.py` - Update transcript path construction
- [ ] `krisp-create-queue-enhanced.py` - Update glob and ID extraction
- [ ] `krisp-create-queue-from-transcripts.py` - Update glob and ID extraction

### Daemon/Orchestration
- [ ] `krisp-hourly-daemon.sh` - Update archive patterns and path references

### Telegram Integration
- [ ] Add feedback notification after successful classification
- [ ] Include: original Krisp title, resolved calendar title, meeting type, confidence
- [ ] Format for easy copy/paste if correction needed

## Technical Design

### New Naming Convention

```
OLD: krisp-transcript-019ab5f50253750996b3c25ac414fb6d.txt
NEW: 2025-11-24-hr-recruitment-weekly-019ab5f50253750996b3c25ac414fb6d.txt

OLD: krisp-transcript-019ab5f50253750996b3c25ac414fb6d.json
NEW: 2025-11-24-hr-recruitment-weekly-019ab5f50253750996b3c25ac414fb6d.json
```

### Sanitization Rules for Filenames
- Lowercase all characters
- Replace spaces with hyphens
- Remove special characters except hyphens
- Truncate to max 50 chars (before meeting_id)
- Preserve meeting_id at end for uniqueness

### Classification Schema (COMPLETED)

### Meeting Type Hierarchy

```
ipmedia_*
├── ipmedia_1on1              # 1:1 meetings with team members
├── ipmedia_review            # Q4/Quarterly person reviews → Person/Reviews/
├── ipmedia_onboarding        # Welcome/onboarding new hires
├── ipmedia_executive         # Ron meetings (special cross-meeting context)
├── ipmedia_board             # Monthly investor board meetings
├── ipmedia_company_wide      # Internal meetings, KPI reviews, All Hands
├── ipmedia_standup           # Daily standups
├── ipmedia_team_*            # Regular team meetings
│   ├── ipmedia_team_hr
│   ├── ipmedia_team_leadership
│   ├── ipmedia_team_product
│   ├── ipmedia_team_operations
│   ├── ipmedia_team_bi
│   ├── ipmedia_team_suporte
│   └── ipmedia_team_marketing
├── ipmedia_dev_*             # Development squads
│   ├── ipmedia_dev_growth    # Growth Squad
│   ├── ipmedia_dev_meumatch  # MeuMatch product squad
│   ├── ipmedia_dev_slackbot  # Slackbot squad
│   └── ipmedia_dev_marcus    # Generic dev squad (Marcus's)
└── ipmedia_marketing_*       # Marketing sub-teams
    ├── ipmedia_marketing_traffic
    ├── ipmedia_marketing_social_pr
    └── ipmedia_marketing_seo

co_*                          # Portfolio companies
├── co_tp_meeting
├── co_excelsior_meeting
├── co_pd_meeting
├── co_mt_meeting             # MassTraffic
├── co_gone_meeting           # Gone investor meetings
└── co_dt_meeting             # DT (DBoy/Daniel)

external_personal             # Personal external (Vlad, etc.)
excluded                      # Lunch, breaks, cowork sessions
unknown                       # Unclassified → Unclassified folder
```

### Test Results: 35/35 PASSED

### Telegram Notification Format

```
📝 Krisp Meeting Classified

Original: 02:31 PM - Slack meeting November 24
Resolved: [Weekly] Growth Squad
Type: ipmedia_team_growth
Confidence: 0.85

File: 2025-11-24-weekly-growth-squad-019ab6ec...txt

Reply with correction if wrong:
/fix 019ab6ec... team_name
```

## Implementation Checklist

### Phase 1: Classification Fixes
- [ ] Add Growth team to `extract_team_from_title()`
- [ ] Review all team patterns for accuracy
- [ ] Test with existing meeting titles

### Phase 2: Download Naming
- [ ] Create `sanitize_filename()` function
- [ ] Update `krisp-download-transcripts-simple.py` to use new naming
- [ ] Update JSON companion file naming
- [ ] Add Telegram notification after successful classification

### Phase 3: Processing Updates
- [ ] Update `krisp-process-transcript.py` to read classification from JSON
- [ ] Remove redundant calendar matching call
- [ ] Update all glob patterns in batch/queue scripts

### Phase 4: Daemon Updates
- [ ] Update `krisp-hourly-daemon.sh` archive patterns
- [ ] Test full pipeline end-to-end

### Phase 5: Migration (Optional)
- [ ] Script to rename existing transcripts
- [ ] Or just reprocess from Krisp API

## Testing Plan

1. Download a new transcript - verify new naming format
2. Check Telegram notification received with correct info
3. Process the transcript - verify it uses JSON metadata
4. Run batch process - verify it finds new-format files
5. Check daemon archive - verify it handles new names

## Rollback Plan

If issues arise:
1. Old transcripts still exist (copy, not move initially)
2. Can revert scripts to old naming pattern
3. Krisp API can re-download if needed

## Notes

- No backwards compatibility needed per user request
- Clean break is acceptable
- Focus on getting it right for future runs
- Existing processed meetings are fine, just fix going forward
