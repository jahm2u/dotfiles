# dotfiles - Technical Specification: Obsidian Meeting Preparation Integration

**Author:** Jeff
**Date:** 2025-11-02
**Project Level:** 1
**Project Type:** enhancement
**Development Context:** brownfield

---

## Source Tree Structure

```
config/sketchybar/
├── plugins/
│   └── meeting.sh                     # MODIFY: Add icon click handler for meeting prep
├── helpers/
│   ├── meeting-prep.sh               # NEW: Main orchestration script
│   ├── classify-meeting.py           # NEW: Meeting type classification
│   ├── find-person-folder.sh         # NEW: Locate person in vault structure
│   ├── analyze-meeting-history.py    # NEW: Extract patterns from last 5 meetings
│   └── generate-meeting-note.py      # NEW: AI-powered note generation

.env                                   # MODIFY: Add Obsidian vault path and OpenAI key
├── OBSIDIAN_VAULT_PATH               # NEW: Path to vault root
├── OPENAI_API_KEY                    # NEW: For AI meeting generation
└── TODOIST_API_TOKEN                 # EXISTING: Keep existing token

# External Dependencies (Obsidian Vault)
/Users/v/Library/Mobile Documents/iCloud~md~obsidian/Documents/U/
├── Business/
│   ├── People/
│   │   ├── IPMedia/                  # READ/WRITE: Person folders for 1-on-1s
│   │   │   └── {PersonName}/
│   │   │       └── Meetings/         # WRITE: Generated meeting notes
│   │   └── CO/                       # READ/WRITE: Company person folders
│   │       └── {Company}/
│   │           └── {PersonName}/
│   └── CO/                           # READ/WRITE: Company-wide meetings
│       └── {Company}/
│           └── Meetings/
└── bmad/
    └── vault-ops/
        ├── config.yaml               # READ: Vault configuration
        └── templates/
            ├── meeting-1on1-template.md      # READ: 1-on-1 template
            ├── meeting-company-template.md   # READ: Company template
            └── meeting-team-template.md      # READ: Team template

~/.cache/sketchybar/
└── last_meeting_prep_result.json     # NEW: Cache last prep result for debugging
```

---

## Technical Approach

### Overview

When a user clicks the **icon** next to a calendar meeting (NOT the label), the system generates a comprehensive, pre-filled Obsidian meeting note by analyzing meeting history and applying AI-powered context generation.

### Workflow Phases

#### Phase 1: Meeting Classification (classify-meeting.py)

**Input:** Calendar event data (title, date, participants)

**Process:**
1. Parse meeting title for patterns:
   - `1on1`, `1-on-1`, `1:1` → IPMedia 1-on-1
   - `weekly tp`, `tp weekly` → TP company meeting
   - `masstraffic weekly` → MT company meeting
   - `bi team dashboard` → BI team meeting
2. Extract participant names (exclude "Jeff Hamersly")
3. Determine company from context (IPMedia, EX, MT, DT, PD, TP)

**Output:** Classification object
```json
{
  "meeting_type": "ipmedia_1on1",
  "company": "IPMedia",
  "participant": "Marcus",
  "confidence": 95
}
```

#### Phase 2: Person Folder Location (find-person-folder.sh)

**Input:** Person name, company

**Process:**
1. Search vault in priority order:
   - `Business/People/IPMedia/{PersonName}/`
   - `Business/People/CO/{Company}/{PersonName}/`
   - `Business/People/Cross-Company/{PersonName}/`
   - `Business/People/Archive/{PersonName}/`
2. Verify folder structure (profile.md, Meetings/, attachments/)

**Output:** Folder paths
```json
{
  "person_folder": "/path/to/Business/People/IPMedia/Marcus",
  "meetings_folder": "/path/to/.../Meetings",
  "profile": "/path/to/.../Marcus.md"
}
```

**Error Handling:** If person not found → exit with error, suggest onboarding workflow

#### Phase 3: Find Last Meeting (find-person-folder.sh)

**Input:** Meetings folder path

**Process:**
1. List all markdown files in Meetings folder
2. Filter for files starting with `YYYY-MM-DD` pattern
3. Sort by date descending
4. Return most recent file

**Output:** Last meeting file path or None

**Note:** Previous meetings are assumed to be already filled (via separate transcript workflow or manual entry). This workflow just reads them as-is.

#### Phase 4: Meeting Continuity Analysis (analyze-meeting-history.py)

**Input:** Last 5 meeting files

**Process:**
1. Read all 5 meeting notes
2. AI analysis (OpenAI GPT-4) to extract:
   - **Open Action Items:** Track status across meetings
     - Newly created vs carried forward
     - Overdue items (days open)
     - Blocked items
   - **Recurring Topics:** Patterns across meetings
   - **Unresolved Threads:** Questions without answers
   - **Active Blockers:** Current impediments
   - **Meeting Patterns:** Frequency, duration, sentiment
3. Generate suggested agenda prioritized by urgency

**Output:** Continuity analysis
```json
{
  "open_action_items": [
    {
      "description": "Review Q4 roadmap",
      "owner": "Jeff",
      "source_meeting": "2025-11-08",
      "days_open": 7,
      "priority": "high"
    }
  ],
  "active_blockers": [...],
  "recurring_topics": [...],
  "suggested_agenda": {
    "must_discuss": [...],
    "should_discuss": [...],
    "could_discuss": [...]
  }
}
```

#### Phase 5: Meeting Note Generation (generate-meeting-note.py)

**Input:** Template file, meeting context, continuity analysis, last meeting summary

**Process:**
1. Load appropriate template (1on1, company, or team)
2. AI generation (OpenAI GPT-4) to:
   - Replace all template variables (`{{date}}`, `{{participant}}`, etc.)
   - Pre-fill **Meeting Prep** sections:
     - Critical/Urgent Items (overdue actions)
     - Prepared Questions (specific to context)
     - Key Topics to Cover (prioritized agenda)
     - Follow-ups from Last Meeting (action tracking)
     - Context from Last Meeting (summary)
   - Leave **Capture** sections empty (for live notes)
   - Generate wikilinks for person, company, documents
3. Calculate next meeting date based on frequency pattern

**Output:** Complete pre-filled meeting note (markdown)

#### Phase 6: Save and Open (meeting-prep.sh)

**Input:** Generated meeting note content, meeting context

**Process:**
1. Determine save path based on meeting type:
   - 1-on-1: `{person_folder}/Meetings/{date} 1on1.md`
   - Company: `Business/CO/{Company}/Meetings/{date} {Company} Weekly.md`
   - Team: `Business/People/IPMedia/Teams/{Team}/{date} {Team} Meeting.md`
2. Ensure directory exists
3. Write file
4. Cache result for debugging
5. **Open in Obsidian** (via `open obsidian://open?vault=U&file=...`)
6. Reset Sketchybar icon to normal state

**Output:** Success notification with file path

### Loading Indicator Design

**Visual Feedback During Processing:**

While the meeting prep workflow runs (15-45 seconds), the Sketchybar meeting widget icon will animate to show progress:

**Option 1: Icon Animation**
- Cycle through icon states: `󰃭` → `󰃮` → `󰃯` → `󰃭` (repeat)
- Update every 500ms
- Implemented via background loop in meeting-prep.sh

**Option 2: Text Animation (simpler)**
- Show loading text patterns: `...` → `:..` → `.:.` → `..:` (repeat)
- Replace meeting label temporarily
- Restore normal display when complete

**Implementation:** Option 2 (text animation) is simpler and doesn't require icon asset changes.

### Error Handling Strategy

| Error Type | Response |
|------------|----------|
| Person not found | Exit with error, suggest running onboard-person workflow |
| No previous meetings | Skip continuity analysis, use first-meeting template |
| OpenAI API failure | Retry with exponential backoff (max 3 attempts), show error in Sketchybar |
| Template not found | Use default 1on1 template as fallback |
| Obsidian vault not accessible | Exit with error, verify OBSIDIAN_VAULT_PATH in .env |

### Performance Expectations

- **Classification:** <100ms (regex patterns)
- **Person folder search:** <200ms (filesystem lookup)
- **Continuity analysis:** 8-15 seconds (AI analysis of 5 meetings)
- **Note generation:** 5-10 seconds (AI generation with context)
- **File operations:** <500ms (save and open)
- **Total end-to-end:** 15-45 seconds depending on API latency
- **Loading indicator:** Shows animated feedback throughout entire process

