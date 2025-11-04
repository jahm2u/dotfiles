# Krisp Transcript Backfill - Development Handoff

**Date:** 2025-11-03
**Status:** Phase 1 Complete (Downloads), Phase 2 Blocked (Processing)
**Priority:** HIGH - 98 transcripts waiting for processing

---

## Current State Summary

### ✅ What's Working

**Phase 1: Transcript Download (COMPLETE)**
- 98 transcripts successfully downloaded from Krisp.ai (Oct 6-31, 2025)
- Location: `~/.config/sketchybar/krisp-transcripts/`
- Download success rate: 99% (96 successful, 1 failed - transcript not ready on Krisp side)
- All transcripts have metadata in `~/.cache/sketchybar/krisp-pending-downloads.json`
- Backfill covered ~4 weeks (target was 8 weeks to Sept 8, but Krisp only had Oct 6 onwards)

**Infrastructure**
- ✅ Family folder search working - includes `Personal/Family/` path
  - Brighton, Evelyn, Mom folders all found correctly
- ✅ Meeting note template system functional
- ✅ Obsidian vault integration configured
- ✅ OpenAI API configured for AI analysis (GPT-4o-mini)
- ✅ Transcript storage and organization working

### ❌ What's Blocked

**Phase 2: Transcript Processing (BLOCKED)**
- Calendar matching via `khal` is too slow (2+ minutes per transcript)
- Root cause: khal database has 8000+ events from two ICS files
- Impact: 95 transcripts × 2 min each = **3+ hours** to process
- Current approach relies on calendar matching to determine meeting context

**Performance Issue Details:**
- `khal list YYYY-MM-DD 1d` takes ~2 minutes with 8000+ events
- Timeout increased to 180 seconds but still blocks workflow
- Calendar matching was designed to verify transcript date/time against calendar
- This is unnecessary - we can infer context from transcript content directly

---

## 🎯 TASK 1: Create Improved Backfill Script (PRIORITY)

### Goal
Create `krisp-backfill-smart.py` that processes transcripts WITHOUT slow calendar matching by analyzing transcript content directly with AI.

### Requirements

#### 1. Transcript Filtering
**Skip short meetings (< 3 minutes) - these are recording glitches**
```python
# Estimate meeting duration from transcript
# Count speakers, timestamps, or character count
# Skip if < 3 minutes worth of content
```

#### 2. AI-Powered Participant Identification
**Use GPT-4o-mini to analyze transcript and identify who it's with**

Input to AI:
- Full transcript text
- Known people context (see below)
- Meeting date/time from filename

AI should return:
- Primary participant name (matched to existing folders)
- Meeting type (1-on-1, family, team)
- Confidence level

#### 3. Known People & Patterns

**Daily Patterns:**
- Brighton (daughter) - calls daily, usually Discord/Slack
- Evelyn (daughter) - calls daily, usually Discord/Slack
- Look for voice/conversation patterns indicating family vs work

**Work Team (IPMedia):**
Location: `$VAULT/Business/People/IPMedia/`
- Check existing folders, classify-meeting.py has name aliases:
  - DBoy → Danniboy
  - Kayla → Queila
  - Kyle → Caio
  - RafaelN → Rafael

**Family:**
Location: `$VAULT/Personal/Family/`
- Brighton (daughter)
- Evelyn (daughter)
- Mom

**Friends:**
Location: `$VAULT/Personal/Friends/`
- (enumerate existing folders)

#### 4. Smart Matching Logic

```python
def identify_meeting_participant(transcript_text, meeting_date, meeting_time):
    """
    Use AI to analyze transcript and identify participant.

    Returns:
        {
            'participant': 'Brighton',  # Name matching folder
            'folder_path': '/path/to/Brighton',
            'meeting_type': '1on1',
            'confidence': 'high',
            'reasoning': 'Daughter mentioned school band practice...'
        }
    """
    # 1. Load list of all known people from vault structure
    # 2. Build AI prompt with transcript + context
    # 3. Ask AI: "Who is Jeff talking to? Match to existing people."
    # 4. Validate AI response against known folders
    # 5. Return match with confidence
```

**AI Prompt Structure:**
```
You are analyzing a meeting transcript to identify who Jeff Hamersly is meeting with.

TRANSCRIPT:
{transcript_text}

MEETING METADATA:
- Date: {date}
- Time: {time}
- Source: {slack/discord/teams}

KNOWN PEOPLE:
Family (daily calls expected):
- Brighton (daughter, teenage, mentions school/band)
- Evelyn (daughter, younger, mentions school/friends)
- Mom (mother, discusses family matters)

Work Team (IPMedia):
- [list from vault folders]

Friends:
- [list from vault folders]

TASK:
1. Identify the PRIMARY person Jeff is talking to
2. Match to ONE person from the KNOWN PEOPLE list above
3. Determine meeting type: 1on1, family, team, or company
4. Provide confidence: high/medium/low

Return JSON:
{
    "participant": "Brighton",
    "meeting_type": "family",
    "confidence": "high",
    "reasoning": "Teen daughter discussing band practice and school events"
}
```

