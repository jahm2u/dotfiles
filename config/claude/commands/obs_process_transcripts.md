# Transcript Processing Workflow

## 🚀 AUTONOMOUS OPERATION - CONTINUOUS UNTIL COMPLETE
**CRITICAL: Process transcripts in `Inbox/Transcripts/` using ROLLING QUEUE (MAX 5 concurrent).**
**EACH Task uses MCP commands with relevant_files to SEND transcript files.**
**START 5 → FINISH 1 → START NEXT → Keep 5 running until all done!**

### ⚠️ CONTINUOUS PROCESSING MANDATE
**DO NOT STOP AFTER ANY BATCH COMPLETION!**
- After each 5-task batch completes → **IMMEDIATELY** launch next 5 tasks
- Continue this pattern until `Inbox/Transcripts/` is completely empty
- Only stop when transcript count = 0
- Update progress but never end until 100% complete

## ⚠️ CLAUDE'S ROLE: COORDINATOR ONLY
**CLAUDE MUST NOT ANALYZE TRANSCRIPTS DIRECTLY.**

## 🛠️ Tools: `mcp__zen__analyze` | `mcp__zen__chat` | `Task` for concurrency

---

## 📋 Streamlined Workflow (4 Steps Per Transcript)

### Step 0: Unzip and Prepare Transcripts
**PREPROCESSING STEP:**
```bash
# CRITICAL: Always start from root directory
cd "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/[VAULT_NAME]"

# Step 1: Unzip transcript files (handles summary peeking and audio files)
python3 claude-obsidian/scripts/transcript_unzip_processor.py /path/to/transcripts.zip
# OR to scan Downloads folder:
python3 claude-obsidian/scripts/transcript_unzip_processor.py

# Step 2: OPTIONAL - Match transcripts with calendar (just helpful metadata)
# IMPORTANT: Unmatched transcripts still get processed normally!
python3 claude-obsidian/scripts/transcript_meeting_matcher.py --show-matches --export

# This will:
# - Extract all transcript folders from zip (if zipped)
# - Peek at summaries for context (then delete them)
# - Identify audio files to archive with transcripts
# - Match transcripts to calendar meetings (if possible)
# - Show confidence scores and destinations
# - Export matches to transcript-matches.json

# NOTE: Meeting matching is OPTIONAL metadata only!
# ALL transcripts get processed whether matched or not!
```

### Step 0.5: Setup Rolling Queue Processing
**ROLLING QUEUE APPROACH:**
1. List all transcript folders in `Inbox/Transcripts/`
2. Start 5 concurrent Task subtasks for first 5 transcripts
3. As each Task completes, start next transcript Task
4. Keep 5 Tasks running until all transcripts processed
5. Each Task uses MCP commands to SEND transcript files

**EXAMPLE ROLLING QUEUE SETUP:**
```bash
# CRITICAL: Always start from and return to root directory
cd "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/[VAULT_NAME]"

# First, check what transcripts exist using LS tool instead of find
# Use LS tool with path parameter

# Start first 5 concurrent Tasks:
Task description="Process transcript 1" prompt="[STREAMLINED WORKFLOW for folder 1]"
Task description="Process transcript 2" prompt="[STREAMLINED WORKFLOW for folder 2]"  
Task description="Process transcript 3" prompt="[STREAMLINED WORKFLOW for folder 3]"
Task description="Process transcript 4" prompt="[STREAMLINED WORKFLOW for folder 4]"
Task description="Process transcript 5" prompt="[STREAMLINED WORKFLOW for folder 5]"

# As Task 1 completes, start Task 8
# As Task 2 completes, start Task 9
# Keep 5 running until all transcripts processed

# CRITICAL: Always return to root after each operation
cd "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/[VAULT_NAME]"
```

### STREAMLINED TASK WORKFLOW (Per Transcript):

### Step 1: Quick Gibberish & Existing Meeting Check (Claude Direct)
```bash
# CRITICAL: Always work from root directory
cd "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/[VAULT_NAME]"

# Claude checks directly (no MCP tool needed):
1. Read first 500 lines of transcript
2. Check if gibberish/noise/unintelligible → If yes, archive and skip
3. Check for existing meeting note (same date, same participants) in:
   - Business/People/*/[PersonName]/Meetings/
   - Personal/Family/[PersonName]/Meetings/
   - Business/IPMedia/Meetings/
   - Business/CO/Meetings/
4. If existing meeting found:
   - Check if it's just template content (no real notes)
   - If template only → Will replace with transcript content
   - If has existing notes → Mark for ENRICHMENT MODE in Step 3
5. If valid → Continue to Step 2
```