---

## Implementation Stack

**Core Technologies:**

- **Python 3.11**: All AI processing and meeting analysis scripts
- **Bash 5.2+**: Orchestration script and Sketchybar plugin integration
- **Sketchybar v2.20+**: Status bar integration and click handlers
- **Obsidian**: Note viewing and editing (opened via URL scheme)

**Python Libraries:**

```requirements.txt
openai==1.12.0              # OpenAI API client for GPT-4
python-dotenv==1.0.0        # .env file loading
pyyaml==6.0.1               # YAML parsing for vault config
```

**External APIs:**

- **OpenAI API (GPT-4o-mini)**
  - Endpoint: `https://api.openai.com/v1/chat/completions`
  - Model: `gpt-4o-mini` (128k context window)
  - Authentication: Bearer token via `OPENAI_API_KEY` in `.env`
  - Rate limits: 10,000 requests/day (tier 1), 500 requests/minute
  - Pricing: $0.15/1M input tokens, $0.60/1M output tokens
  - Expected cost per run: ~$0.005 per meeting prep (input: 20k tokens, output: 3k tokens)

**Filesystem Integration:**

- **Obsidian Vault:** `/Users/v/Library/Mobile Documents/iCloud~md~obsidian/Documents/U`
  - Read: Meeting history, templates, config
  - Write: Generated meeting notes
  - Format: Markdown with YAML frontmatter
- **Cache Directory:** `~/.cache/sketchybar/`
  - Debug cache: `last_meeting_prep_result.json`

**URL Schemes:**

- **Obsidian URI:** `obsidian://open?vault=U&file={encoded_path}`
  - Opens specific file in vault
  - Triggers via `open` command in macOS

**Development Tools:**

- **jq 1.7**: JSON manipulation in bash scripts (optional)
- **Python venv**: Virtual environment for dependency isolation

---

## Technical Details

### Component 1: Icon Click Handler (meeting.sh)

**File:** `config/sketchybar/plugins/meeting.sh`

**Changes Required:**

Add icon click handler that triggers meeting prep script:

```bash
# After existing click_script for label (around line 240)

# Icon click handler - triggers meeting prep
ICON_CLICK_SCRIPT="~/.config/sketchybar/helpers/meeting-prep.sh '\$NAME' '\$SENDER'"

sketchybar --set "$NAME" \
    icon.click_script="$ICON_CLICK_SCRIPT"
```

**Note:** This creates separate behaviors:
- **Label click:** Shows popup with all today's meetings (existing)
- **Icon click:** Prepares next meeting note in Obsidian (new)

### Component 2: Main Orchestration Script (meeting-prep.sh)

**File:** `config/sketchybar/helpers/meeting-prep.sh`

**Purpose:** Coordinates entire meeting prep workflow with loading animation

**Key Functions:**

```bash
#!/usr/bin/env bash

# Load environment
source "${HOME}/.env" || source "${HOME}/dotfiles/.env"

HELPERS_DIR="$HOME/.config/sketchybar/helpers"
CACHE_DIR="$HOME/.cache/sketchybar"
PYTHON_VENV="$HOME/.config/sketchybar/venv"

# Activate Python virtual environment
source "$PYTHON_VENV/bin/activate"

# Start loading animation in background
animate_loading() {
    local NAME=$1
    local patterns=("..." ":.." ".:." "..:")
    local i=0

    while kill -0 $MAIN_PID 2>/dev/null; do
        sketchybar --set "$NAME" label="${patterns[$i]}"
        i=$(( (i + 1) % 4 ))
        sleep 0.5
    done
}

# Main workflow
main() {
    MAIN_PID=$$

    # Start animation
    animate_loading "$NAME" &
    ANIM_PID=$!

    # Get next meeting from cache
    NEXT_MEETING=$(get_next_meeting_from_cache)

    if [[ -z "$NEXT_MEETING" ]]; then
        sketchybar --set "$NAME" label="No meetings found"
        exit 1
    fi

    # Parse meeting data
    TITLE=$(echo "$NEXT_MEETING" | cut -d'|' -f1)
    DATE=$(echo "$NEXT_MEETING" | cut -d'|' -f3)
    PARTICIPANTS=$(echo "$NEXT_MEETING" | cut -d'|' -f5)

    # Step 1: Classify meeting
    CLASSIFICATION=$(python3 "$HELPERS_DIR/classify-meeting.py" \
        --title "$TITLE" \
        --date "$DATE" \
        --participants "$PARTICIPANTS")

    # Step 2: Find person folder
    PERSON=$(echo "$CLASSIFICATION" | jq -r '.participant')
    COMPANY=$(echo "$CLASSIFICATION" | jq -r '.company')

    PERSON_FOLDER=$(bash "$HELPERS_DIR/find-person-folder.sh" \
        --person "$PERSON" \
        --company "$COMPANY")

    if [[ $? -ne 0 ]]; then
        kill $ANIM_PID
        sketchybar --set "$NAME" label="Person not found: $PERSON"
        exit 1
    fi

    # Step 3: Analyze meeting history
    CONTINUITY=$(python3 "$HELPERS_DIR/analyze-meeting-history.py" \
        --person-folder "$PERSON_FOLDER" \
        --classification "$CLASSIFICATION")

    # Step 4: Generate meeting note
    MEETING_NOTE=$(python3 "$HELPERS_DIR/generate-meeting-note.py" \
        --classification "$CLASSIFICATION" \
        --person-folder "$PERSON_FOLDER" \
        --continuity "$CONTINUITY")

    # Stop animation
    kill $ANIM_PID

    # Step 5: Save and open in Obsidian
    NOTE_PATH=$(echo "$MEETING_NOTE" | jq -r '.file_path')

    # Cache result for debugging
    echo "$MEETING_NOTE" > "$CACHE_DIR/last_meeting_prep_result.json"

    # Open in Obsidian
    ENCODED_PATH=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$NOTE_PATH'))")
    open "obsidian://open?vault=U&file=$ENCODED_PATH"

    # Reset widget
    sketchybar --trigger calendar_synced

    exit 0
}

main "$@"
```

### Component 3: Meeting Classifier (classify-meeting.py)

**File:** `config/sketchybar/helpers/classify-meeting.py`

**Purpose:** Determine meeting type and routing based on title/participants

```python
#!/usr/bin/env python3

import argparse
import json
import re

def classify_meeting(title: str, participants: list[str]) -> dict:
    """Classify meeting type based on title and participants."""

    title_lower = title.lower()

    # Remove "Jeff Hamersly" from participants
    other_participants = [p for p in participants if p != "Jeff Hamersly"]

    # IPMedia 1-on-1 patterns
    if any(pattern in title_lower for pattern in ['1on1', '1-on-1', '1:1']):
        if len(other_participants) == 1:
            return {
                'meeting_type': 'ipmedia_1on1',
                'company': 'IPMedia',
                'participant': other_participants[0],
                'confidence': 95
            }

    # Company meeting patterns
    company_patterns = {
        'weekly tp': ('co_tp_meeting', 'TP'),
        'tp weekly': ('co_tp_meeting', 'TP'),
        'masstraffic weekly': ('co_mt_meeting', 'MT'),
        'mt weekly': ('co_mt_meeting', 'MT'),
        'ex weekly': ('co_ex_meeting', 'EX'),
        'dt weekly': ('co_dt_meeting', 'DT'),
        'pd weekly': ('co_pd_meeting', 'PD'),
    }

    for pattern, (meeting_type, company) in company_patterns.items():
        if pattern in title_lower:
            return {
                'meeting_type': meeting_type,
                'company': company,
                'participant': None,
                'confidence': 90
            }

    # Team meeting patterns
    if 'bi team' in title_lower or 'bi dashboard' in title_lower:
        return {
            'meeting_type': 'ipmedia_team_bi',
            'company': 'IPMedia',
            'team': 'BI',
            'confidence': 85
        }

    if 'traffic' in title_lower and 'team' in title_lower:
        return {
            'meeting_type': 'ipmedia_team_traffic',
            'company': 'IPMedia',
            'team': 'Traffic',
            'confidence': 85
        }

    # Unknown
    return {
        'meeting_type': 'unknown',
        'confidence': 0
    }

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--title', required=True)
    parser.add_argument('--date', required=True)
    parser.add_argument('--participants', required=True)
    args = parser.parse_args()

    participants_list = args.participants.split(',')
    result = classify_meeting(args.title, participants_list)

    print(json.dumps(result, indent=2))
```

