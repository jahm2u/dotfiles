# People & Meetings Organization Workflow

## 🎯 INTERACTIVE OPERATION - ONE PERSON AT A TIME
**CRITICAL: Reorganize all people in the vault ONE BY ONE with user confirmation.**
**EACH person processed individually with user input at decision points.**
**ASK → ANALYZE → CONFIRM → PROCEED → NEXT PERSON**

### ⚠️ INTERACTIVE PROCESSING MANDATE
**STOP AND ASK USER FOR CONFIRMATION AT KEY DECISION POINTS!**
- After each person analysis → **ASK USER** for confirmation
- Before any major changes → **WAIT FOR USER APPROVAL**
- Continue only after user confirms each step
- Ask specific questions about person status, company, role, etc.

## ⚠️ CLAUDE'S ROLE: ANALYZER & QUESTIONER
**CLAUDE ANALYZES PEOPLE AND ASKS SPECIFIC QUESTIONS FOR USER CONFIRMATION.**

## 🛠️ Tools: `mcp__zen__analyze` | `mcp__zen__chat` | `Task` for concurrency

---

## 📋 Enhanced Workflow (10 Steps Per Person with Async Meeting Processing)

### Step 0: Setup Individual Person Processing
**INDIVIDUAL PERSON APPROACH:**
1. List all people folders in `Business/People/` and `Personal/Family/`
2. Process ONE person at a time with user interaction
3. Ask user specific questions about each person
4. Wait for user confirmation before proceeding
5. Move to next person only after user approval

**EXAMPLE INDIVIDUAL SETUP:**
```bash
# CRITICAL: Always start from and return to root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

# First, check what people exist using LS tool
LS path:"/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Business/People"
LS path:"/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Personal/Family"

# Process one person at a time:
# 1. Analyze Person 1 → Ask user questions → Wait for answers → Process
# 2. Analyze Person 2 → Ask user questions → Wait for answers → Process
# 3. Continue until all people processed

# CRITICAL: Always return to root after each operation
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"
```

### STREAMLINED TASK WORKFLOW (Per Person):

### Step 1: Person Analysis & User Questions - `@analyze`
```
# CRITICAL: Always work from root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

Use mcp__zen__analyze with:
- model: "o3"
- relevant_files: ["/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Business/People/COMPANY/PERSON/PERSON.md", "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/claude-obsidian/docs/People-Directory.md"]
- step: "PERSON ANALYSIS: Using the People-Directory.md as reference, analyze this person and prepare specific questions for the user. Provide: 1) Current person profile summary, 2) Potential duplicate detection from People-Directory.md, 3) Current company assignment, 4) Meeting history summary, 5) Role/position analysis. Then ask user specific questions like: 'Does [PERSON] still work with you?', 'Is [PERSON] part of [COMPANY]?', 'Should [PERSON] be merged with [OTHER_PERSON]?', 'Is [PERSON] active or inactive?', 'What is [PERSON]'s current role?'"
- step_number: 1
- total_steps: 1
- next_step_required: false
```

### Step 2: User Confirmation & Decision - **STOP AND ASK USER**
**CRITICAL: STOP HERE AND ASK USER SPECIFIC QUESTIONS:**
- "Does [PERSON] still work with you? (Yes/No)"
- "Which company is [PERSON] part of? (IPMedia/Windsor-Online/Media-Marketing-Solutions/BK-Solutions/Personal)"
- "Is [PERSON] a duplicate of someone else? If yes, who?"
- "What is [PERSON]'s current role/position?"
- "Should [PERSON] be marked as active or inactive?"
- "Any other changes needed for [PERSON]?"

**WAIT FOR USER RESPONSES BEFORE PROCEEDING TO STEP 3**

### Step 3: Meeting Content Analysis (Based on User Input) - `@chat`
```
# CRITICAL: Always work from root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

Use mcp__zen__chat with:
- model: "gemini-2.5-pro"
- prompt: "MEETING ANALYSIS: Based on user input about [PERSON] and referencing People-Directory.md for context, analyze: 1) Read ALL meeting files for this person, 2) Identify duplicate meetings or meetings that should be merged, 3) Extract key information about this person's role, skills, background, and relationship with Jeff, 4) Summarize their contribution to the business, 5) Identify any meetings in wrong locations, 6) List key insights about this person from all meetings, 7) Check for connections to other people in People-Directory.md, 8) Prepare summary for user confirmation."
- files: ["/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Business/People/COMPANY/PERSON/Meetings/", "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/claude-obsidian/docs/People-Directory.md"]
```