#### 5. Fallback Handling

If AI can't identify participant with high confidence:
- Save to `$VAULT/Meetings/Unclassified/YYYY-MM-DD-HH-MM.md`
- Flag for manual review
- Include AI reasoning in note for user context

#### 6. Script Flow

```python
# For each transcript in oldest → newest order:

1. Load transcript file
2. Check duration (skip if < 3 min)
3. Parse metadata from filename
4. Identify participant via AI (new approach)
5. Find/create person folder
6. Generate meeting note with AI analysis:
   - Discussion highlights
   - Action items
   - Topics for next time
   - Related context
7. Save note to person's Meetings/ folder
8. Move transcript to person's attachments/
9. Mark as processed in cache
```

#### 7. Expected Performance
- No khal queries = instant participant identification
- AI analysis: ~5-10 seconds per transcript
- Total time: 95 transcripts × 10 sec = **~15 minutes** (vs 3+ hours)

### Implementation Files

**Create:**
- `helpers/krisp-backfill-smart.py` - Main backfill script
- `helpers/identify-participant-from-transcript.py` - AI participant identifier

**Modify:**
- `helpers/krisp-process-transcript.py` - Add option to skip calendar matching

### Success Criteria

✅ Processes all 95 transcripts in < 30 minutes
✅ Correctly identifies Brighton/Evelyn daily calls
✅ Skips recordings < 3 minutes
✅ Creates meeting notes with AI analysis
✅ Less than 10% need manual review (unclassified)
✅ Notes include all sections: highlights, actions, topics, context

---

## TASK 2: Verify One Complete Example

After Task 1 is implemented:
1. Process the first 5 transcripts
2. Show Jeff one complete example:
   - Brighton or Evelyn meeting note
   - Verify AI correctly identified it's a daughter call
   - Check note has all sections filled
   - Confirm transcript is organized properly
3. Get approval before processing remaining 90

---

## TASK 3: Complete Backfill

Once example is approved:
1. Run full backfill on remaining transcripts
2. Generate summary report:
   - How many per person
   - How many unclassified
   - Any errors/failures
3. Review unclassified meetings with Jeff for patterns

---

## Architecture Context

### File Locations

**Transcripts:** `~/.config/sketchybar/krisp-transcripts/`
**Cache:** `~/.cache/sketchybar/krisp-*.json`
**Obsidian Vault:** `$OBSIDIAN_VAULT_PATH` (from .env)
**Person Folders:** `$VAULT/{Personal/Family, Personal/Friends, Business/People/IPMedia}`
**Python venv:** `~/.config/sketchybar/venv/bin/python3`
**Logs:** `~/.config/sketchybar/logs/krisp-*.log`

### Key Scripts