### Component 4: Person Folder Finder (find-person-folder.sh)

**File:** `config/sketchybar/helpers/find-person-folder.sh`

**Purpose:** Locate person's folder in Obsidian vault structure

```bash
#!/usr/bin/env bash

# Load vault path from .env
source "${HOME}/.env" || source "${HOME}/dotfiles/.env"

VAULT_ROOT="$OBSIDIAN_VAULT_PATH"

find_person_folder() {
    local PERSON=$1
    local COMPANY=$2

    # Search paths in priority order
    local SEARCH_PATHS=(
        "$VAULT_ROOT/Business/People/IPMedia/$PERSON"
        "$VAULT_ROOT/Business/People/CO/$COMPANY/$PERSON"
        "$VAULT_ROOT/Business/People/Cross-Company/$PERSON"
        "$VAULT_ROOT/Business/People/Archive/$PERSON"
    )

    for path in "${SEARCH_PATHS[@]}"; do
        if [[ -d "$path" ]]; then
            # Verify structure
            if [[ -f "$path/$PERSON.md" ]] && [[ -d "$path/Meetings" ]]; then
                echo "$path"
                return 0
            fi
        fi
    done

    # Not found
    echo "ERROR: Person folder not found for: $PERSON" >&2
    return 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --person) PERSON="$2"; shift 2 ;;
        --company) COMPANY="$2"; shift 2 ;;
        *) shift ;;
    esac
done

find_person_folder "$PERSON" "$COMPANY"
```

### Component 5: Meeting History Analyzer (analyze-meeting-history.py)

**File:** `config/sketchybar/helpers/analyze-meeting-history.py`

**Purpose:** AI-powered analysis of last 5 meetings to extract patterns and context

```python
#!/usr/bin/env python3

import argparse
import json
import os
import re
from datetime import datetime
from pathlib import Path
from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()

client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))

def get_last_n_meetings(meetings_folder: str, n: int = 5) -> list[dict]:
    """Get last N meeting files sorted by date."""

    meetings_path = Path(meetings_folder)
    meeting_files = []

    for file in meetings_path.glob('*.md'):
        # Check if filename starts with YYYY-MM-DD
        if re.match(r'^\d{4}-\d{2}-\d{2}', file.name):
            meeting_files.append({
                'file': str(file),
                'date': file.name[:10]
            })

    # Sort by date descending
    meeting_files.sort(key=lambda x: x['date'], reverse=True)

    # Read content of last N
    meetings = []
    for meeting in meeting_files[:n]:
        with open(meeting['file'], 'r') as f:
            meetings.append({
                'date': meeting['date'],
                'content': f.read()
            })

    return meetings

def analyze_continuity(meetings: list[dict], person: str) -> dict:
    """Use AI to analyze meeting history and extract patterns."""

    # Build context from meetings
    meetings_context = "\n\n---\n\n".join([
        f"Meeting Date: {m['date']}\n\n{m['content']}"
        for m in meetings
    ])

    prompt = f"""Analyze this meeting series with {person} and extract comprehensive context for next meeting preparation.

MEETING HISTORY:
{meetings_context}

ANALYSIS REQUIREMENTS:

1. OPEN ACTION ITEMS: Extract all uncompleted action items
   - Track each item across meetings (if mentioned multiple times)
   - Calculate days open (from first mention to today)
   - Identify owner (Jeff or {person})
   - Determine priority based on context

2. RECURRING TOPICS: Identify patterns
   - Topics discussed in multiple meetings
   - Trend (increasing/decreasing attention)

3. ACTIVE BLOCKERS: Current impediments
   - What's blocked
   - Impact level
   - Resolution needs

4. UNRESOLVED THREADS: Questions without answers
   - Topic raised but never resolved
   - Original date raised

5. SUGGESTED AGENDA: Prioritize for next meeting
   - Must discuss (urgent/overdue items)
   - Should discuss (important topics)
   - Could discuss (nice-to-have)

Return JSON with this structure:
{{
  "open_action_items": [
    {{"description": "...", "owner": "Jeff|{person}", "source_meeting": "YYYY-MM-DD", "days_open": N, "priority": "high|medium|low"}}
  ],
  "recurring_topics": [
    {{"topic": "...", "frequency": N, "trend": "increasing|stable|decreasing"}}
  ],
  "active_blockers": [
    {{"blocker": "...", "blocking": "...", "impact": "high|medium|low", "resolution": "..."}}
  ],
  "unresolved_threads": [
    {{"topic": "...", "raised_date": "YYYY-MM-DD", "context": "..."}}
  ],
  "suggested_agenda": {{
    "must_discuss": ["..."],
    "should_discuss": ["..."],
    "could_discuss": ["..."]
  }},
  "meeting_patterns": {{
    "frequency_days": N,
    "last_meeting_date": "YYYY-MM-DD"
  }}
}}"""

    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": "You are an expert meeting analyst. Extract comprehensive, actionable insights from meeting history."},
            {"role": "user", "content": prompt}
        ],
        response_format={"type": "json_object"},
        temperature=0.3
    )

    return json.loads(response.choices[0].message.content)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--person-folder', required=True)
    parser.add_argument('--classification', required=True)
    args = parser.parse_args()

    classification = json.loads(args.classification)
    person = classification.get('participant', 'Team')

    meetings_folder = os.path.join(args.person_folder, 'Meetings')
    meetings = get_last_n_meetings(meetings_folder, n=5)

    if not meetings:
        # No previous meetings - return empty analysis
        result = {
            "open_action_items": [],
            "recurring_topics": [],
            "active_blockers": [],
            "unresolved_threads": [],
            "suggested_agenda": {
                "must_discuss": ["First meeting - introductions and expectations"],
                "should_discuss": [],
                "could_discuss": []
            },
            "meeting_patterns": {
                "frequency_days": 0,
                "last_meeting_date": None
            }
        }
    else:
        result = analyze_continuity(meetings, person)

    print(json.dumps(result, indent=2))
```

### Component 6: Meeting Note Generator (generate-meeting-note.py)

**File:** `config/sketchybar/helpers/generate-meeting-note.py`

**Purpose:** AI-powered generation of pre-filled meeting note from template