### Step 4: Present Analysis & Ask for Final Confirmation - **STOP AND ASK USER**
**CRITICAL: STOP HERE AND PRESENT ANALYSIS TO USER:**
- Show summary of meeting analysis
- Present proposed changes to person profile
- Ask: "Does this analysis look correct?"
- Ask: "Should I proceed with these changes?"
- Ask: "Any additional modifications needed?"

**WAIT FOR USER APPROVAL BEFORE PROCEEDING TO STEP 5**

### Step 5: Person Profile Update & Enhancement (After User Approval) - `@chat`
```
# CRITICAL: Always work from root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

Use mcp__zen__chat with:
- model: "o3"
- prompt: "PERSON PROFILE UPDATE: Using user-confirmed information, meeting insights, and People-Directory.md for context, update the person's profile with: 1) Enhanced personal information (role, skills, background), 2) Updated meeting cadence and communication patterns, 3) Key contributions and value to the business, 4) Current projects and collaborations, 5) Remove placeholder text and add real content from meetings, 6) Ensure proper wikilinks to all their meetings, 7) Add 'Recent Interactions' section with chronological meeting summaries, 8) Update status as active/inactive per user input, 9) Update People-Directory.md if person's company or status changes."
- files: ["/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Business/People/COMPANY/PERSON/PERSON.md", "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Business/People/COMPANY/PERSON/Meetings/", "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/claude-obsidian/docs/People-Directory.md"]
```

### Step 6: Structural Reorganization & File Moves (If Needed) - `@chat`
```
# CRITICAL: Always work from root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

Use mcp__zen__chat with:
- model: "o3"
- prompt: "STRUCTURAL REORGANIZATION: Based on user input, if person needs to be moved to different company or merged: 1) Create proper folder structure in correct company, 2) Move all meetings to new location, 3) Update all wikilinks in meetings to point to new location, 4) Update person profile with correct company context, 5) Remove old folder structure, 6) Update any references to old location throughout the vault, 7) Update People-Directory.md to reflect the new location/company, 8) If merging with another person, consolidate all meetings and update references in People-Directory.md."
- files: ["/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Business/People/COMPANY/PERSON/", "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/claude-obsidian/docs/People-Directory.md"]
```

### Step 7: Async Meeting Review & Analysis (After Person Move) - **CONCURRENT TASKS**
**CRITICAL: AFTER PERSON IS MOVED, PROCESS ALL THEIR MEETINGS ASYNCHRONOUSLY**
**Launch 5 concurrent Task subtasks to review meetings - DO NOT READ MEETINGS DIRECTLY**

**ASYNC MEETING PROCESSING SETUP:**
```bash
# CRITICAL: Always work from root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

# First, list all meeting files for this person using LS tool
LS path:"/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Business/People/COMPANY/PERSON/Meetings"

# Launch 5 concurrent Tasks to process meetings:
Task description="Meeting analysis 1" prompt="[MEETING ANALYSIS WORKFLOW]"
Task description="Meeting analysis 2" prompt="[MEETING ANALYSIS WORKFLOW]"
Task description="Meeting analysis 3" prompt="[MEETING ANALYSIS WORKFLOW]"
Task description="Meeting analysis 4" prompt="[MEETING ANALYSIS WORKFLOW]"
Task description="Meeting analysis 5" prompt="[MEETING ANALYSIS WORKFLOW]"

# As each Task completes, start next meeting Task
# Keep 5 Tasks running until all meetings processed
```

**MEETING ANALYSIS TASK WORKFLOW (Per Meeting):**
```
Task Meeting Analysis Workflow:

CRITICAL: Always work from root directory first!
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

CRITICAL: Use MCP commands to SEND meeting files - never read directly!

1. Use mcp__zen__chat with:
   - model: "gemini-2.5-pro"
   - prompt: "MEETING ANALYSIS: Analyze this meeting note in detail. Extract: 1) Person's role and responsibilities mentioned, 2) Skills and expertise demonstrated, 3) Key contributions to projects, 4) Background information revealed, 5) Relationship dynamics with Jeff, 6) Technical knowledge displayed, 7) Decision-making authority, 8) Current projects and involvement, 9) Meeting frequency and communication patterns, 10) Any personal information relevant to business context. Prepare insights for person profile enhancement."
   - files: ["/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Business/People/COMPANY/PERSON/Meetings/MEETING_FILE.md", "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/claude-obsidian/docs/People-Directory.md"]

2. Store analysis results for consolidation with other meetings

CRITICAL: Return to root after completion!
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"
```