**Working (don't modify):**
- `krisp-download-transcripts.py` - Browser automation download (✅ works)
- `krisp-discover-meetings.py` - Pagination & metadata extraction (✅ works)
- `krisp-process-queue.py` - Download queue processor (✅ works)
- `find-person-folder.sh` - Vault folder search (✅ works, includes Family)
- `classify-meeting.py` - Meeting type classifier (✅ works)
- `krisp-analyze-transcript.py` - AI analysis (✅ works)
- `krisp-update-note.py` - Note updater (✅ works)

**Needs Work:**
- `krisp-match-meetings.py` - Calendar matcher (too slow, bypass this)
- `krisp-process-transcript.py` - Full pipeline (relies on slow calendar matching)
- `krisp-batch-process.py` - Batch processor (blocked by above)

### Environment Variables (.env)

```bash
OBSIDIAN_VAULT_PATH="/Users/v/Library/Mobile Documents/iCloud~md~obsidian/Documents/U"
OPENAI_API_KEY="sk-..." # GPT-4o-mini for analysis
TELEGRAM_BOT_TOKEN="..." # Optional notifications
TELEGRAM_CHAT_ID="..." # Optional notifications
```

### Dependencies

All installed in venv:
```
openai==1.12.0
python-dotenv==1.0.0
pyyaml==6.0.1
playwright==1.40.0
playwright-stealth==1.0.0
```

---

## Known Issues & Notes

### Performance
- khal is slow with 8000+ events - this is why we're bypassing calendar matching
- AI analysis (GPT-4o-mini) is fast and cheap (~$0.005 per transcript)
- Total cost for 95 transcripts: ~$0.50

### Edge Cases
1. **Multiple speakers in transcript** - AI should identify PRIMARY person Jeff is meeting with
2. **Group calls** - For now, treat as 1-on-1 with most active participant
3. **Very short transcripts** - Skip anything < 3 minutes (glitches)
4. **Unknown participants** - Save to Unclassified folder, flag for review

### Testing Strategy
1. Test with Brighton transcript first (known daily pattern)
2. Test with work colleague (known IPMedia person)
3. Test with short transcript (should skip)
4. Then process batch

---

## Future Enhancements (Post-Backfill)

### Optimization Ideas
1. **Cache AI participant identification** - Don't re-analyze same speakers
2. **Pattern learning** - Track which time slots = which people (Brighton calls at X time)
3. **Calendar sync improvement** - Reduce khal database to 30-60 days for speed
4. **Batch AI calls** - Send multiple transcripts to AI at once for efficiency
5. **Voice identification** - Use Krisp's speaker labels if available

### Integration Ideas
1. **Auto-create calendar events** - If transcript has no matching calendar event, create one
2. **Action item tracking** - Extract action items into separate task system
3. **Meeting prep integration** - Use previous transcripts for meeting prep workflow
4. **Relationship mapping** - Track communication patterns over time

---

## Questions for Jeff (When Resuming)

1. Should unclassified meetings go into a specific folder, or skip them entirely?
2. What confidence level threshold? (high only, or include medium?)
3. Any other daily patterns besides Brighton/Evelyn calls?
4. Should we notify via Telegram when backfill completes?
5. Want to review sample notes before processing all 95?

---

## Testing Commands

**Check transcripts:**
```bash
ls -lh ~/.config/sketchybar/krisp-transcripts/*.txt | wc -l
# Should show 98 files
```

**Check metadata:**
```bash
jq '.total_pending' ~/.cache/sketchybar/krisp-pending-downloads.json
# Should show 96
```

**Test person folder search:**
```bash
bash ~/.config/sketchybar/helpers/find-person-folder.sh --person "Brighton" --company "unknown"
# Should return: /path/to/Personal/Family/Brighton
```

**Test AI analysis:**
```bash
~/.config/sketchybar/venv/bin/python3 \
  ~/.config/sketchybar/helpers/krisp-analyze-transcript.py \
  --transcript /path/to/transcript.txt \
  --note /path/to/note.md \
  --person "Brighton" \
  --company "Family" \
  --meeting-type "1on1" \
  --date "2025-10-06" \
  --json
```

---

## Success Metrics

**Phase 1 (Complete):** ✅
- 98 transcripts downloaded
- 96 with valid metadata
- 99% success rate

**Phase 2 (Pending):**
- [ ] 95 transcripts processed in < 30 minutes
- [ ] 90%+ automatically classified (< 10% unclassified)
- [ ] Brighton/Evelyn calls correctly identified
- [ ] All notes have complete AI analysis
- [ ] Transcripts organized in person folders
- [ ] Zero data loss (all transcripts accounted for)

---

## Logs to Monitor

```bash
# Main processing log
tail -f ~/.config/sketchybar/logs/krisp-batch-process.log

# Download log (already complete)
tail -f ~/.config/sketchybar/logs/krisp-processing.log

# Automation pipeline log
tail -f ~/.config/sketchybar/logs/krisp-automation.log
```

---

## Git Status

**Modified files (ready to commit after successful backfill):**
```
M config/sketchybar/helpers/find-person-folder.sh  # Added Personal/Family path
M config/sketchybar/helpers/krisp-match-meetings.py  # Increased timeout to 180s
M config/sketchybar/helpers/krisp-process-transcript.py  # Fixed calendar match contract
M .env  # Cleaned up line 8 parse error
```

**New files to create:**
```
+ helpers/krisp-backfill-smart.py  # Main backfill script (TASK 1)
+ helpers/identify-participant-from-transcript.py  # AI participant ID
+ .claude/docs/krisp-backfill-handoff.md  # This document
```

---

## Contact Context

**User:** Jeff Hamersly
**Daughters:** Brighton (teenage, band practice), Evelyn (younger)
**Meeting Patterns:** Daily calls with daughters, frequent IPMedia team meetings
**Vault Structure:** Well-organized with Business/Personal separation
**Preferences:** Wants automated backfill, minimal manual review

---

## Next Session Checklist

When next dev picks this up:

1. [ ] Read this entire handoff document
2. [ ] Verify all 98 transcripts still present
3. [ ] Implement Task 1: krisp-backfill-smart.py
4. [ ] Test with Brighton transcript first
5. [ ] Show Jeff one complete example
6. [ ] Get approval
7. [ ] Run full backfill (95 transcripts)
8. [ ] Generate summary report
9. [ ] Commit changes with clear message
10. [ ] Update this handoff with results

---

**End of Handoff Document**