```python
#!/usr/bin/env python3

import argparse
import json
import os
from datetime import datetime, timedelta
from pathlib import Path
from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()

client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))

def load_template(meeting_type: str) -> str:
    """Load appropriate template based on meeting type."""

    vault_root = os.getenv('OBSIDIAN_VAULT_PATH')
    template_map = {
        'ipmedia_1on1': 'meeting-1on1-template.md',
        'co_company': 'meeting-company-template.md',
        'ipmedia_team': 'meeting-team-template.md'
    }

    # Determine base type
    if '1on1' in meeting_type:
        base_type = 'ipmedia_1on1'
    elif 'team' in meeting_type:
        base_type = 'ipmedia_team'
    else:
        base_type = 'co_company'

    template_file = template_map[base_type]
    template_path = Path(vault_root) / 'bmad' / 'vault-ops' / 'templates' / template_file

    with open(template_path, 'r') as f:
        return f.read()

def generate_meeting_note(classification: dict, continuity: dict, person_folder: str) -> dict:
    """Generate pre-filled meeting note using AI."""

    template = load_template(classification['meeting_type'])

    # Calculate next meeting date from pattern
    last_meeting = continuity.get('meeting_patterns', {}).get('last_meeting_date')
    frequency = continuity.get('meeting_patterns', {}).get('frequency_days', 7)

    if last_meeting:
        last_date = datetime.strptime(last_meeting, '%Y-%m-%d')
        next_date = last_date + timedelta(days=frequency)
    else:
        next_date = datetime.now()

    next_date_str = next_date.strftime('%Y-%m-%d')

    # Build comprehensive prompt
    prompt = f"""Generate a complete, pre-filled meeting note for upcoming meeting.

TEMPLATE:
{template}

MEETING CONTEXT:
- Date: {next_date_str}
- Participant: {classification.get('participant', 'Team')}
- Company: {classification['company']}
- Meeting Type: {classification['meeting_type']}
- Previous Meeting: {last_meeting or 'First meeting'}

CONTINUITY ANALYSIS:
{json.dumps(continuity, indent=2)}

INSTRUCTIONS:

1. Replace ALL template variables:
   - {{{{date:YYYY-MM-DD}}}} → {next_date_str}
   - {{{{time:HH:MM}}}} → {next_date.strftime('%H:%M')}
   - {{{{participant}}}} → {classification.get('participant', 'Team')}
   - {{{{company}}}} → {classification['company']}
   - {{{{previous_meeting}}}} → {last_meeting or 'None'}

2. Fill MEETING PREP sections with real content:

   A. 🚨 Critical/Urgent Items
      - List overdue action items with days overdue
      - List high-priority items from suggested agenda

   B. 💭 Prepared Questions
      - Generate 3-5 specific questions based on:
        * Open action items needing status
        * Unresolved threads
        * Recurring topics needing follow-up

   C. 📌 Key Topics to Cover
      - Pull from suggested_agenda (must/should/could)
      - Include brief context for each

   D. 🔄 Follow-ups from Last Meeting
      - List all open action items with tracking info
      - Group by: Action Items, Ongoing Discussions, Support Needed

   E. 📊 Context from Last Meeting
      - Summarize major topics, decisions, concerns, wins

3. Leave CAPTURE sections empty (filled during meeting):
   - Notes During Meeting
   - Action Items (new)
   - Key Insights & Quotes
   - Decisions Made
   - Blockers Identified

4. Generate proper wikilinks:
   - Person: [[Business/People/{classification['company']}/{classification.get('participant', 'Team')}/{classification.get('participant', 'Team')}|{classification.get('participant', 'Team')}]]
   - Company: [[Business/{classification['company']}/{classification['company']}|{classification['company']}]]

Return the COMPLETE meeting note as markdown text."""

    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": "You are an expert meeting preparation assistant. Generate comprehensive, actionable meeting notes."},
            {"role": "user", "content": prompt}
        ],
        temperature=0.5
    )

    meeting_note_content = response.choices[0].message.content

    # Determine save path
    if '1on1' in classification['meeting_type']:
        save_path = Path(person_folder) / 'Meetings' / f"{next_date_str} 1on1.md"
    elif 'team' in classification['meeting_type']:
        team = classification['team']
        vault_root = os.getenv('OBSIDIAN_VAULT_PATH')
        save_path = Path(vault_root) / 'Business' / 'People' / 'IPMedia' / 'Teams' / team / f"{next_date_str} {team} Meeting.md"
    else:
        company = classification['company']
        vault_root = os.getenv('OBSIDIAN_VAULT_PATH')
        save_path = Path(vault_root) / 'Business' / 'CO' / company / 'Meetings' / f"{next_date_str} {company} Weekly.md"

    # Ensure directory exists
    save_path.parent.mkdir(parents=True, exist_ok=True)

    # Write file
    with open(save_path, 'w') as f:
        f.write(meeting_note_content)

    return {
        'file_path': str(save_path.relative_to(Path(os.getenv('OBSIDIAN_VAULT_PATH')))),
        'full_path': str(save_path),
        'date': next_date_str,
        'success': True
    }

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--classification', required=True)
    parser.add_argument('--person-folder', required=True)
    parser.add_argument('--continuity', required=True)
    args = parser.parse_args()

    classification = json.loads(args.classification)
    continuity = json.loads(args.continuity)

    result = generate_meeting_note(classification, continuity, args.person_folder)

    print(json.dumps(result, indent=2))
```

---

## Development Setup

### Prerequisites

**System Requirements:**
- macOS 14.0+ (Sonoma or later)
- Python 3.11+
- Bash 5.2+
- Obsidian app installed

**Verify Prerequisites:**
```bash
# Check Python version
python3 --version  # Should be 3.11+

# Check Bash version
bash --version  # Should be 5.2+

# Check Obsidian is installed
ls -la "/Applications/Obsidian.app"  # Should exist

# Check Sketchybar
sketchybar --version  # Should be v2.20+
```

### Python Virtual Environment Setup

**Create and configure Python venv:**

```bash
# Create venv in Sketchybar config
cd ~/.config/sketchybar
python3 -m venv venv

# Activate venv
source venv/bin/activate

# Install dependencies
cat > requirements.txt << 'EOF'
openai==1.12.0
python-dotenv==1.0.0
pyyaml==6.0.1
EOF

pip install -r requirements.txt

# Verify installation
python3 -c "import openai; print('OpenAI:', openai.__version__)"
python3 -c "import dotenv; print('python-dotenv installed')"
python3 -c "import yaml; print('PyYAML installed')"
```

### Environment Configuration

**Required .env variables:**

```bash
# Edit ~/.env or ~/dotfiles/.env
cat >> ~/.env << 'EOF'

# Obsidian Meeting Prep
OBSIDIAN_VAULT_PATH="/Users/v/Library/Mobile Documents/iCloud~md~obsidian/Documents/U"
OPENAI_API_KEY="sk-proj-..."  # Get from https://platform.openai.com/api-keys

EOF
```

**Verify .env configuration:**

```bash
# Test loading
source ~/.env
[[ -n "$OBSIDIAN_VAULT_PATH" ]] && echo "✓ Vault path set" || echo "✗ Missing OBSIDIAN_VAULT_PATH"
[[ -n "$OPENAI_API_KEY" ]] && echo "✓ API key set" || echo "✗ Missing OPENAI_API_KEY"

# Test vault access
[[ -d "$OBSIDIAN_VAULT_PATH" ]] && echo "✓ Vault accessible" || echo "✗ Vault not found"
[[ -d "$OBSIDIAN_VAULT_PATH/bmad/vault-ops/templates" ]] && echo "✓ Templates found" || echo "✗ Templates missing"
```

### OpenAI API Key Setup

**Get API key:**
1. Visit https://platform.openai.com/api-keys
2. Create new secret key
3. Copy key to `.env` file
4. Add $5-10 credit to account (enough for ~1000-2000 meeting preps)

**Test API access:**
```bash
# Activate venv
source ~/.config/sketchybar/venv/bin/activate

# Test API
python3 << 'EOF'
import os
from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()
client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))

response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "Say 'API works!'"}],
    max_tokens=10
)

print(response.choices[0].message.content)
EOF
# Expected output: "API works!"
```

### Directory Structure Creation

**Create required directories:**

```bash
# Cache directory
mkdir -p ~/.cache/sketchybar

# Logs directory (if doesn't exist)
mkdir -p ~/.config/sketchybar/logs

# Helpers directory (should already exist)
mkdir -p ~/.config/sketchybar/helpers

# Verify structure
tree ~/.config/sketchybar -L 2
```

### File Permissions

**Set executable permissions on scripts:**

```bash
chmod +x ~/.config/sketchybar/helpers/meeting-prep.sh
chmod +x ~/.config/sketchybar/helpers/find-person-folder.sh
chmod +x ~/.config/sketchybar/helpers/classify-meeting.py
chmod +x ~/.config/sketchybar/helpers/analyze-meeting-history.py
chmod +x ~/.config/sketchybar/helpers/generate-meeting-note.py
```

### Obsidian Vault Verification

**Verify vault structure exists:**

```bash
VAULT_PATH="/Users/v/Library/Mobile Documents/iCloud~md~obsidian/Documents/U"

# Check critical paths
[[ -d "$VAULT_PATH/Business/People/IPMedia" ]] && echo "✓ IPMedia folder" || echo "✗ Missing"
[[ -d "$VAULT_PATH/Business/CO" ]] && echo "✓ CO folder" || echo "✗ Missing"
[[ -f "$VAULT_PATH/bmad/vault-ops/templates/meeting-1on1-template.md" ]] && echo "✓ 1on1 template" || echo "✗ Missing"
[[ -f "$VAULT_PATH/bmad/vault-ops/templates/meeting-company-template.md" ]] && echo "✓ Company template" || echo "✗ Missing"
[[ -f "$VAULT_PATH/bmad/vault-ops/templates/meeting-team-template.md" ]] && echo "✓ Team template" || echo "✗ Missing"
```