**If gibberish → Archive transcript to Archive/Skipped/ and end Task**

### Step 2: Full Analysis (Combined) - `@analyze`
```
# CRITICAL: Always work from root directory
cd "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/[VAULT_NAME]"

Use mcp__zen__analyze with:
- model: "o3"
- relevant_files: ["~/Library/Mobile Documents/iCloud~md~obsidian/Documents/[VAULT_NAME]/Inbox/Transcripts/FOLDER/transcript.txt", "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/[VAULT_NAME]/claude-obsidian/docs/People-Directory.md"]
- step: "FULL ANALYSIS - Jeff is main speaker. 'You/voce' = Jeff. Provide: 1) Meeting participants (use People-Directory.md for reference), 2) Meeting type (1on1/team/board/family), 3) Company/Context (IPMedia/CO/Personal), 4) Key topics discussed, 5) Action items, 6) Meeting date (YYYY-MM-DD format), 7) Meeting title suggestion, 8) Important quotes from Jeff, 9) Key decisions made, 10) Follow-up items"
- step_number: 1
- total_steps: 1
- next_step_required: false
```

### Step 3: Create/Enrich Meeting Note (With Specific Location Rules)
Claude creates or enriches meeting note based on Step 1 findings:

**MODE DECISION (from Step 1):**
- **CREATE MODE**: No existing note → Create new from template
- **ENRICHMENT MODE**: Existing note with content → Merge transcript insights

**LOCATION RULES:**
1. **1-on-1 Meetings**: 
   - Business contacts: `Business/People/[COMPANY]/[PersonName]/Meetings/YYYY-MM-DD 1on1.md`
   - Family members: `Personal/Family/[PersonName]/Meetings/YYYY-MM-DD 1on1.md`
   - Use Template: `Templates/1on1 Template.md`

2. **Team/Group Meetings**:
   - IPMedia meetings: `Business/IPMedia/Meetings/YYYY-MM-DD [MeetingTitle].md`
   - CO meetings: `Business/CO/Meetings/YYYY-MM-DD [MeetingTitle].md`
   - Family gatherings: `Personal/Family/Meetings/YYYY-MM-DD [MeetingTitle].md`
   - Use Template: `Templates/Meeting Template.md`

3. **Board/Investor Meetings**:
   - Save to: `Business/[Company]/Meetings/Board/YYYY-MM-DD [MeetingTitle].md`
   - Use Template: `Templates/Meeting Template.md`

**ENRICHMENT MODE RULES:**
- Preserve existing human-written notes
- Add new sections: "## Transcript Insights" with key points from analysis
- Update/expand "## Action Items" if new ones found
- Add "## Key Quotes" section if notable quotes exist
- Append to "## Topics Discussed" without duplicating
- Add attachments section:
```markdown
## Attachments
- **Original Transcript**: [[attachments/YYYY-MM-DD-original.txt]]
- **Audio Recording**: [[attachments/YYYY-MM-DD-audio.m4a]]
```

### Step 4: Final Quality Review & Archive - `@chat`
```
# CRITICAL: Always work from root directory
cd "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/[VAULT_NAME]"

Use mcp__zen__chat with:
- model: "grok-4"
- prompt: "FINAL QUALITY REVIEW: Check meeting note accuracy and completeness. Ensure key topics, action items, and important quotes are captured. If quality is good, respond 'APPROVED - ARCHIVE'. If needs improvement, provide specific fixes."
- files: ["~/Library/Mobile Documents/iCloud~md~obsidian/Documents/[VAULT_NAME]/MEETING_NOTE_PATH"]

If APPROVED, archive:
# Ensure attachments folder exists (same location as meeting note)
# For 1on1s: Business/People/[COMPANY]/[PersonName]/Meetings/attachments/
# For team meetings: Business/[Company]/Meetings/attachments/
# For family: Personal/Family/[PersonName]/Meetings/attachments/

mkdir -p "[MEETING_NOTE_DIRECTORY]/attachments"

# Archive transcript
mv "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/[VAULT_NAME]/Inbox/Transcripts/[FOLDER]/transcript.txt" \
   "[MEETING_NOTE_DIRECTORY]/attachments/YYYY-MM-DD-original.txt"

# Archive audio file (if exists)
if ls "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/[VAULT_NAME]/Inbox/Transcripts/[FOLDER]/"*.{mp3,m4a,wav,ogg,aac} 1> /dev/null 2>&1; then
    mv "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/[VAULT_NAME]/Inbox/Transcripts/[FOLDER]/"*.{mp3,m4a,wav,ogg,aac} \
       "[MEETING_NOTE_DIRECTORY]/attachments/YYYY-MM-DD-audio.*"
fi

# Clean up empty folder
rmdir "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/[VAULT_NAME]/Inbox/Transcripts/[FOLDER_NAME]"

# CRITICAL: Return to root directory
cd "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/[VAULT_NAME]"
```

