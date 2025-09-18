# Obsidian Fix All Linting Issues Workflow

🚀 AUTONOMOUS LINTING FIX - CONTINUOUS ASYNC PROCESSING
**CRITICAL: Fix all linting issues in Obsidian vault using ROLLING QUEUE (MAX 10 concurrent).**
**EACH Task uses MCP Grok4 commands to SEND files for analysis and fixes.**
**START 10 → FINISH 1 → START NEXT → Keep 10 running until all done!**

### ⚠️ CONTINUOUS PROCESSING MANDATE
**DO NOT STOP AFTER ANY BATCH COMPLETION!**
- After each 10-task batch completes → **IMMEDIATELY** launch next 10 tasks
- Continue this pattern until all linting issues are fixed
- Only stop when issue count approaches zero
- Update progress but never end until 100% complete

## ⚠️ CLAUDE'S ROLE: COORDINATOR ONLY
**CLAUDE MUST NOT FIX LINTING ISSUES DIRECTLY.**

## 🛠️ Tools: `mcp__zen__chat` with `grok-4` | `Task` for concurrency

---

## 📋 Streamlined Workflow (Per File)

### Step 0: Initialize and Get File List
**CRITICAL: Always start from root directory**
```bash
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

# Run linter to get current issue count and file list
python3 claude-obsidian/scripts/obsidian_smart_linter.py . --claude-mode 2>&1 | jq -r '.issues[].file' | sort | uniq > /tmp/files_with_issues.txt

# Check total files needing fixes
wc -l /tmp/files_with_issues.txt
```

### Step 1: Rolling Queue Processing Setup
**ROLLING QUEUE APPROACH:**
1. List all files with linting issues
2. Start 10 concurrent Task subtasks for first 10 files
3. As each Task completes, start next file Task
4. Keep 10 Tasks running until all files processed
5. Each Task uses mcp__zen__chat with grok-4 to fix files

**EXAMPLE ROLLING QUEUE SETUP:**
```bash
# CRITICAL: Always start from root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

# Start first 10 concurrent Tasks:
Task description="Fix linting file 1" prompt="[STREAMLINED LINTING FIX for file 1]"
Task description="Fix linting file 2" prompt="[STREAMLINED LINTING FIX for file 2]"  
Task description="Fix linting file 3" prompt="[STREAMLINED LINTING FIX for file 3]"
Task description="Fix linting file 4" prompt="[STREAMLINED LINTING FIX for file 4]"
Task description="Fix linting file 5" prompt="[STREAMLINED LINTING FIX for file 5]"
Task description="Fix linting file 6" prompt="[STREAMLINED LINTING FIX for file 6]"
Task description="Fix linting file 7" prompt="[STREAMLINED LINTING FIX for file 7]"
Task description="Fix linting file 8" prompt="[STREAMLINED LINTING FIX for file 8]"
Task description="Fix linting file 9" prompt="[STREAMLINED LINTING FIX for file 9]"
Task description="Fix linting file 10" prompt="[STREAMLINED LINTING FIX for file 10]"

# As Task 1 completes, start Task 11
# As Task 2 completes, start Task 12
# Keep 10 running until all files processed
```

### STREAMLINED TASK WORKFLOW (Per File):

### Linting Fix Process - `mcp__zen__chat`
```
Use mcp__zen__chat with:
- model: "grok-4"
- files: ["/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/[FILE_PATH]"]
- prompt: "Fix all linting issues in this file. This is part of an Obsidian vault for business operations. Common issues include:

1. **Broken wikilinks** - Fix [[broken/links]] by either:
   - Creating missing target files
   - Updating links to point to existing files
   - Converting to proper markdown links if external

2. **Missing frontmatter** - Add YAML frontmatter with:
   - title: Descriptive title
   - tags: [relevant, tags]
   - created: YYYY-MM-DD

3. **Other linting issues** - Fix:
   - Inconsistent formatting
   - Missing headings
   - Broken lists or checkboxes
   - Code block issues

Analyze the file, identify all issues, and provide the complete fixed file content. Be thorough but conservative - don't add unnecessary content."
```