### Test Data Preparation

**Create test person folder (optional):**

```bash
VAULT_PATH="/Users/v/Library/Mobile Documents/iCloud~md~obsidian/Documents/U"
TEST_PERSON="TestPerson"

# Create test structure
mkdir -p "$VAULT_PATH/Business/People/IPMedia/$TEST_PERSON/Meetings"
mkdir -p "$VAULT_PATH/Business/People/IPMedia/$TEST_PERSON/Documents"
mkdir -p "$VAULT_PATH/Business/People/IPMedia/$TEST_PERSON/attachments"

# Create profile
cat > "$VAULT_PATH/Business/People/IPMedia/$TEST_PERSON/$TEST_PERSON.md" << 'EOF'
---
role: Test Role
company: IPMedia
tags: [person, test]
---

# TestPerson

Test person for meeting prep development.
EOF

echo "✓ Test person created at: $VAULT_PATH/Business/People/IPMedia/$TEST_PERSON"
```

---

## Implementation Guide

### Phase 1: Python Scripts Creation (60 minutes)

**Goal:** Create all Python helper scripts with AI integration

**Step 1.1: Meeting Classifier**
```bash
# Create classify-meeting.py
cat > ~/.config/sketchybar/helpers/classify-meeting.py << 'EOF'
# (Use complete code from Technical Details - Component 3)
EOF

chmod +x ~/.config/sketchybar/helpers/classify-meeting.py

# Test
python3 ~/.config/sketchybar/helpers/classify-meeting.py \
    --title "1on1 with Marcus" \
    --date "2025-11-15" \
    --participants "Jeff Hamersly,Marcus"
# Expected: JSON with meeting_type: ipmedia_1on1
```

**Step 1.2: Meeting History Analyzer**
```bash
# Create analyze-meeting-history.py
cat > ~/.config/sketchybar/helpers/analyze-meeting-history.py << 'EOF'
# (Use complete code from Technical Details - Component 5)
EOF

chmod +x ~/.config/sketchybar/helpers/analyze-meeting-history.py

# Test with test person (requires existing meetings)
# Will test in Phase 4
```

**Step 1.3: Meeting Note Generator**
```bash
# Create generate-meeting-note.py
cat > ~/.config/sketchybar/helpers/generate-meeting-note.py << 'EOF'
# (Use complete code from Technical Details - Component 6)
EOF

chmod +x ~/.config/sketchybar/helpers/generate-meeting-note.py

# Test will be in integration phase
```

### Phase 2: Bash Scripts Creation (30 minutes)

**Goal:** Create orchestration and helper bash scripts

**Step 2.1: Person Folder Finder**
```bash
# Create find-person-folder.sh
cat > ~/.config/sketchybar/helpers/find-person-folder.sh << 'EOF'
# (Use complete code from Technical Details - Component 4)
EOF

chmod +x ~/.config/sketchybar/helpers/find-person-folder.sh

# Test
bash ~/.config/sketchybar/helpers/find-person-folder.sh \
    --person "TestPerson" \
    --company "IPMedia"
# Expected: Path to TestPerson folder
```

**Step 2.2: Main Orchestration Script**
```bash
# Create meeting-prep.sh
cat > ~/.config/sketchybar/helpers/meeting-prep.sh << 'EOF'
# (Use complete code from Technical Details - Component 2)
EOF

chmod +x ~/.config/sketchybar/helpers/meeting-prep.sh

# Don't test yet - needs full integration
```

### Phase 3: Sketchybar Integration (20 minutes)

**Goal:** Add icon click handler to existing meeting.sh plugin

**Step 3.1: Backup Current Config**
```bash
cp ~/.config/sketchybar/plugins/meeting.sh \
   ~/.config/sketchybar/plugins/meeting.sh.backup-$(date +%Y%m%d)
```

**Step 3.2: Add Icon Click Handler**
```bash
# Find the line where meeting widget is configured
# Around line 240 in meeting.sh
# Add icon click handler:

ICON_CLICK_SCRIPT="~/.config/sketchybar/helpers/meeting-prep.sh '\$NAME' '\$SENDER'"

sketchybar --set "$NAME" \
    icon.click_script="$ICON_CLICK_SCRIPT"
```

**Manual Edit Required:**
Open `~/.config/sketchybar/plugins/meeting.sh` and add the icon click handler configuration after the existing label click_script setup.

**Step 3.3: Reload Sketchybar**
```bash
brew services restart sketchybar

# Verify restart
pgrep -fl sketchybar
```

### Phase 4: Integration Testing (45 minutes)

**Goal:** Test complete end-to-end workflow

**Step 4.1: Create Test Meeting Data**
```bash
VAULT_PATH="/Users/v/Library/Mobile Documents/iCloud~md~obsidian/Documents/U"
TEST_PERSON="TestPerson"

# Create a test meeting note (simulating past meeting)
cat > "$VAULT_PATH/Business/People/IPMedia/$TEST_PERSON/Meetings/2025-10-25 1on1.md" << 'EOF'
---
date: "2025-10-25"
participants: ["[[Jeff Hamersly]]", "[[TestPerson]]"]
company: "IPMedia"
meeting_type: "1on1"
---

# 2025-10-25 1on1 with TestPerson

## Action Items
- [ ] Review Q4 roadmap - Owner: [[Jeff]] - Due: 2025-11-01
- [ ] Complete project documentation - Owner: [[TestPerson]] - Due: 2025-11-05

## Key Insights & Quotes
> "We need to focus on API performance improvements" - [[TestPerson]]
> **Insight:** Performance is becoming a blocker for new features

## Decisions Made
- Prioritize performance work over new features for next sprint
- Delay marketing dashboard to Q1

## Notes During Meeting
- Discussed Q4 goals and priorities
- TestPerson raised concerns about technical debt
- Agreed on performance focus

## Blockers Identified
- API performance degrading under load
- Limited testing infrastructure
EOF

echo "✓ Test meeting created"
```

**Step 4.2: Test Meeting Classification**
```bash
# Activate venv
source ~/.config/sketchybar/venv/bin/activate

# Test classifier
python3 ~/.config/sketchybar/helpers/classify-meeting.py \
    --title "1on1 with TestPerson" \
    --date "2025-11-02" \
    --participants "Jeff Hamersly,TestPerson"

# Expected output:
# {
#   "meeting_type": "ipmedia_1on1",
#   "company": "IPMedia",
#   "participant": "TestPerson",
#   "confidence": 95
# }
```

**Step 4.3: Test Person Folder Finder**
```bash
bash ~/.config/sketchybar/helpers/find-person-folder.sh \
    --person "TestPerson" \
    --company "IPMedia"

# Expected: /path/to/.../Business/People/IPMedia/TestPerson
```

**Step 4.4: Test Meeting History Analysis**
```bash
source ~/.config/sketchybar/venv/bin/activate

CLASSIFICATION='{"meeting_type":"ipmedia_1on1","company":"IPMedia","participant":"TestPerson"}'
PERSON_FOLDER="/Users/v/Library/Mobile Documents/iCloud~md~obsidian/Documents/U/Business/People/IPMedia/TestPerson"

python3 ~/.config/sketchybar/helpers/analyze-meeting-history.py \
    --person-folder "$PERSON_FOLDER" \
    --classification "$CLASSIFICATION"

# Expected: JSON with open_action_items, suggested_agenda, etc.
# Review output - should extract the 2 action items from test meeting
```

**Step 4.5: Test Meeting Note Generation**
```bash
source ~/.config/sketchybar/venv/bin/activate

CLASSIFICATION='{"meeting_type":"ipmedia_1on1","company":"IPMedia","participant":"TestPerson"}'
PERSON_FOLDER="/Users/v/Library/Mobile Documents/iCloud~md~obsidian/Documents/U/Business/People/IPMedia/TestPerson"

# Get continuity from previous step (or use cached)
CONTINUITY=$(python3 ~/.config/sketchybar/helpers/analyze-meeting-history.py \
    --person-folder "$PERSON_FOLDER" \
    --classification "$CLASSIFICATION")

python3 ~/.config/sketchybar/helpers/generate-meeting-note.py \
    --classification "$CLASSIFICATION" \
    --person-folder "$PERSON_FOLDER" \
    --continuity "$CONTINUITY"

# Expected: JSON with file_path and success: true
# Check that meeting note was created in Meetings folder
```

