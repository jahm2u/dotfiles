# Meeting Prefill Workflow

## 🚀 AUTONOMOUS OPERATION - WEEK-BASED PROCESSING
**CRITICAL: Process meeting files in `Inbox/Meetings/` using ROLLING QUEUE (MAX 5 concurrent).**
**EACH Task uses MCP commands to analyze meeting metadata and create prefilled notes.**
**START 5 → FINISH 1 → START NEXT → Keep 5 running until all done!**

### ⚠️ CONTINUOUS PROCESSING MANDATE
**DO NOT STOP AFTER ANY BATCH COMPLETION!**
- After each 5-task batch completes → **IMMEDIATELY** launch next 5 tasks
- Continue this pattern until `Inbox/Meetings/` is completely empty
- Only stop when meeting count = 0
- Update progress but never end until 100% complete

## ⚠️ MEETING PROCESSING RULES
**CRITICAL PATTERNS TO RECOGNIZE:**
- **SKIP:** Ops Team, Headquarters, Traffic HQ, MPalpite Weekly, Daily/Standups, Team Meetings
- **1on1s:** "1on1 [Name] Jeff" → Create in Business/People/IPMedia/[Name]/Meetings/
- **CO Meetings:** 
  - "Weekly TP" → CO TP (Business/People/CO/TP/)
  - "MassTraffic Weekly" → CO MT (Business/People/CO/MT/Chris/)
  - "Excelsior" → CO EX (Business/People/CO/EX/Felipe/)
  - "Jeff and DBoy" → CO DT (Business/People/CO/DT/Danniboy/)
  - "PD - Best Meeting" → CO PD (Business/People/CO/PD/Kyle/)
- **Welcome Meetings:** Create new person folder structure

## 🛠️ Tools: `mcp__zen__analyze` | `mcp__zen__chat` | `Task` for concurrency

---

## 📋 Meeting Prefill Workflow (5 Steps Per Meeting)

### Step 0: Initial Week Prefill
**RUN ONCE AT START:**
```bash
# CRITICAL: Always start from root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

# Run the weekly prefill script first
cd claude-obsidian/scripts && python3 weekly_meeting_prefill.py

# This creates JSON files in Inbox/Meetings/ for the week
# Current week (Mon-Thu) or Next week (Fri-Sun)
```

### Step 1: Setup Rolling Queue Processing
**ROLLING QUEUE APPROACH:**
1. List all JSON files in `Inbox/Meetings/`
2. Start 5 concurrent Task subtasks for first 5 meetings
3. As each Task completes, start next meeting Task
4. Keep 5 Tasks running until all meetings processed
5. Each Task uses MCP commands to analyze and create notes

**EXAMPLE ROLLING QUEUE SETUP:**
```bash
# CRITICAL: Always start from and return to root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

# First, check what meeting files exist using LS tool
# Use LS tool with path parameter

# Start first 5 concurrent Tasks:
Task description="Process meeting 1" prompt="[MEETING WORKFLOW for file 1]"
Task description="Process meeting 2" prompt="[MEETING WORKFLOW for file 2]"  
Task description="Process meeting 3" prompt="[MEETING WORKFLOW for file 3]"
Task description="Process meeting 4" prompt="[MEETING WORKFLOW for file 4]"
Task description="Process meeting 5" prompt="[MEETING WORKFLOW for file 5]"

# As Task 1 completes, start Task 6
# As Task 2 completes, start Task 7
# Keep 5 running until all meetings processed

# CRITICAL: Always return to root after each operation
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"
```

### MEETING TASK WORKFLOW (Per Meeting File):

### Step 1: Quick Meeting Type Check - `@analyze`
```
# CRITICAL: Always work from root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

Use mcp__zen__analyze with:
- model: "o3"
- relevant_files: ["/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Inbox/Meetings/MEETING_FILE.json"]
- step: "MEETING TYPE CHECK: Analyze this meeting JSON. Determine: 1) Should we SKIP (ops team, HQ, team meeting, etc.), 2) Type: IPMEDIA_1ON1, CO_MEETING (specify which), or NEW_PERSON, 3) Person name if 1on1, 4) Company if CO meeting. If SKIP, respond 'SKIP - [reason]' and stop."
- step_number: 1
- total_steps: 1
- next_step_required: false
```

**If response contains "SKIP" → Delete JSON file and end Task**

### Step 2: Find Previous Meeting & Deep Analysis - `@chat`
**For 1on1s and CO Meetings only:**
```
# CRITICAL: Always work from root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

# First use Python to find previous meeting
python3 Tests/action_item_utils.py --find-previous --person "[PERSON]" --company "[COMPANY]" --type "[TYPE]" --date "[DATE]"

# Then deep analysis with grok-4 if previous meeting found
Use mcp__zen__chat with:
- model: "grok-4"
- prompt: "DEEP MEETING ANALYSIS: Analyze the previous meeting notes to extract:
  1) ALL UNCHECKED ACTION ITEMS - List each with owner and due date
  2) UNRESOLVED DISCUSSIONS - Topics that were discussed but need follow-up
  3) DECISIONS MADE - Key decisions that need progress updates
  4) BLOCKERS MENTIONED - Issues that were blocking progress
  5) FOLLOW-UP TOPICS - Things explicitly mentioned for next meeting
  6) GROWTH AREAS - For 1on1s, any development areas discussed
  7) STRATEGIC INITIATIVES - Any longer-term projects or goals
  Format each category clearly for easy extraction."
- files: ["/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/[PREVIOUS_MEETING_PATH]", "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Inbox/Meetings/MEETING_FILE.json"]
```