### Step 8: Consolidate Meeting Insights & Update Person Profile - `@chat`
```
# CRITICAL: Always work from root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

Use mcp__zen__chat with:
- model: "gemini-2.5-pro"
- prompt: "CONSOLIDATE MEETING INSIGHTS: Using all meeting analysis results from the 5 concurrent tasks, consolidate insights and update the person's profile with: 1) Enhanced role and responsibilities based on meetings, 2) Updated skills and expertise demonstrated, 3) Key contributions and value to the business, 4) Current projects and collaborations, 5) Communication patterns and meeting frequency, 6) Background information and experience, 7) Decision-making authority and influence, 8) Technical knowledge and capabilities, 9) Relationship dynamics and working style, 10) Remove placeholder text and add real content from meetings, 11) Ensure proper wikilinks to all meetings, 12) Add 'Recent Interactions' chronological summary, 13) Update status and company assignment, 14) Update People-Directory.md with any changes."
- files: ["/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Business/People/COMPANY/PERSON/PERSON.md", "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/claude-obsidian/docs/People-Directory.md"]
```

### Step 9: Challenge & Validate Changes - `@chat`
```
# CRITICAL: Always work from root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

Use mcp__zen__chat with:
- model: "grok-4"
- prompt: "CHALLENGE GEMINI CHANGES: Review the person profile updates made by Gemini and challenge them critically. Analyze: 1) Are the role/responsibility updates accurate based on meeting evidence?, 2) Are the skills and expertise claims supported by actual meeting content?, 3) Are the project contributions properly attributed?, 4) Is the background information factual and relevant?, 5) Are the relationship dynamics accurately represented?, 6) Is the technical knowledge assessment correct?, 7) Are there any exaggerations or unsupported claims?, 8) Are there missing insights that should be included?, 9) Are the wikilinks and references correct?, 10) Does the updated profile accurately reflect this person's current status and value?. Provide specific feedback on what should be changed, what should be removed, and what additional information should be added. If changes are needed, provide the corrected version."
- files: ["/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Business/People/COMPANY/PERSON/PERSON.md", "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/Business/People/COMPANY/PERSON/Meetings/", "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/claude-obsidian/docs/People-Directory.md"]
```

### Step 10: Final Confirmation & Next Person - **STOP AND ASK USER**
**CRITICAL: STOP HERE AND CONFIRM WITH USER:**
- Show completed changes for this person
- Ask: "Are you satisfied with the organization of [PERSON]?"
- Ask: "Should I proceed to the next person?"
- Ask: "Any final adjustments needed?"

**WAIT FOR USER CONFIRMATION BEFORE MOVING TO NEXT PERSON**

### Individual Person Processing Management
**SEQUENTIAL PROCESSING PATTERN:**
```
PROCESS: Person 1 → Analyze → Ask User → Wait for Response → Process → Confirm → Next
PROCESS: Person 2 → Analyze → Ask User → Wait for Response → Process → Confirm → Next
PROCESS: Person 3 → Analyze → Ask User → Wait for Response → Process → Confirm → Next
Continue until all people processed
```

**INDIVIDUAL PERSON TEMPLATE:**
```
Individual Person Processing Workflow:

CRITICAL: Always work from root directory first!
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

CRITICAL: Use MCP commands to SEND files - never read directly!
CRITICAL: Always include People-Directory.md in relevant_files for context and reference!

1. Use mcp__zen__analyze - Person analysis & prepare user questions
2. **STOP** - Ask user specific questions about person (status, company, role, etc.)
3. Use mcp__zen__chat model:gemini-2.5-pro - Meeting content analysis based on user input
4. **STOP** - Present analysis to user and ask for confirmation
5. Use mcp__zen__chat model:o3 - Person profile update & enhancement (after user approval)
6. Use mcp__zen__chat model:o3 - Structural reorganization & file moves (if needed)
7. **ASYNC TASKS** - Launch 5 concurrent meeting analysis tasks (gemini-2.5-pro)
8. Use mcp__zen__chat model:gemini-2.5-pro - Consolidate meeting insights & update person profile
9. Use mcp__zen__chat model:grok-4 - Challenge & validate gemini changes
10. **STOP** - Show completed changes and ask for final confirmation before next person

TOTAL: 10 steps per person (with 3 user interaction stops + 5 async meeting tasks)

CRITICAL: Return to root after completion!
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"
```