**Step 4.6: Verify Generated Meeting Note**
```bash
VAULT_PATH="/Users/v/Library/Mobile Documents/iCloud~md~obsidian/Documents/U"
TEST_PERSON="TestPerson"

# Find the newly generated meeting note
ls -la "$VAULT_PATH/Business/People/IPMedia/$TEST_PERSON/Meetings/"

# Open in editor to review
# Should have:
# - Pre-filled Meeting Prep sections
# - Action items from last meeting
# - Suggested questions
# - Context from last meeting
# - Empty Capture sections
```

**Step 4.7: Test Obsidian URL Opening**
```bash
# Test opening a meeting note in Obsidian
NOTE_PATH="Business/People/IPMedia/TestPerson/Meetings/2025-11-02 1on1.md"
ENCODED_PATH=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$NOTE_PATH'))")

open "obsidian://open?vault=U&file=$ENCODED_PATH"

# Obsidian should open with the meeting note
```

### Phase 5: Real-World Testing (30 minutes)

**Goal:** Test with actual calendar meetings

**Step 5.1: Test with Real Meeting**
```bash
# Click the ICON (not label) of your next calendar meeting in Sketchybar
# Watch the loading animation: ... → :.. → .:. → ..:
# Verify Obsidian opens with pre-filled meeting note
```

**Step 5.2: Verify Meeting Note Quality**
Check the generated note for:
- [ ] Correct date, participant, company
- [ ] Proper wikilinks
- [ ] Open action items from previous meetings
- [ ] Relevant prepared questions
- [ ] Context from last meeting
- [ ] Suggested agenda items
- [ ] Empty capture sections (ready for live notes)

**Step 5.3: Check Debug Cache**
```bash
# Review cached result
cat ~/.cache/sketchybar/last_meeting_prep_result.json | jq

# Should show complete workflow result
```

### Phase 6: Error Handling Testing (20 minutes)

**Test error scenarios:**

**Test 1: Person Not Found**
```bash
# Try preparing meeting for non-existent person
python3 ~/.config/sketchybar/helpers/classify-meeting.py \
    --title "1on1 with NonExistentPerson" \
    --date "2025-11-02" \
    --participants "Jeff Hamersly,NonExistentPerson"

# Then try finding folder
bash ~/.config/sketchybar/helpers/find-person-folder.sh \
    --person "NonExistentPerson" \
    --company "IPMedia"

# Expected: Error message, exit code 1
```

**Test 2: Missing OpenAI API Key**
```bash
# Temporarily rename .env
mv ~/.env ~/.env.backup

# Try running analysis
python3 ~/.config/sketchybar/helpers/analyze-meeting-history.py \
    --person-folder "$PERSON_FOLDER" \
    --classification "$CLASSIFICATION"

# Expected: Error about missing API key

# Restore .env
mv ~/.env.backup ~/.env
```

**Test 3: Invalid Vault Path**
```bash
# Temporarily modify .env
echo 'OBSIDIAN_VAULT_PATH="/invalid/path"' >> ~/.env

# Try person folder search
bash ~/.config/sketchybar/helpers/find-person-folder.sh \
    --person "TestPerson" \
    --company "IPMedia"

# Expected: Not found error

# Fix .env (remove last line)
head -n -1 ~/.env > ~/.env.tmp && mv ~/.env.tmp ~/.env
```

### Phase 7: Performance Optimization (15 minutes)

**Measure timing:**

```bash
# Time complete workflow
time bash ~/.config/sketchybar/helpers/meeting-prep.sh "meeting" "test"

# Target: 15-45 seconds total
# If slower, check:
# - OpenAI API latency
# - Number of meetings being analyzed (should be 5)
# - File I/O operations
```

**Monitor API usage:**
```bash
# Check OpenAI dashboard: https://platform.openai.com/usage
# Verify costs are ~$0.005 per meeting prep
```

### Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| "Module 'openai' not found" | Activate venv: `source ~/.config/sketchybar/venv/bin/activate` |
| "Permission denied" | Add execute permissions: `chmod +x script.sh` |
| Obsidian doesn't open | Check Obsidian app is installed, vault name is "U" |
| Loading animation stuck | Check logs, kill process: `pkill -f meeting-prep.sh` |
| API rate limit hit | Wait 1 minute, check usage at platform.openai.com |
| Template not found | Verify vault path, check templates exist |
| Meeting note empty | Check AI prompt, verify continuity analysis worked |

---

## Testing Approach

### Unit Testing

**Test 1: Meeting Classification**
```bash
source ~/.config/sketchybar/venv/bin/activate

# Test IPMedia 1-on-1
python3 ~/.config/sketchybar/helpers/classify-meeting.py \
    --title "1on1 with Marcus" \
    --date "2025-11-02" \
    --participants "Jeff Hamersly,Marcus" | jq '.meeting_type'
# Expected: "ipmedia_1on1"

# Test company meeting
python3 ~/.config/sketchybar/helpers/classify-meeting.py \
    --title "Weekly TP Meeting" \
    --date "2025-11-02" \
    --participants "Jeff Hamersly,Team" | jq '.meeting_type'
# Expected: "co_tp_meeting"

# Test team meeting
python3 ~/.config/sketchybar/helpers/classify-meeting.py \
    --title "BI Team Dashboard" \
    --date "2025-11-02" \
    --participants "Jeff Hamersly,BI Team" | jq '.meeting_type'
# Expected: "ipmedia_team_bi"

# Test unknown
python3 ~/.config/sketchybar/helpers/classify-meeting.py \
    --title "Random Meeting" \
    --date "2025-11-02" \
    --participants "Jeff Hamersly,Someone" | jq '.meeting_type'
# Expected: "unknown"
```

**Test 2: Person Folder Discovery**
```bash
# Test existing person
bash ~/.config/sketchybar/helpers/find-person-folder.sh \
    --person "Marcus" \
    --company "IPMedia"
# Expected: Path to Marcus folder or exit 1

# Test non-existent person
bash ~/.config/sketchybar/helpers/find-person-folder.sh \
    --person "NonExistent" \
    --company "IPMedia"
# Expected: Error message, exit code 1
```

**Test 3: Meeting History Analysis (AI)**
```bash
source ~/.config/sketchybar/venv/bin/activate

# Create minimal test
CLASSIFICATION='{"meeting_type":"ipmedia_1on1","company":"IPMedia","participant":"TestPerson"}'
PERSON_FOLDER="/Users/v/Library/Mobile Documents/iCloud~md~obsidian/Documents/U/Business/People/IPMedia/TestPerson"

OUTPUT=$(python3 ~/.config/sketchybar/helpers/analyze-meeting-history.py \
    --person-folder "$PERSON_FOLDER" \
    --classification "$CLASSIFICATION")

# Validate JSON structure
echo "$OUTPUT" | jq -e '.open_action_items' > /dev/null && echo "✓ Has action items"
echo "$OUTPUT" | jq -e '.suggested_agenda' > /dev/null && echo "✓ Has agenda"
echo "$OUTPUT" | jq -e '.meeting_patterns' > /dev/null && echo "✓ Has patterns"
```

**Test 4: Meeting Note Generation (AI)**
```bash
source ~/.config/sketchybar/venv/bin/activate

CLASSIFICATION='{"meeting_type":"ipmedia_1on1","company":"IPMedia","participant":"TestPerson"}'
CONTINUITY='{"open_action_items":[],"suggested_agenda":{"must_discuss":[],"should_discuss":[],"could_discuss":[]},"meeting_patterns":{"frequency_days":7,"last_meeting_date":"2025-10-25"}}'
PERSON_FOLDER="/Users/v/Library/Mobile Documents/iCloud~md~obsidian/Documents/U/Business/People/IPMedia/TestPerson"

OUTPUT=$(python3 ~/.config/sketchybar/helpers/generate-meeting-note.py \
    --classification "$CLASSIFICATION" \
    --person-folder "$PERSON_FOLDER" \
    --continuity "$CONTINUITY")

# Validate output
echo "$OUTPUT" | jq -e '.success' > /dev/null && echo "✓ Success flag"
echo "$OUTPUT" | jq -e '.file_path' > /dev/null && echo "✓ Has file path"

# Check file was created
FILE_PATH=$(echo "$OUTPUT" | jq -r '.full_path')
[[ -f "$FILE_PATH" ]] && echo "✓ File exists" || echo "✗ File not created"
```