### Rolling Queue Management
**CONCURRENT PROCESSING PATTERN:**
```
INITIAL: Start 5 Tasks (transcripts 1, 2, 3, 4, 5, 6, 7)
Task 1 completes → Start Task 8 (transcript 8)
Task 2 completes → Start Task 9 (transcript 9)  
Task 3 completes → Start Task 10 (transcript 10)
Task 4 completes → Start Task 11 (transcript 11)
Task 5 completes → Start Task 12 (transcript 12)
Task 6 completes → Start Task 13 (transcript 13)
Task 5 completes → Start Task 14 (transcript 14)
Continue until all transcripts processed
```

**STREAMLINED TASK TEMPLATE:**
```
Task description="Process transcript X" prompt="
CRITICAL: Always work from root directory first!
cd '~/Library/Mobile Documents/iCloud~md~obsidian/Documents/[VAULT_NAME]'

CRITICAL: Use zen-mcp-server tools properly!

1. Quick gibberish & existing meeting check (Claude direct check)
   - IF GIBBERISH → Archive to Archive/Skipped/ and end Task
   - IF EXISTING MEETING → Note if template-only or has content for Step 3

2. Use mcp__zen__analyze for full analysis with People-Directory reference

3. Create OR enrich meeting note:
   - CREATE MODE: New note from template
   - ENRICHMENT MODE: Merge with existing content (preserve human notes)

4. Use mcp__zen__chat for final review & archive

TOTAL: 4 steps

CRITICAL: Return to root after completion!
cd '~/Library/Mobile Documents/iCloud~md~obsidian/Documents/[VAULT_NAME]'
"
```

---

## 🚨 CRITICAL RULES
1. **ROLLING QUEUE: 5 concurrent, add new as each finishes**
2. **EARLY GIBBERISH DETECTION** - Skip meaningless transcripts immediately
3. **HANDLE EXISTING MEETINGS** - Enrich existing notes, don't overwrite human content
4. **STREAMLINED: 4 steps per transcript**
5. **CLAUDE CHECKS DIRECTLY** - No MCP tool for gibberish/existing meeting check
6. **USE MCP FOR ANALYSIS** - Use mcp__zen__analyze for full transcript analysis
7. **SPECIFIC MEETING LOCATIONS** - Follow exact folder structure rules for each meeting type
8. **ENRICHMENT MODE** - Preserve human notes, add transcript insights as new sections
9. **USE TEMPLATES** - Meeting templates from Templates/ folder for new notes only
10. **QUALITY GATE** - Final review before archiving
11. **NEVER STOP UNTIL COMPLETE** - Continue launching new batches until inbox is empty

## 🔄 CONTINUOUS PROCESSING MANDATE

**CRITICAL: DO NOT STOP AFTER ANY BATCH - CONTINUE UNTIL COMPLETE!**

After each batch of 5 tasks completes:
1. **IMMEDIATELY** check remaining transcript count using LS tool
2. **IF COUNT > 0** → Launch next 5 concurrent Tasks immediately
3. **ONLY STOP** when count = 0 (inbox completely empty)
4. **UPDATE TODO** with current progress but DO NOT END

**AUTOMATION PATTERN:**
```
BATCH 1: Launch 5 → Wait for completion → Count remaining
BATCH 2: Launch 5 → Wait for completion → Count remaining  
BATCH 3: Launch 5 → Wait for completion → Count remaining
...continue until inbox count = 0
```

**WORKFLOW: CD to root → List All → Start 5 Tasks → As each finishes, start next → Keep 5 running → **CONTINUE LAUNCHING NEW BATCHES** → Complete only when inbox empty**
**SUCCESS: LS tool returns empty result for Inbox/Transcripts AND all Tasks completed**

## 🔧 Efficiency Improvements
- **60% fewer AI calls** (4 vs 10 per transcript)
- **Early gibberish detection** saves processing time
- **Smart meeting handling** - enriches existing notes instead of duplicating
- **No MCP tool for initial check** - Claude checks directly
- **Rolling queue** maintains constant throughput
- **Simplified workflow** - removed profile updates and journal creation
- **Specific location rules** prevent meeting note placement errors
- **Enrichment mode** preserves human notes while adding transcript insights
- **Single quality gate** vs multiple reviews