### Step 3: Create Prefilled Meeting Note - `@chat`
**For IPMedia 1on1s:**
```
# CRITICAL: Always work from root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

Use mcp__zen__chat with:
- model: "gemini-2.5-pro"
- prompt: "Create a prefilled 1on1 meeting note using the checklist template. CRITICAL:
  1) Use EXACT template structure from 1on1 Template.md
  2) In 'Follow-ups from Last 1on1' section, replace placeholder items with ACTUAL items from grok-4 analysis:
     - Unchecked action items become checklist items
     - Unresolved discussions become follow-up items
     - Growth areas discussed become check-in items
  3) Keep other checklist sections with helpful prompts
  4) Add carryover action items to Action Items section
  5) Use proper YAML formatting (quotes for time, wikilinks)
  6) Previous meeting link at bottom
  Save to the correct person's Meetings folder."
- files: [
    "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Templates/1on1 Template.md",
    "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Inbox/Meetings/MEETING_FILE.json",
    "[GROK4_ANALYSIS_RESULTS]"
  ]

Save to: Business/People/IPMedia/[PERSON]/Meetings/YYYY-MM-DD 1on1.md
```

**For CO Company Meetings:**
```
Use mcp__zen__chat with:
- model: "gemini-2.5-pro"
- prompt: "Create a prefilled CO company meeting note using checklist template. CRITICAL:
  1) Use EXACT template structure from CO-Company-Meeting-Template.md (or DT-Company-Meeting-Template.md for DT)
  2) In 'Follow-ups from Last Meeting' section, replace placeholder items with ACTUAL items from grok-4 analysis:
     - Unchecked action items become checklist items
     - Unresolved business discussions become follow-up items
     - Strategic initiatives become progress check items
     - Blockers mentioned become items to revisit
  3) Company must be just the code (EX/MT/DT/PD/TP) not CO/EX
  4) Leader wikilinks must use full path: [[Business/People/CO/[COMPANY]/[Name]]]
  5) businessImpact: use Medium if unknown (no quotes)
  6) Tags: use lowercase, hyphenated format
  7) Add carryover action items to Action Items section
  8) Keep metrics table empty for filling during meeting
  USE TEMPLATES and customize based on grok-4 analysis."
- files: [
    "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Templates/CO-Company-Meeting-Template.md",
    "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Inbox/Meetings/MEETING_FILE.json",
    "[GROK4_ANALYSIS_RESULTS]"
  ]

Save to: Business/People/CO/[COMPANY]/[LEADER]/Company-Meetings/YYYY-MM-DD [Company] Meeting.md
```

**For Welcome Meetings (New Person):**
```
# Create person folder structure first
mkdir -p Business/People/IPMedia/[PERSON_NAME]/Meetings
mkdir -p Business/People/IPMedia/[PERSON_NAME]/Documents
mkdir -p Business/People/IPMedia/[PERSON_NAME]/attachments

Use mcp__zen__chat with:
- model: "o3"
- prompt: "Create new person profile and welcome meeting note. Extract person name from 'Welcome by Jeff > [Name]'. Create: 1) Person profile using Person Template, 2) Welcome meeting note in their Meetings folder. Initialize with basic info. USE TEMPLATES from Templates/ folder - copy template and customize for this person and meeting."
- files: [
    "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Templates/Person-Business-Template.md",
    "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Templates/Meeting Template.md",
    "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Inbox/Meetings/MEETING_FILE.json"
  ]
```

### Step 4: Mark Previous Action Items as Moved - `@chat`
**Only if action items were carried over:**
```
# CRITICAL: Always work from root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

# Use Python utility to mark items as moved
python3 Tests/action_item_utils.py --mark-moved --file "[PREVIOUS_MEETING_PATH]" --new-date "[NEW_MEETING_DATE]"

Use mcp__zen__chat with:
- model: "grok-4"
- prompt: "Verify action items were properly marked as moved in the previous meeting file. Check for: 1) Items changed from - [ ] to - [x] with strikethrough, 2) → Moved to [[YYYY-MM-DD]] notation added, 3) File saved correctly."
- files: ["/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/[PREVIOUS_MEETING_PATH]"]
```

### Step 5: Final Cleanup & Quality Check - `@chat`
```
# CRITICAL: Always work from root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

Use mcp__zen__chat with:
- model: "o3"
- prompt: "FINAL CHECK: Verify meeting note was created correctly: 1) In correct folder, 2) Action items carried over, 3) Template filled properly, 4) Wikilinks work. If all good, respond 'APPROVED - DELETE JSON'. If issues, specify fixes needed."
- files: ["/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/[NEW_MEETING_PATH]"]

If APPROVED, delete JSON:
rm "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Inbox/Meetings/[JSON_FILE]"

# CRITICAL: Return to root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"
```