### Integration Testing

**Full Workflow Test Matrix**

| Test Case | Scenario | Expected Result |
|-----------|----------|-----------------|
| Happy Path | 1-on-1 with existing person + past meetings | Complete note generated in <45s |
| First Meeting | 1-on-1 with person who has no meetings | Note with "first meeting" agenda |
| Company Meeting | TP Weekly with no participants | Company meeting note created |
| Team Meeting | BI Dashboard | Team meeting note created |
| Missing Person | Meeting with unknown participant | Error: Person not found |
| Invalid API Key | Analysis with bad OPENAI_API_KEY | Error: API authentication failed |
| No Templates | Vault missing template files | Error: Template not found |

**Test Script:**
```bash
#!/usr/bin/env bash
# integration-test.sh

source ~/.config/sketchybar/venv/bin/activate
source ~/.env

PASSED=0
FAILED=0

run_test() {
    local test_name=$1
    local command=$2
    local expected_pattern=$3

    echo "Running: $test_name"
    OUTPUT=$(eval "$command" 2>&1)

    if echo "$OUTPUT" | grep -q "$expected_pattern"; then
        echo "✓ PASS: $test_name"
        ((PASSED++))
    else
        echo "✗ FAIL: $test_name"
        echo "  Output: $OUTPUT"
        ((FAILED++))
    fi
}

# Test 1: Classification
run_test "Classify 1-on-1" \
    "python3 ~/.config/sketchybar/helpers/classify-meeting.py --title '1on1 with Marcus' --date '2025-11-02' --participants 'Jeff Hamersly,Marcus'" \
    "ipmedia_1on1"

# Test 2: Person folder
run_test "Find person folder" \
    "bash ~/.config/sketchybar/helpers/find-person-folder.sh --person 'TestPerson' --company 'IPMedia'" \
    "TestPerson"

# Test 3: History analysis
run_test "Analyze history" \
    "python3 ~/.config/sketchybar/helpers/analyze-meeting-history.py --person-folder '$OBSIDIAN_VAULT_PATH/Business/People/IPMedia/TestPerson' --classification '{\"meeting_type\":\"ipmedia_1on1\",\"company\":\"IPMedia\",\"participant\":\"TestPerson\"}'" \
    "open_action_items"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
```

### Performance Testing

**Benchmark Tests:**
```bash
# Test 1: Classification speed
time python3 ~/.config/sketchybar/helpers/classify-meeting.py \
    --title "1on1 with Marcus" \
    --date "2025-11-02" \
    --participants "Jeff Hamersly,Marcus"
# Target: <100ms

# Test 2: Person folder search
time bash ~/.config/sketchybar/helpers/find-person-folder.sh \
    --person "Marcus" \
    --company "IPMedia"
# Target: <200ms

# Test 3: AI analysis (varies with meeting count)
time python3 ~/.config/sketchybar/helpers/analyze-meeting-history.py \
    --person-folder "$PERSON_FOLDER" \
    --classification "$CLASSIFICATION"
# Target: 8-15 seconds for 5 meetings

# Test 4: Note generation
time python3 ~/.config/sketchybar/helpers/generate-meeting-note.py \
    --classification "$CLASSIFICATION" \
    --person-folder "$PERSON_FOLDER" \
    --continuity "$CONTINUITY"
# Target: 5-10 seconds

# Test 5: End-to-end
time bash ~/.config/sketchybar/helpers/meeting-prep.sh "meeting" "test"
# Target: 15-45 seconds total
```

### Error Scenario Testing

**Test Error Handling:**

```bash
# Test 1: Missing environment variables
unset OPENAI_API_KEY
python3 ~/.config/sketchybar/helpers/analyze-meeting-history.py \
    --person-folder "$PERSON_FOLDER" \
    --classification "$CLASSIFICATION" 2>&1 | grep -i "api key"
# Should show API key error

# Test 2: Invalid vault path
OBSIDIAN_VAULT_PATH="/invalid" bash ~/.config/sketchybar/helpers/find-person-folder.sh \
    --person "Marcus" \
    --company "IPMedia"
# Should exit with error code 1

# Test 3: Malformed JSON input
python3 ~/.config/sketchybar/helpers/analyze-meeting-history.py \
    --person-folder "$PERSON_FOLDER" \
    --classification "invalid json"
# Should handle JSON parse error gracefully

# Test 4: API rate limit (simulate by making rapid requests)
for i in {1..10}; do
    python3 ~/.config/sketchybar/helpers/analyze-meeting-history.py \
        --person-folder "$PERSON_FOLDER" \
        --classification "$CLASSIFICATION" &
done
wait
# Should handle rate limit errors with retry logic
```

### AI Output Quality Testing

**Manual Review Checklist for Generated Notes:**

- [ ] **Meeting Metadata**
  - Correct date format (YYYY-MM-DD)
  - Proper participant names
  - Company correctly identified
  - Meeting type matches classification

- [ ] **Meeting Prep Sections**
  - Critical/Urgent items properly flagged
  - Questions are specific and actionable
  - Topics have context and priority
  - Action items include owner and status

- [ ] **Context from Last Meeting**
  - Accurately summarizes previous discussion
  - Decisions correctly extracted
  - No hallucinated information

- [ ] **Wikilinks**
  - Person links formatted correctly
  - Company links point to right location
  - No broken link syntax

- [ ] **Empty Sections**
  - Capture sections are empty (not pre-filled)
  - Ready for live note-taking

**Quality Test Script:**
```bash
# Generate note and check quality
GENERATED_NOTE=$(python3 ~/.config/sketchybar/helpers/generate-meeting-note.py \
    --classification "$CLASSIFICATION" \
    --person-folder "$PERSON_FOLDER" \
    --continuity "$CONTINUITY")

FILE_PATH=$(echo "$GENERATED_NOTE" | jq -r '.full_path')

# Check structure
grep -q "^# 2025-" "$FILE_PATH" && echo "✓ Has title"
grep -q "## 🎯 MEETING PREP" "$FILE_PATH" && echo "✓ Has prep section"
grep -q "## 📝 NOTES DURING MEETING" "$FILE_PATH" && echo "✓ Has capture section"
grep -q "\[\[.*\]\]" "$FILE_PATH" && echo "✓ Has wikilinks"

# Check empty sections (should NOT have content)
! grep -A 5 "## 📝 NOTES DURING MEETING" "$FILE_PATH" | grep -q "^-" && echo "✓ Capture section empty"
```

### Regression Testing

**After Changes Checklist:**
```bash
# 1. Run unit tests
bash integration-test.sh

# 2. Test with real data
# Click icon for actual meeting
# Verify note quality manually

# 3. Check performance
time bash ~/.config/sketchybar/helpers/meeting-prep.sh "meeting" "test"

# 4. Verify no API errors
cat ~/.config/sketchybar/logs/*.log | grep -i error

# 5. Check costs
# Visit https://platform.openai.com/usage
# Verify per-meeting cost ~$0.005
```

---

## Deployment Strategy

### Pre-Deployment Checklist

- [ ] Python venv created at `~/.config/sketchybar/venv`
- [ ] Dependencies installed (`openai`, `python-dotenv`, `pyyaml`)
- [ ] `.env` file contains `OBSIDIAN_VAULT_PATH` and `OPENAI_API_KEY`
- [ ] OpenAI API key tested and working
- [ ] Obsidian vault accessible and templates exist
- [ ] Backup of current `meeting.sh` created
- [ ] All helper scripts have execute permissions
- [ ] Test person folder created for testing

### Deployment Steps

**Step 1: Backup Current Configuration**
```bash
# Backup meeting plugin
cp ~/.config/sketchybar/plugins/meeting.sh \
   ~/.config/sketchybar/plugins/meeting.sh.backup-$(date +%Y%m%d-%H%M%S)

# Backup entire Sketchybar config (optional)
tar -czf ~/sketchybar-backup-$(date +%Y%m%d).tar.gz ~/.config/sketchybar/
```