---

## 🚨 CRITICAL RULES
1. **INDIVIDUAL PROCESSING: One person at a time with user interaction**
2. **ELIMINATE CROSS-COMPANY** - Assign each person to ONE primary company
3. **MERGE DUPLICATES** - Consolidate duplicate people and meetings (with user confirmation)
4. **ENHANCE PROFILES** - Use meeting content to enrich person profiles
5. **PROPER COMPANY ASSIGNMENT** - Use company docs and user input to determine correct assignment
6. **STRUCTURAL CLEANUP** - Ensure proper folder hierarchy and wikilinks
7. **USER CONFIRMATION** - Stop and ask user questions at key decision points
8. **SEQUENTIAL PROCESSING** - Process one person completely before moving to next
9. **ASYNC MEETING PROCESSING** - After person move, launch 5 concurrent tasks to analyze meetings
10. **GEMINI CONSOLIDATION** - Use gemini-2.5-pro to consolidate meeting insights and update profiles
11. **GROK VALIDATION** - Use grok-4 to challenge and validate gemini changes

## 🔄 INTERACTIVE PROCESSING MANDATE

**CRITICAL: STOP AND ASK USER AT EACH DECISION POINT!**

For each person:
1. **ANALYZE** person and prepare questions
2. **STOP** - Ask user about person status, company, role, etc.
3. **WAIT** for user responses
4. **PROCESS** based on user input
5. **STOP** - Present analysis and ask for confirmation
6. **WAIT** for user approval
7. **EXECUTE** changes with user oversight
8. **STOP** - Confirm completion and ask to proceed to next person

**SEQUENTIAL PATTERN:**
```
Person 1: Analyze → Ask User → Wait → Process → Confirm → Next
Person 2: Analyze → Ask User → Wait → Process → Confirm → Next
Person 3: Analyze → Ask User → Wait → Process → Confirm → Next
...continue until all people processed with user guidance
```

**WORKFLOW: CD to root → List All People → Process Person 1 → Ask User → Wait → Process → Confirm → Next Person → Repeat until complete**

## 🔧 Interactive Processing Benefits
- **User-guided decisions** ensure accurate person assignments
- **Company-focused assignment** eliminates cross-company confusion
- **Duplicate detection with user confirmation** reduces vault clutter safely
- **Meeting-based profile enhancement** creates richer person profiles
- **Interactive workflow** prevents automated mistakes
- **Structural cleanup with oversight** improves vault navigation
- **User confirmation at each step** ensures quality outcomes
- **Async meeting processing** enables efficient analysis of large meeting histories
- **Gemini consolidation** provides comprehensive meeting insights
- **Grok validation** ensures accuracy and challenges assumptions

## 📋 Expected Outcomes
- **Unified person profiles** with rich content from meetings
- **Proper company assignments** (IPMedia/Windsor-Online/Media-Marketing-Solutions/BK-Solutions)
- **Eliminated duplicates** and consolidated meetings
- **Enhanced wikilink structure** for better navigation
- **Removed "Cross-Company" references** from all documentation
- **Improved folder hierarchy** following person-centric structure
- **Quality person profiles** with real content instead of placeholders
- **Detailed meeting analysis** with 5 concurrent tasks per person
- **Consolidated meeting insights** from gemini-2.5-pro analysis
- **Validated profile updates** challenged by grok-4 for accuracy

## 🎯 Success Criteria
- All people assigned to correct company folders (with user confirmation)
- No duplicate people or meetings (merged with user approval)
- All person profiles enhanced with meeting content and user input
- All wikilinks functional and properly structured
- "Cross-Company" concept completely removed
- Proper folder hierarchy maintained (PersonName/, PersonName.md, Meetings/, Documents/)
- User satisfaction with each person's organization
- Clear understanding of each person's current status and role
- All meetings analyzed by 5 concurrent tasks per person
- Meeting insights consolidated and validated by gemini-2.5-pro
- Profile updates challenged and validated by grok-4

## 📝 Common User Questions to Expect
- "Does [PERSON] still work with you?"
- "Which company is [PERSON] part of?"
- "What is [PERSON]'s current role?"
- "Is [PERSON] active or inactive?"
- "Should [PERSON] be merged with [OTHER_PERSON]?"
- "Is this analysis correct?"
- "Should I proceed with these changes?"
- "Are you satisfied with the organization of [PERSON]?"
- "Should I move to the next person?"