### Progress Tracking
After each batch of 10, check progress:
```bash
# CRITICAL: Always work from root directory
cd "/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T"

# Check current linting status
python3 claude-obsidian/scripts/obsidian_smart_linter.py . --claude-mode 2>&1 | jq -r '"\(.total_files) files, \(.total_issues) issues (\(.issues_by_severity.error) errors, \(.issues_by_severity.warn) warnings, \(.issues_by_severity.info) info)"'

# Get next batch of files if issues remain
python3 claude-obsidian/scripts/obsidian_smart_linter.py . --claude-mode 2>&1 | jq -r '.issues[].file' | sort | uniq | head -10
```

### Rolling Queue Management
**CONCURRENT PROCESSING PATTERN:**
```
INITIAL: Start 10 Tasks (files 1-10)
Task 1 completes → Start Task 11 (file 11)
Task 2 completes → Start Task 12 (file 12)  
Task 3 completes → Start Task 13 (file 13)
Continue until all files processed
```

**STREAMLINED TASK TEMPLATE:**
```
Task description="Fix linting issues in [FILENAME]" prompt="
CRITICAL: Fix all linting issues in the specified file!

Use mcp__zen__chat with:
- model: 'grok-4' 
- files: ['/Users/t/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/[FULL_FILE_PATH]']
- prompt: 'Fix all linting issues in this Obsidian vault file. Add missing frontmatter, fix broken wikilinks, and resolve formatting issues. Provide the complete corrected file content.'

Apply the fixes provided by Grok4 to the actual file.
"
```

---

## 🚨 CRITICAL RULES
1. **ROLLING QUEUE: 10 concurrent, add new as each finishes**
2. **USE GROK-4** - Always use grok-4 model for analysis
3. **APPLY FIXES** - Actually implement the recommended changes
4. **TRACK PROGRESS** - Monitor linting issue count reduction
5. **CLAUDE NEVER FIXES DIRECTLY** - Always use mcp__zen__chat
6. **CONTINUOUS PROCESSING** - Don't stop until all issues resolved
7. **ROOT DIRECTORY** - Always work from vault root
8. **NEVER SKIP FILES** - Process every file with issues

## 🔄 CONTINUOUS PROCESSING MANDATE

**CRITICAL: DO NOT STOP AFTER ANY BATCH - CONTINUE UNTIL COMPLETE!**

After each batch of 10 tasks completes:
1. **IMMEDIATELY** check remaining issue count
2. **IF ISSUES > 0** → Launch next 10 concurrent Tasks immediately
3. **ONLY STOP** when issues approach zero (vault fully linted)
4. **UPDATE PROGRESS** but DO NOT END until complete

**AUTOMATION PATTERN:**
```
BATCH 1: Launch 10 → Wait for completion → Check remaining issues
BATCH 2: Launch 10 → Wait for completion → Check remaining issues  
BATCH 3: Launch 10 → Wait for completion → Check remaining issues
...continue until issue count ≈ 0
```

**SUCCESS: Linter shows minimal issues (<100) AND all critical wikilinks fixed**

## 🔧 Expected Results
- **Fix ~4,100+ linting issues** across 1,147+ files
- **Add missing frontmatter** to hundreds of files
- **Fix broken wikilinks** throughout the vault
- **Create missing index files** as needed
- **Standardize formatting** across all files
- **Maintain vault integrity** and navigation

## 📊 Progress Tracking
- **Start**: ~4,100 issues across 1,524 files
- **Target**: <100 issues (primarily minor formatting)
- **Files processed**: Track via todo system
- **Batch size**: 10 files per batch
- **Estimated batches**: ~115 batches total

**WORKFLOW: CD to root → Get file list → Start 10 Tasks → As each finishes, start next → Keep 10 running → **CONTINUE LAUNCHING NEW BATCHES** → Complete only when fully linted**