**Step 2: Deploy Python Scripts**
```bash
# Navigate to dotfiles repo
cd ~/repos/02_personal/dotfiles

# Create feature branch
git checkout -b feature/obsidian-meeting-prep

# Copy scripts to helpers directory (from this tech spec)
# classify-meeting.py
# analyze-meeting-history.py
# generate-meeting-note.py
# find-person-folder.sh
# meeting-prep.sh

# Set permissions
chmod +x config/sketchybar/helpers/classify-meeting.py
chmod +x config/sketchybar/helpers/analyze-meeting-history.py
chmod +x config/sketchybar/helpers/generate-meeting-note.py
chmod +x config/sketchybar/helpers/find-person-folder.sh
chmod +x config/sketchybar/helpers/meeting-prep.sh

# Since config is symlinked, changes apply immediately
```

**Step 3: Update meeting.sh Plugin**
```bash
# Edit meeting.sh to add icon click handler
# Add after existing click_script configuration (around line 240):

ICON_CLICK_SCRIPT="~/.config/sketchybar/helpers/meeting-prep.sh '\$NAME' '\$SENDER'"

sketchybar --set "$NAME" \
    icon.click_script="$ICON_CLICK_SCRIPT"
```

**Step 4: Test in Isolation**
```bash
# Test classification
python3 ~/.config/sketchybar/helpers/classify-meeting.py \
    --title "1on1 with TestPerson" \
    --date "2025-11-02" \
    --participants "Jeff Hamersly,TestPerson"

# Test person folder finder
bash ~/.config/sketchybar/helpers/find-person-folder.sh \
    --person "TestPerson" \
    --company "IPMedia"

# If both pass, proceed
```

**Step 5: Restart Sketchybar**
```bash
# Restart service
brew services restart sketchybar

# Verify running
pgrep -fl sketchybar

# Check widget visible
sketchybar --query meeting
```

**Step 6: Smoke Test**
```bash
# Click meeting widget ICON (not label)
# Should see loading animation
# Obsidian should open with generated note
# Verify note has content

# Check debug cache
cat ~/.cache/sketchybar/last_meeting_prep_result.json | jq
```

**Step 7: Commit Changes**
```bash
cd ~/repos/02_personal/dotfiles

git add config/sketchybar/helpers/*.py
git add config/sketchybar/helpers/meeting-prep.sh
git add config/sketchybar/helpers/find-person-folder.sh
git add config/sketchybar/plugins/meeting.sh
git add .env  # If adding new variables

git commit -m "feat(sketchybar): add Obsidian meeting prep integration

- Add icon click handler for meeting prep workflow
- Implement AI-powered meeting note generation
- Integrate with Obsidian vault structure
- Add meeting classification and history analysis
- Generate pre-filled meeting notes with context

Tech Stack: Python 3.11, OpenAI GPT-4o-mini, Obsidian
Cost: ~$0.005 per meeting prep
Performance: 15-45 seconds end-to-end"

# Push to remote
git push origin feature/obsidian-meeting-prep
```

### Rollback Plan

**If Issues Occur:**

```bash
# 1. Stop loading animation if stuck
pkill -f meeting-prep.sh

# 2. Restore backup
cp ~/.config/sketchybar/plugins/meeting.sh.backup-YYYYMMDD-HHMMSS \
   ~/.config/sketchybar/plugins/meeting.sh

# 3. Remove new scripts (optional)
rm ~/.config/sketchybar/helpers/classify-meeting.py
rm ~/.config/sketchybar/helpers/analyze-meeting-history.py
rm ~/.config/sketchybar/helpers/generate-meeting-note.py
rm ~/.config/sketchybar/helpers/find-person-folder.sh
rm ~/.config/sketchybar/helpers/meeting-prep.sh

# 4. Restart Sketchybar
brew services restart sketchybar

# 5. Verify meeting widget works normally
# Click label to see popup

# 6. Git rollback
cd ~/repos/02_personal/dotfiles
git checkout main
git branch -D feature/obsidian-meeting-prep
```

### Post-Deployment Monitoring

**First 24 Hours:**

```bash
# Monitor for errors
tail -f ~/.config/sketchybar/logs/*.log

# Check cache updates
watch -n 60 "ls -lh ~/.cache/sketchybar/"

# Monitor OpenAI usage
# Visit: https://platform.openai.com/usage
# Track: Total requests, costs, errors

# Test multiple meetings
# Click icon for different meeting types
# Verify all classifications work
```

**Success Metrics:**

- [ ] Icon click triggers workflow (no errors)
- [ ] Loading animation displays correctly
- [ ] Meeting notes generated in <45 seconds
- [ ] Obsidian opens with correct note
- [ ] Notes contain proper context from history
- [ ] No crashes or hangs in Sketchybar
- [ ] OpenAI costs ~$0.005 per meeting
- [ ] No API rate limit errors

### Git Workflow

**Branch Strategy:**
```bash
# Feature branch
git checkout -b feature/obsidian-meeting-prep

# Make changes and commit incrementally
git add -p  # Stage changes interactively

git commit -m "feat: add meeting classification script"
git commit -m "feat: add AI meeting history analyzer"
git commit -m "feat: add meeting note generator"
git commit -m "feat: integrate with Sketchybar icon click"

# Push for review (if working with others)
git push origin feature/obsidian-meeting-prep

# Or merge to main directly
git checkout main
git merge feature/obsidian-meeting-prep
git push origin main

# Tag release (optional)
git tag -a v1.0.0-meeting-prep -m "Release Obsidian meeting prep integration"
git push origin v1.0.0-meeting-prep
```

### Documentation Updates

**Update CLAUDE.md:**

Add new section documenting this feature:

```markdown
#### Obsidian Meeting Prep Integration

The calendar widget integrates with Obsidian vault for AI-powered meeting preparation.

**Architecture:**
```
Icon Click → meeting-prep.sh → classify → find person → analyze history →
generate note → save to vault → open in Obsidian
```

**Components:**
1. **classify-meeting.py**: Regex-based meeting type detection
2. **find-person-folder.sh**: Vault structure navigation
3. **analyze-meeting-history.py**: GPT-4o-mini analysis of last 5 meetings
4. **generate-meeting-note.py**: AI-powered note generation from templates

**Configuration:**
- `.env`: `OBSIDIAN_VAULT_PATH`, `OPENAI_API_KEY`
- Templates: `bmad/vault-ops/templates/meeting-*.md`
- Cache: `~/.cache/sketchybar/last_meeting_prep_result.json`

**Usage:**
Click meeting widget ICON (not label) to generate prep note.

**Troubleshooting:**
- Loading stuck: `pkill -f meeting-prep.sh`
- API errors: Check `~/.env` has valid `OPENAI_API_KEY`
- Person not found: Verify vault structure matches expected paths
- Costs: Visit https://platform.openai.com/usage (~$0.005 per meeting)
```

### Maintenance

**Regular Tasks:**

```bash
# Weekly: Check API usage and costs
# Visit: https://platform.openai.com/usage

# Monthly: Review generated notes quality
# Manually inspect 5-10 generated notes
# Check for hallucinations or errors
# Update prompts if needed

# Quarterly: Update dependencies
source ~/.config/sketchybar/venv/bin/activate
pip list --outdated
pip install --upgrade openai python-dotenv pyyaml

# As needed: Adjust AI prompts
# Edit analyze-meeting-history.py and generate-meeting-note.py
# Improve context extraction or note formatting
```

**Troubleshooting Common Issues:**

| Issue | Diagnostic | Solution |
|-------|------------|----------|
| Notes not opening | Check Obsidian running | Launch Obsidian app |
| API timeout | Check network | Retry, increase timeout in scripts |
| Poor note quality | Review AI prompts | Adjust temperature, add examples |
| High costs | Check usage dashboard | Reduce meeting count analyzed (5→3) |
| Classification errors | Test with actual titles | Add more patterns to classify-meeting.py |

---

**Deployment Complete!**

Next Steps:
1. Use daily for 1 week
2. Collect feedback on note quality
3. Iterate on AI prompts as needed
4. Consider adding more meeting types
5. Explore caching meeting analysis to reduce API calls