### Rolling Queue Management
**CONCURRENT PROCESSING PATTERN:**
```
INITIAL: Start 5 Tasks (meetings 1-5)
Task 1 completes → Start Task 6 (meeting 6)
Task 2 completes → Start Task 7 (meeting 7)  
Task 3 completes → Start Task 8 (meeting 8)
Task 4 completes → Start Task 9 (meeting 9)
Task 5 completes → Start Task 10 (meeting 10)
Continue until all meetings processed
```

**STREAMLINED TASK TEMPLATE:**
```
Task description="Process meeting X" prompt="
CRITICAL: Always work from root directory first!
cd '/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T'

CRITICAL: Use zen-mcp-server tools properly!

1. Use mcp__zen__analyze for meeting type check
   IF SKIP → Delete JSON and end Task
   
2. For 1on1/CO meetings:
   - Find previous meeting with Python utility
   - Use mcp__zen__chat with grok-4 for DEEP ANALYSIS:
     * Extract unchecked action items
     * Find unresolved discussions
     * Identify follow-up topics
     * Note blockers and decisions
   
3. Use mcp__zen__chat with gemini-2.5-pro to create prefilled meeting note
   - Use checklist template format (1on1 vs CO)
   - Populate 'Follow-ups from Last Meeting' with grok-4 analysis
   - Include carryover action items
   - Save to correct folder
   
4. If action items carried over:
   - Mark as moved in previous meeting
   
5. Use mcp__zen__chat for final quality check
   - Verify checklist items are populated
   - Delete JSON if approved

TOTAL: 5 steps max

CRITICAL: Return to root after completion!
cd '/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T'
"
```

---

## 🚨 CRITICAL RULES
1. **ROLLING QUEUE: 5 concurrent, add new as each finishes**
2. **MEETING TYPE FILTER** - Skip unwanted meeting patterns immediately
3. **ACTION ITEM CARRYOVER** - Central feature of this workflow
4. **CORRECT FOLDER STRUCTURE** - IPMedia vs CO companies
5. **USE TEMPLATES** - IPMedia-1on1 vs CO-Company templates
6. **WEEK-BASED PROCESSING** - Current week Mon-Thu, Next week Fri-Sun
7. **NEVER STOP UNTIL COMPLETE** - Continue until inbox is empty

## 🎯 LINT-COMPLIANT YAML FORMATTING
**CRITICAL for passing Obsidian lint tests:**
```yaml
---
title: 2025-08-01 DT Company Meeting  # No quotes needed
type: meeting                          # Simple values don't need quotes
date: 2025-08-01                      # Date format without quotes
time: "10:15"                         # Time needs quotes (contains colon)
company: DT                           # Just the code, not CO/DT
meetingType: Company Meeting          # Multi-word values without special chars don't need quotes
attendees:
  - "[[Jeff Hamersly]]"              # Wikilinks need quotes
  - "[[Danniboy Mejia]]"             # Full names in wikilinks
businessImpact: Medium                # Enum values without quotes
tags:
  - co-company-meeting               # Lowercase, hyphenated
  - dt                              # Company tag lowercase
  - meeting                          # Standard tag
---
```

## 📋 Meeting Type Quick Reference

### Process These:
- **1on1s**: "1on1 Marcus Jeff", "1on1 Jeff Juliana", etc.
- **CO TP**: "Weekly Meeting TP", "Weekly TP" 
- **CO MT**: "MassTraffic Weekly"
- **CO EX**: "Weekly Meeting Excelsior", "Excelsior"
- **CO DT**: "Jeff and DBoy", "DBoy" → Use DT-Company-Meeting-Template.md
- **CO PD**: "PD - Best Meeting Ever"
- **Welcome**: "Welcome by Jeff > [Name]" → Create new person

### Skip These:
- Ops Team, Headquarters, Traffic HQ
- MPalpite Weekly, MP Product Team
- Daily, Standup, Backlog Review
- Team meetings, Group meetings
- Lunch meetings, Social events
- SEO Weekly, Press Meeting
- HR meetings, Recruitment

## 🔄 CONTINUOUS PROCESSING MANDATE

**CRITICAL: DO NOT STOP AFTER ANY BATCH - CONTINUE UNTIL COMPLETE!**

After each batch of 5 tasks completes:
1. **IMMEDIATELY** check remaining JSON count using LS tool
2. **IF COUNT > 0** → Launch next 5 concurrent Tasks immediately
3. **ONLY STOP** when count = 0 (inbox completely empty)
4. **UPDATE TODO** with current progress but DO NOT END

**WORKFLOW: Prefill week → List JSONs → Start 5 Tasks → Keep 5 running → Complete when empty**
**SUCCESS: LS tool returns empty result for Inbox/Meetings AND all Tasks completed**