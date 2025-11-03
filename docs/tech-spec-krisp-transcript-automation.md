# dotfiles - Technical Specification: Krisp Transcript Automation

**Author:** Jeff
**Date:** 2025-11-02
**Updated:** 2025-11-03 (Post Story 4-2 - Production Reality)
**Project Level:** 1 (Coherent feature - 3-5 stories)
**Project Type:** software
**Development Context:** brownfield (extending Epic 4 - Obsidian Integration)

---

## 📝 Story 4-2 Implementation Reality (2025-11-03)

**Status:** COMPLETE - Production-ready transcript downloader deployed

This section documents what was **actually implemented** in Story 4-2, which differs significantly from the original specification. The remaining features (calendar matching, AI analysis, note updates) are deferred to Story 4-3.

### ✅ What Was Built in Story 4-2

**Core Download Automation:**
- **Script:** `config/sketchybar/helpers/krisp-download-transcripts.py`
- **Authentication:** localStorage + cookies (not just cookies)
- **Transcript Download:** Clipboard-based copy (not file download)
- **Anti-Detection:** Basic flags only (NOT playwright-stealth - see critical findings)
- **Caching:** Idempotent processing with `processed-krisp-meetings.json`
- **LaunchAgent:** Hourly downloads via `com.user.krisp-transcript-download.plist`
  - **Opt-in:** Requires `KRISP_LAUNCHAGENT=TRUE` in `.env` to install
  - Safety mechanism prevents accidental installation without proper Krisp auth setup

**Production Features Added:**
- `--days-back N` parameter for backfill downloads (e.g., `--days-back 56` for 8 weeks)
- Multi-page pagination (scrapes until date cutoff reached)
- `--dry-run` mode for preview without downloading
- Per-meeting Telegram notifications (title, timestamp, transcript length, file path)
- Batch summary notification (success/pending/failed counts)
- Pending transcripts retry system (max 5 attempts for meetings where transcript not yet ready)

**CLI Usage:**
```bash
# Test auth
python3 krisp-download-transcripts.py --test-auth

# Download new transcripts (last 24 hours)
python3 krisp-download-transcripts.py --download-new --days-back 1 --limit 20 --headless

# Backfill historical transcripts
python3 krisp-download-transcripts.py --download-new --days-back 56 --limit 100 --headless

# Dry run preview
python3 krisp-download-transcripts.py --dry-run --days-back 7 --limit 20 --headless

# Debug with visible browser
python3 krisp-download-transcripts.py --download-new --days-back 1 --limit 5 --visible
```

### 🔥 Critical Implementation Findings

**1. playwright-stealth REMOVED (Not Added)**
- **Original Spec:** Required playwright-stealth for anti-detection
- **Reality:** playwright-stealth **BREAKS** Krisp's React app
- **Symptoms:** Blank white page, 0 meetings found, console errors
- **Root Cause:** Injects broken JavaScript: "utils is not defined", "opts is not defined", "Navigator.get error"
- **Solution:** Removed all `stealth_sync()` calls - basic anti-detection is sufficient
- **Test Results:** Found 100+ meetings after removal (was 0 with stealth)
- **Lesson:** Real-world testing > spec requirements

**2. URL Endpoint Correction**
- **Original Spec:** `https://app.krisp.ai/meetings`
- **Reality:** `https://app.krisp.ai/meeting-notes` (correct endpoint)
- **Testing:** /meetings doesn't work, /meeting-notes does

**3. Wait Strategy Optimization**
- **Original Spec:** `wait_until="networkidle"`
- **Reality:** `wait_until="load"` (10-15 seconds faster per page)
- **Reason:** networkidle too slow, load + timeout is reliable

**4. Authentication Method**
- **Original Spec:** Cookies only
- **Reality:** localStorage + cookies required
- **Process:**
  1. Navigate to domain, inject localStorage
  2. Add cookies to context
  3. Navigate to meeting-notes page
- **File:** `~/.config/sketchybar/krisp-auth.json` (contains both localStorage and cookies)

**5. Transcript Download Method**
- **Original Spec:** File download with `expect_download()`
- **Reality:** Clipboard-based copy (more reliable on macOS)
- **Process:**
  1. Click 3-dot menu button: `button[data-test-id="Dropdown"]`
  2. Click "Copy transcript" button
  3. Read from clipboard using `navigator.clipboard.readText()`
- **Reason:** No macOS permission issues, more reliable

### 📊 Production Performance Metrics

**Tested Results (Nich's E2E Validation):**
- Meetings scraped: 100+ across 5+ pages
- Timestamp parsing success: 95% (some non-standard formats gracefully handled)
- Date filtering: Tested 3 days and 56 days successfully
- Cache deduplication: Works perfectly
- Pagination: Continues until oldest meeting < cutoff
- Average performance: ~5 seconds per page, ~3-5 seconds per download

### 🗂️ File Structure (As Built)

```
dotfiles/
├── config/sketchybar/
│   ├── helpers/
│   │   └── krisp-download-transcripts.py        # Main download script (COMPLETE)
│   ├── launchagents/
│   │   └── com.user.krisp-transcript-download.plist  # Hourly LaunchAgent (NEW)
│   ├── logs/
│   │   ├── krisp-download.log                   # Main log file
│   │   ├── krisp-download-stdout.log            # LaunchAgent stdout
│   │   └── krisp-download-stderr.log            # LaunchAgent stderr
│   ├── krisp-transcripts/
│   │   └── krisp-transcript-{meeting_id}.txt    # Downloaded transcripts
│   └── requirements.txt                          # Updated with Playwright deps
├── scripts/
│   └── install.sh                                # Added install_krisp_transcript_launchagent()
└── .cache/sketchybar/
    └── processed-krisp-meetings.json             # Cache with pending_transcripts array
```

**Auth File:** `~/.config/sketchybar/krisp-auth.json`
```json
{
  "cookies": [...],
  "localStorage": {...},
  "updated_at": "2025-11-03T00:00:00Z"
}
```

**Cache File Structure:**
```json
{
  "last_check": "2025-11-03T00:00:00Z",
  "processed_meetings": [
    {
      "meeting_id": "019a3c973e74...",
      "title": "08:25 PM - Signal meeting October 31",
      "krisp_timestamp": "2025-10-31T20:25:00",
      "transcript_path": "/path/to/transcript.txt",
      "matched_calendar_event": null,
      "obsidian_note_path": null,
      "confidence": null,
      "processed_at": "2025-11-03T00:00:00Z"
    }
  ],
  "pending_transcripts": [
    {
      "meeting_id": "019a1234...",
      "title": "Meeting title",
      "url": "/t/...",
      "timestamp": "2025-11-02T14:00:00",
      "first_attempt": "2025-11-03T00:00:00Z",
      "retry_count": 2,
      "last_retry": "2025-11-03T01:00:00Z",
      "reason": "transcript_not_ready"
    }
  ]
}
```

### 🚫 What Was NOT Built (Deferred to Story 4-3)

The following components from the original spec are **NOT implemented** and will be Story 4-3:
- ❌ `krisp-match-meetings.py` - Calendar matching logic
- ❌ `krisp-analyze-transcript.py` - AI transcript analysis
- ❌ `krisp-update-note.py` - Obsidian note updater
- ❌ `krisp-orchestrator.sh` - Full workflow orchestration
- ❌ Calendar event matching (±15 min window)
- ❌ AI summary generation with GPT-4o-mini
- ❌ Obsidian Post-Meeting Summary updates
- ❌ Transcript saved to person folders

**Current State:** Story 4-2 downloads transcripts to `~/.config/sketchybar/krisp-transcripts/`. Story 4-3 will match them to calendar events, analyze with AI, and update Obsidian notes.

### 📦 Dependencies (As Implemented)

```requirements.txt
# From Story 4-1
openai==1.12.0
python-dotenv==1.0.0
pyyaml==6.0.1

# Added in Story 4-2
playwright==1.40.0
# playwright-stealth==1.0.6  # REMOVED - breaks Krisp app
requests==2.31.0
```

**Playwright Setup:**
```bash
playwright install chromium  # ~120MB download
```

### 🔄 Pending List Retry System

**Problem:** Krisp takes time to generate transcripts after meetings end.

**Solution:** Pending transcripts retry system
- When transcript button not found → add to `pending_transcripts` array
- Retry on next run (hourly LaunchAgent)
- Max 5 attempts before giving up
- Prevents missing meetings that are still being processed by Krisp

**Status Flow:**
```
Meeting Detected → Download Attempted
  ├─ SUCCESS → Add to processed_meetings
  ├─ NOT_READY → Add to pending_transcripts (retry next hour)
  └─ ERROR → Log error, skip
```

### 🎯 Next Steps (Story 4-3)

Story 4-3 will build the analysis pipeline:
1. Read transcripts from `~/.config/sketchybar/krisp-transcripts/`
2. Match to calendar events using khal
3. Classify meeting type → find person folder
4. Analyze with GPT-4o-mini
5. Update Obsidian notes with Post-Meeting Summary
6. Move transcript to `{person}/attachments/`

**Integration Point:** Story 4-3 will query `processed-krisp-meetings.json` to find unmatched transcripts (where `matched_calendar_event == null`).

---

## Source Tree Structure

```
dotfiles/
├── config/sketchybar/
│   ├── helpers/
│   │   ├── krisp-download-transcripts.py       # NEW - Main transcript downloader
│   │   ├── krisp-match-meetings.py             # NEW - Calendar matching logic
│   │   ├── krisp-analyze-transcript.py         # NEW - AI transcript analysis
│   │   ├── krisp-update-note.py                # NEW - Obsidian note updater
│   │   └── krisp-orchestrator.sh               # NEW - Hourly orchestration script
│   ├── logs/
│   │   └── krisp-automation.log                # NEW - Comprehensive logging
│   └── requirements.txt                         # MODIFIED - Add playwright, telegram
│
├── .env                                         # MODIFIED - Add Krisp/Telegram config
├── .env.example                                 # MODIFIED - Document new variables
│
└── Library/LaunchAgents/
    └── com.user.krisp-automation.plist          # NEW - Hourly LaunchAgent

Obsidian Vault (~/Library/Mobile Documents/iCloud~md~obsidian/Documents/U/):
├── claude-obsidian/
│   ├── config/
│   │   ├── krisp-cookies.json                  # NEW - Browser cookie export
│   │   └── telegram-bot.json                   # NEW - Telegram bot credentials
│   └── cache/
│       └── processed-meetings.json             # NEW - Tracking processed meetings
│
└── Business/People/IPMedia/{PersonName}/
    ├── Meetings/
    │   └── YYYY-MM-DD 1on1.md                  # MODIFIED - Add Post-Meeting Summary
    └── attachments/
        └── YYYY-MM-DD-{person}-transcript.txt  # NEW - Raw transcript storage
```

---

## Technical Approach

### High-Level Workflow

```
Hourly Trigger (LaunchAgent)
    ↓
krisp-orchestrator.sh
    ↓
1. Test Krisp Auth (cookie validation)
    ├─ SUCCESS → Continue
    └─ FAIL → Send Telegram alert, exit
    ↓
2. Launch Playwright (undetected Chrome)
    ↓
3. Load krisp-cookies.json
    ↓
4. Navigate to app.krisp.ai/meetings
    ↓
5. Scrape meeting list (last 24 hours)
    ↓
6. Filter unprocessed meetings (check processed-meetings.json)
    ↓
7. For each unprocessed meeting:
    ├─ Click meeting → Download transcript
    ├─ Save to temp directory
    ├─ Match to khal calendar event (±15 min window)
    ├─ Classify meeting → Find person folder
    ├─ AI analyze transcript (GPT-4o-mini)
    ├─ AI generate Post-Meeting Summary
    ├─ Save transcript to {person}/attachments/
    ├─ Update Obsidian note with summary
    └─ Mark as processed in cache
    ↓
8. Trigger meeting-prep.sh (Story 4-1)
    ↓
9. Log summary, send Telegram success notification
```

### Key Technical Strategies

**1. Anti-Detection Browser Automation**
- Use `playwright-stealth` to avoid bot detection
- Undetected Chromium with realistic user-agent
- Cookie-based authentication (no username/password)
- Random delays between actions (500-2000ms)

**2. Idempotent Processing**
- Cache file tracks processed meeting IDs
- Safe to re-run hourly without duplicates
- Failed matches saved separately for manual review

**3. Graceful Degradation**
- Auth failures → Telegram alert, retry next hour
- Calendar match failures → Save to failed_matches
- AI failures → Retry with exponential backoff (max 3)
- Obsidian note missing → Create from template

**4. Cost Optimization**
- GPT-4o-mini for analysis (~$0.01 per transcript)
- Batch processing (up to 5 transcripts per hour)
- Daily budget cap: $0.50 (~50 meetings)

---

## Implementation Stack

### Core Technologies

| Technology | Version | Purpose |
|------------|---------|---------|
| **Python** | 3.11+ | Script automation, AI integration |
| **Playwright** | 1.40.0 | Browser automation |
| **playwright-stealth** | 1.0.6 | Anti-detection for Krisp scraping |
| **Bash** | 5.2+ | Orchestration, LaunchAgent integration |
| **OpenAI API** | GPT-4o-mini | Transcript analysis, summary generation |
| **Telegram Bot API** | 6.9 | Error alerting |
| **khal** | 0.11.2 | Calendar event matching |

### Python Dependencies

```requirements.txt
# Existing (from Story 4-1)
openai==1.12.0
python-dotenv==1.0.0
pyyaml==6.0.1

# NEW for Story 4-2
playwright==1.40.0
playwright-stealth==1.0.6
requests==2.31.0
beautifulsoup4==4.12.2
python-telegram-bot==20.7
```

### External APIs

**OpenAI API (GPT-4o-mini)**
- Model: `gpt-4o-mini` (128k context window)
- Cost: ~$0.01 per transcript (input: 5-10k tokens, output: 1k tokens)
- Rate limits: 10,000 requests/day
- Timeout: 30 seconds

**Telegram Bot API**
- Alert-only (no message polling)
- Rate limits: 30 messages/second
- Free tier: Unlimited messages

**Krisp.ai**
- No official API (web scraping)
- Authentication: Cookie-based session
- Rate limits: Unknown (use 3-5 second delays)

---

## Technical Details

### 1. Browser Automation with Playwright

**Cookie Management:**
```python
# config/sketchybar/helpers/krisp-download-transcripts.py
from playwright.sync_api import sync_playwright
from playwright_stealth import stealth_sync
import json
from pathlib import Path

def load_krisp_cookies():
    """Load cookies from vault config"""
    cookie_file = Path.home() / "Library/Mobile Documents/iCloud~md~obsidian/Documents/U/claude-obsidian/config/krisp-cookies.json"

    if not cookie_file.exists():
        raise FileNotFoundError(f"Krisp cookies not found: {cookie_file}")

    with open(cookie_file) as f:
        return json.load(f)

def test_krisp_auth(cookies):
    """Validate cookies before full automation"""
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context()

        # Load cookies
        for cookie in cookies:
            context.add_cookies([cookie])

        page = context.new_page()
        stealth_sync(page)  # Apply anti-detection

        # Test auth by visiting meetings page
        response = page.goto("https://app.krisp.ai/meetings", wait_until="networkidle")

        if response.status == 401 or "login" in page.url.lower():
            browser.close()
            return False

        browser.close()
        return True
```

**Meeting List Scraping:**
```python
def scrape_krisp_meetings(cookies, hours_back=24):
    """Scrape meeting list from Krisp dashboard"""
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=[
                '--disable-blink-features=AutomationControlled',
                '--disable-dev-shm-usage'
            ]
        )

        context = browser.new_context(
            user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
        )

        for cookie in cookies:
            context.add_cookies([cookie])

        page = context.new_page()
        stealth_sync(page)

        page.goto("https://app.krisp.ai/meetings", wait_until="domcontentloaded")
        page.wait_for_timeout(2000)  # Random delay

        # Scrape meeting elements (adjust selectors based on actual DOM)
        meetings = page.query_selector_all('.meeting-item')

        meeting_data = []
        for meeting in meetings:
            meeting_data.append({
                'id': meeting.get_attribute('data-meeting-id'),
                'title': meeting.query_selector('.meeting-title').inner_text(),
                'timestamp': meeting.query_selector('.meeting-time').inner_text(),
                'download_button': meeting.query_selector('.download-transcript-btn')
            })

        browser.close()
        return meeting_data
```

**Transcript Download:**
```python
def download_transcript(meeting_id, download_button, cookies):
    """Click download button and save transcript"""
    with sync_playwright() as p:
        # Re-launch browser for each download (safer)
        browser = p.chromium.launch(headless=True)
        context = browser.new_context()

        for cookie in cookies:
            context.add_cookies([cookie])

        page = context.new_page()
        stealth_sync(page)

        # Navigate to meeting detail page
        page.goto(f"https://app.krisp.ai/meeting/{meeting_id}")
        page.wait_for_timeout(1500)

        # Click download button
        with page.expect_download() as download_info:
            download_button.click()

        download = download_info.value

        # Save to temp directory
        temp_path = Path(f"/tmp/krisp-transcript-{meeting_id}.txt")
        download.save_as(temp_path)

        browser.close()
        return temp_path
```

### 2. Calendar Matching Logic

```python
# config/sketchybar/helpers/krisp-match-meetings.py
import re
from datetime import datetime, timedelta
import subprocess
import json

def parse_krisp_filename(filename):
    """
    Parse Krisp transcript filename
    Examples:
      - 03_59_pm_-_slack_meeting_october_31_transcript.txt
      - 12_01-PM---Slack-meeting-June-3-103ba1e1b5aa47c3b57704586455c11c-transcript.txt
    """
    pattern = r'(\d{2})_(\d{2})[-_]([ap]m).*?([a-z]+)[-_]meeting[-_]([a-z]+)[-_](\d{1,2})'
    match = re.search(pattern, filename.lower())

    if not match:
        return None

    hour, minute, period, source, month, day = match.groups()

    # Convert to 24-hour
    hour = int(hour)
    if period == 'pm' and hour != 12:
        hour += 12
    elif period == 'am' and hour == 12:
        hour = 0

    return {
        'time': f"{hour:02d}:{minute}",
        'month': month,
        'day': int(day),
        'source': source
    }

def get_khal_events(date_str):
    """Get calendar events from khal for specific date"""
    result = subprocess.run(
        ['khal', 'list', date_str, '1d', '--format', '{start-time} {title}'],
        capture_output=True,
        text=True
    )

    events = []
    for line in result.stdout.strip().split('\n'):
        if line:
            time, title = line.split(' ', 1)
            events.append({'time': time, 'title': title})

    return events

def match_transcript_to_calendar(transcript_meta, year=2025):
    """Match Krisp transcript to khal calendar event"""
    # Parse month name to number
    month_map = {
        'january': 1, 'february': 2, 'march': 3, 'april': 4,
        'may': 5, 'june': 6, 'july': 7, 'august': 8,
        'september': 9, 'october': 10, 'november': 11, 'december': 12
    }
    month_num = month_map[transcript_meta['month']]

    meeting_dt = datetime(
        year, month_num, transcript_meta['day'],
        int(transcript_meta['time'].split(':')[0]),
        int(transcript_meta['time'].split(':')[1])
    )

    # Get calendar events for that day
    date_str = meeting_dt.strftime('%Y-%m-%d')
    khal_events = get_khal_events(date_str)

    # Find events within ±15 min window
    window_start = meeting_dt - timedelta(minutes=15)
    window_end = meeting_dt + timedelta(minutes=15)

    candidates = []
    for event in khal_events:
        event_time = datetime.strptime(f"{date_str} {event['time']}", '%Y-%m-%d %H:%M')
        if window_start <= event_time <= window_end:
            candidates.append({
                'calendar_event': event,
                'time_diff': abs((event_time - meeting_dt).total_seconds())
            })

    # Sort by time difference
    candidates.sort(key=lambda x: x['time_diff'])

    if not candidates:
        return None, 'no_match'

    if len(candidates) == 1:
        return candidates[0]['calendar_event'], 'high_confidence'

    # Multiple matches - try source disambiguation
    for candidate in candidates:
        if transcript_meta['source'] in candidate['calendar_event']['title'].lower():
            return candidate['calendar_event'], 'medium_confidence'

    # Return closest match but flag for review
    return candidates[0]['calendar_event'], 'manual_review_needed'
```

### 3. AI Transcript Analysis

```python
# config/sketchybar/helpers/krisp-analyze-transcript.py
from openai import OpenAI
import json
from pathlib import Path
import os

def analyze_transcript(transcript_path, meeting_context):
    """
    Use GPT-4o-mini to analyze transcript and generate summary

    Args:
        transcript_path: Path to transcript.txt file
        meeting_context: Dict with calendar_event, person_name, company

    Returns:
        Dict with discussion_highlights, action_items, next_topics
    """
    client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))

    # Read transcript
    with open(transcript_path) as f:
        transcript_text = f.read()

    # Build prompt
    prompt = f"""You are analyzing a meeting transcript to generate a concise post-meeting summary.

**Meeting Context:**
- Participants: {meeting_context.get('person_name', 'Unknown')}, Jeff Hamersly
- Company: {meeting_context.get('company', 'Unknown')}
- Meeting Type: {meeting_context.get('meeting_type', '1-on-1')}
- Date: {meeting_context.get('date')}

**Transcript:**
{transcript_text}

**Instructions:**
Generate a structured summary with the following sections:

1. **Discussion Highlights** (3-5 bullet points)
   - Main topics covered
   - Key decisions made
   - Important information shared

2. **Action Items** (per person)
   - Format: "- [ ] Action item description (Due: YYYY-MM-DD)"
   - Assign to specific person: [[PersonName]] or [[Jeff Hamersly]]
   - Extract only clear commitments with deadlines

3. **Topics to Review Next Time** (2-4 bullet points)
   - Open questions
   - Pending decisions
   - Follow-up discussions needed

4. **Related Context** (optional)
   - Mentions of projects, people, or documents
   - Format as Obsidian wikilinks: [[ProjectName]] or [[PersonName]]

**Output Format:**
Return JSON with this structure:
{{
  "discussion_highlights": ["point 1", "point 2", ...],
  "action_items": {{
    "person_name": ["- [ ] action 1", "- [ ] action 2"],
    "Jeff Hamersly": ["- [ ] action 3"]
  }},
  "topics_next_time": ["topic 1", "topic 2", ...],
  "related_context": ["[[Project]]", "[[Person]]", ...]
}}

Be concise. Focus on actionable information."""

    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a meeting notes assistant. Generate structured, actionable summaries."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.3,
            max_tokens=1500,
            timeout=30
        )

        content = response.choices[0].message.content

        # Parse JSON response
        analysis = json.loads(content)

        return analysis

    except Exception as e:
        raise Exception(f"AI analysis failed: {str(e)}")
```

### 4. Obsidian Note Update

```python
# config/sketchybar/helpers/krisp-update-note.py
from pathlib import Path
from datetime import datetime

def update_meeting_note(note_path, analysis, transcript_relative_path, meeting_meta):
    """
    Update Obsidian meeting note with Post-Meeting Summary

    Args:
        note_path: Path to meeting note (e.g., 2024-11-02 1on1 with Kyle.md)
        analysis: Dict from analyze_transcript()
        transcript_relative_path: Relative path to transcript (e.g., attachments/2024-11-02-kyle-slack-transcript.txt)
        meeting_meta: Dict with meeting duration, processed timestamp
    """
    if not note_path.exists():
        raise FileNotFoundError(f"Meeting note not found: {note_path}")

    # Read existing note
    with open(note_path) as f:
        existing_content = f.read()

    # Build Post-Meeting Summary section
    post_meeting_summary = f"""
## 📝 Post-Meeting Summary
*Auto-generated from transcript analysis*

### 🎯 Discussion Highlights
"""

    for highlight in analysis['discussion_highlights']:
        post_meeting_summary += f"- {highlight}\n"

    post_meeting_summary += "\n### ✅ Action Items Captured\n"

    for person, items in analysis['action_items'].items():
        post_meeting_summary += f"\n**[[{person}]]:**\n"
        for item in items:
            post_meeting_summary += f"{item}\n"

    post_meeting_summary += "\n### 💡 Topics to Review Next Time\n"

    for topic in analysis['topics_next_time']:
        post_meeting_summary += f"- {topic}\n"

    if analysis.get('related_context'):
        post_meeting_summary += "\n### 🔗 Related Context\n"
        for context in analysis['related_context']:
            post_meeting_summary += f"- {context}\n"

    post_meeting_summary += f"""
---
**Original Transcript:** [[{transcript_relative_path}|View Transcript]]
**Meeting Duration:** {meeting_meta.get('duration', 'Unknown')}
**Transcript Processed:** {datetime.now().strftime('%Y-%m-%d %H:%M')}
"""

    # Check if Post-Meeting Summary already exists
    if "## 📝 Post-Meeting Summary" in existing_content:
        # Replace existing summary
        parts = existing_content.split("## 📝 Post-Meeting Summary")
        before = parts[0]

        # Find next section or end of file
        after_parts = parts[1].split("\n## ")
        if len(after_parts) > 1:
            after = "\n## " + after_parts[1]
        else:
            after = ""

        updated_content = before + post_meeting_summary + after
    else:
        # Append to end of file
        updated_content = existing_content.rstrip() + "\n\n" + post_meeting_summary

    # Write updated note
    with open(note_path, 'w') as f:
        f.write(updated_content)

    return True
```

### 5. Telegram Error Alerting

```python
# Integrated into krisp-orchestrator.sh and Python scripts

def send_telegram_alert(message, config_path=None):
    """Send Telegram notification"""
    import requests
    import json
    from pathlib import Path

    if not config_path:
        config_path = Path.home() / "Library/Mobile Documents/iCloud~md~obsidian/Documents/U/claude-obsidian/config/telegram-bot.json"

    if not config_path.exists():
        print(f"WARNING: Telegram config not found at {config_path}")
        return False

    with open(config_path) as f:
        bot = json.load(f)

    url = f"https://api.telegram.org/bot{bot['token']}/sendMessage"

    try:
        response = requests.post(url, json={
            'chat_id': bot['chat_id'],
            'text': message,
            'parse_mode': 'Markdown'
        }, timeout=10)

        response.raise_for_status()
        return True

    except Exception as e:
        print(f"Telegram alert failed: {str(e)}")
        return False

# Usage examples:
# send_telegram_alert("🚨 *Krisp Auth Failed*\n\nCookie expired. Update krisp-cookies.json")
# send_telegram_alert("✅ *Krisp Automation Success*\n\n5 transcripts processed, 5 notes updated")
```

### 6. Orchestration Script

```bash
#!/bin/bash
# config/sketchybar/helpers/krisp-orchestrator.sh
# Main orchestration script for hourly Krisp transcript automation

set -euo pipefail

# Configuration
SCRIPT_DIR="$HOME/.config/sketchybar/helpers"
VENV_PATH="$HOME/.config/sketchybar/venv"
LOG_FILE="$HOME/.config/sketchybar/logs/krisp-automation.log"
VAULT_PATH="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/U"
CACHE_DIR="$VAULT_PATH/claude-obsidian/cache"

# Source .env
if [ -f "$HOME/repos/02_personal/dotfiles/.env" ]; then
    source "$HOME/repos/02_personal/dotfiles/.env"
elif [ -f "$HOME/dotfiles/.env" ]; then
    source "$HOME/dotfiles/.env"
else
    echo "ERROR: .env file not found" | tee -a "$LOG_FILE"
    exit 1
fi

# Activate Python venv
source "$VENV_PATH/bin/activate"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========================================"
log "Krisp Transcript Automation - Starting"
log "========================================"

# Step 1: Test Krisp Auth
log "Testing Krisp authentication..."
if ! python3 "$SCRIPT_DIR/krisp-download-transcripts.py" --test-auth; then
    log "ERROR: Krisp authentication failed"
    python3 -c "
from krisp_update_note import send_telegram_alert
send_telegram_alert('🚨 *Krisp Auth Failed*\n\nCookie expired. Update manually:\n1. Export cookies from browser\n2. Save to: \`krisp-cookies.json\`\n3. Script retries next hour')
"
    exit 1
fi

log "✓ Authentication successful"

# Step 2: Download new transcripts
log "Downloading new transcripts..."
TRANSCRIPTS=$(python3 "$SCRIPT_DIR/krisp-download-transcripts.py" --download-new)
TRANSCRIPT_COUNT=$(echo "$TRANSCRIPTS" | jq '. | length')

log "Downloaded $TRANSCRIPT_COUNT new transcripts"

if [ "$TRANSCRIPT_COUNT" -eq 0 ]; then
    log "No new transcripts to process. Exiting."
    exit 0
fi

# Step 3: Process each transcript
log "Processing transcripts..."
PROCESSED=0
FAILED=0

for row in $(echo "$TRANSCRIPTS" | jq -r '.[] | @base64'); do
    _jq() {
        echo "$row" | base64 --decode | jq -r "$1"
    }

    MEETING_ID=$(_jq '.meeting_id')
    TEMP_PATH=$(_jq '.temp_path')

    log "Processing meeting: $MEETING_ID"

    # Match to calendar
    MATCH_RESULT=$(python3 "$SCRIPT_DIR/krisp-match-meetings.py" --transcript "$TEMP_PATH")

    if [ "$(echo "$MATCH_RESULT" | jq -r '.match_status')" = "no_match" ]; then
        log "  ✗ No calendar match found for $MEETING_ID"
        FAILED=$((FAILED + 1))
        continue
    fi

    CALENDAR_EVENT=$(echo "$MATCH_RESULT" | jq -r '.calendar_event')
    PERSON_NAME=$(echo "$MATCH_RESULT" | jq -r '.person_name')
    PERSON_FOLDER=$(echo "$MATCH_RESULT" | jq -r '.person_folder')

    log "  ✓ Matched to: $PERSON_NAME"

    # Analyze transcript with AI
    log "  Analyzing transcript with AI..."
    ANALYSIS=$(python3 "$SCRIPT_DIR/krisp-analyze-transcript.py" \
        --transcript "$TEMP_PATH" \
        --person "$PERSON_NAME" \
        --calendar-event "$CALENDAR_EVENT")

    if [ $? -ne 0 ]; then
        log "  ✗ AI analysis failed"
        FAILED=$((FAILED + 1))
        continue
    fi

    log "  ✓ Analysis complete"

    # Save transcript to person folder
    TRANSCRIPT_DATE=$(echo "$MATCH_RESULT" | jq -r '.meeting_date')
    TRANSCRIPT_SLUG=$(echo "$PERSON_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    TRANSCRIPT_FILENAME="$TRANSCRIPT_DATE-$TRANSCRIPT_SLUG-transcript.txt"
    TRANSCRIPT_PATH="$PERSON_FOLDER/attachments/$TRANSCRIPT_FILENAME"

    mkdir -p "$PERSON_FOLDER/attachments"
    cp "$TEMP_PATH" "$TRANSCRIPT_PATH"

    log "  ✓ Saved transcript to: $TRANSCRIPT_PATH"

    # Update Obsidian note
    NOTE_PATH=$(echo "$MATCH_RESULT" | jq -r '.note_path')

    log "  Updating Obsidian note..."
    python3 "$SCRIPT_DIR/krisp-update-note.py" \
        --note "$NOTE_PATH" \
        --analysis "$ANALYSIS" \
        --transcript "attachments/$TRANSCRIPT_FILENAME"

    if [ $? -ne 0 ]; then
        log "  ✗ Note update failed"
        FAILED=$((FAILED + 1))
        continue
    fi

    log "  ✓ Note updated successfully"

    # Mark as processed
    python3 -c "
import json
from pathlib import Path

cache_file = Path('$CACHE_DIR/processed-meetings.json')
cache = json.loads(cache_file.read_text()) if cache_file.exists() else {'processed_meetings': []}

cache['processed_meetings'].append({
    'meeting_id': '$MEETING_ID',
    'processed_at': '$(date -u +%Y-%m-%dT%H:%M:%S)Z',
    'person': '$PERSON_NAME',
    'note_path': '$NOTE_PATH'
})

cache_file.write_text(json.dumps(cache, indent=2))
"

    PROCESSED=$((PROCESSED + 1))

    # Cleanup temp file
    rm "$TEMP_PATH"
done

log "========================================"
log "Processing complete: $PROCESSED success, $FAILED failed"
log "========================================"

# Step 4: Trigger meeting prep (Story 4-1)
if [ "$PROCESSED" -gt 0 ]; then
    log "Triggering meeting prep workflow..."
    bash "$SCRIPT_DIR/meeting-prep.sh" || log "WARNING: Meeting prep failed"
fi

# Step 5: Send success notification
python3 -c "
from krisp_update_note import send_telegram_alert
send_telegram_alert('✅ *Krisp Automation Success*\n\n$PROCESSED transcripts processed\n$FAILED failed')
"

log "Krisp automation complete"
exit 0
```

---

## Development Setup

### Prerequisites

1. **Python 3.11+** installed
2. **Playwright browsers** installed
3. **OpenAI API key** with GPT-4o-mini access
4. **Telegram Bot** created and configured
5. **Obsidian vault** accessible at expected path
6. **khal** installed and configured

### Installation Steps

```bash
# 1. Activate Python virtual environment
source ~/.config/sketchybar/venv/bin/activate

# 2. Install new dependencies
pip install playwright==1.40.0 playwright-stealth==1.0.6 requests==2.31.0 beautifulsoup4==4.12.2 python-telegram-bot==20.7

# 3. Install Playwright browsers
playwright install chromium

# 4. Create configuration directories
mkdir -p ~/Library/Mobile\ Documents/iCloud~md~obsidian/Documents/U/claude-obsidian/config
mkdir -p ~/Library/Mobile\ Documents/iCloud~md~obsidian/Documents/U/claude-obsidian/cache

# 5. Configure environment variables in .env
cat >> ~/dotfiles/.env << EOF

# Krisp Automation (Story 4-2)
KRISP_LAUNCHAGENT=TRUE  # REQUIRED: Enable LaunchAgent installation (set to FALSE or omit to disable)
KRISP_COOKIES_PATH=~/Library/Mobile Documents/iCloud~md~obsidian/Documents/U/claude-obsidian/config/krisp-cookies.json
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here
EOF

# Note: KRISP_LAUNCHAGENT must be set to TRUE in .env for install.sh to offer LaunchAgent installation
# This is a safety mechanism - LaunchAgent won't work without proper Krisp auth setup anyway

# 6. Export Krisp cookies from browser
# - Install EditThisCookie extension
# - Visit app.krisp.ai/meetings (while logged in)
# - Export cookies as JSON
# - Save to: ~/Library/Mobile Documents/iCloud~md~obsidian/Documents/U/claude-obsidian/config/krisp-cookies.json

# 7. Create Telegram bot
# - Message @BotFather on Telegram
# - Send /newbot and follow instructions
# - Copy bot token to .env (TELEGRAM_BOT_TOKEN)
# - Message your bot to get chat_id
# - Use https://api.telegram.org/bot<TOKEN>/getUpdates to find chat_id
# - Add chat_id to .env (TELEGRAM_CHAT_ID)

# 8. Test authentication
python3 ~/.config/sketchybar/helpers/krisp-download-transcripts.py --test-auth

# 9. Install LaunchAgent
cp ~/dotfiles/Library/LaunchAgents/com.user.krisp-automation.plist ~/Library/LaunchAgents/
launchctl load -w ~/Library/LaunchAgents/com.user.krisp-automation.plist

# 10. Verify LaunchAgent running
launchctl list | grep krisp-automation
```

---

## Implementation Guide

### Story 1: Browser Automation Setup
**Goal:** Establish Playwright + stealth infrastructure with cookie auth

1. Install Playwright and playwright-stealth
2. Create `krisp-download-transcripts.py` with cookie loading
3. Implement `test_krisp_auth()` function
4. Test with real Krisp cookies (manual export from browser)
5. Add Telegram alert on auth failure
6. Verify undetected browser behavior

**Acceptance Criteria:**
- Playwright launches undetected Chrome
- Cookies load from JSON file
- Auth test passes with valid cookies
- Auth test fails gracefully with expired cookies
- Telegram alert sent on failure

---

### Story 2: Krisp Web Scraping
**Goal:** Scrape meeting list and download transcripts

1. Implement `scrape_krisp_meetings()` function
2. Parse meeting list HTML (adjust selectors based on actual DOM)
3. Implement `download_transcript()` for each meeting
4. Save transcripts to temp directory with meeting ID
5. Parse transcript filename for date/time metadata
6. Filter meetings already processed (check cache)

**Acceptance Criteria:**
- Meeting list scraped correctly (last 24 hours)
- Transcripts download without errors
- Filename parsing extracts date/time/source correctly
- Duplicate meetings skipped (already in cache)
- Random delays prevent rate limiting

---

### Story 3: Meeting Matching & Obsidian Integration
**Goal:** Match transcripts to calendar, analyze with AI, update notes

1. Implement `parse_krisp_filename()` with regex
2. Implement `get_khal_events()` to fetch calendar
3. Implement `match_transcript_to_calendar()` with ±15 min window
4. Classify meeting type → find person folder (reuse Story 4-1 logic)
5. Implement `analyze_transcript()` with GPT-4o-mini
6. Implement `update_meeting_note()` to add Post-Meeting Summary
7. Save transcript to `{person}/attachments/` with standardized naming
8. Update cache with processed meeting ID

**Acceptance Criteria:**
- Calendar matching works with ±15 min tolerance
- Source name used for disambiguation
- AI analysis generates structured summary
- Obsidian notes updated with new section
- Transcripts saved to correct person folder
- Cache updated to prevent reprocessing

---

### Story 4: Scheduling & Automation
**Goal:** Hourly LaunchAgent orchestrates full workflow

1. Create `krisp-orchestrator.sh` bash script
2. Implement 6-step workflow (auth → download → match → analyze → update → notify)
3. Add comprehensive logging to `krisp-automation.log`
4. Create LaunchAgent plist (hourly schedule)
5. Integrate with existing `meeting-prep.sh` (Story 4-1)
6. Test end-to-end with real meetings

**Acceptance Criteria:**
- LaunchAgent runs every hour
- Full workflow completes successfully
- Errors logged with details
- Telegram notifications sent
- Meeting prep workflow triggered after transcript processing
- No duplicate processing

---

### Story 5: Error Handling & Monitoring
**Goal:** Graceful degradation and alerting for all failure modes

1. Add retry logic with exponential backoff (AI failures)
2. Handle missing person folders (save to Inbox)
3. Handle missing Obsidian notes (create from template)
4. Handle calendar match failures (save to failed_matches cache)
5. Add Telegram alerts for all failure types
6. Create monitoring dashboard (optional - manual log review)

**Acceptance Criteria:**
- Auth failures → Telegram alert, exit gracefully
- AI failures → Retry 3x with backoff, then alert
- Person not found → Save to Inbox, log warning
- Calendar mismatch → Save to failed_matches, alert
- All errors logged with context
- No crashes from unexpected errors

---

## Testing Approach

### Unit Testing

**Test 1: Cookie Loading**
```python
# Test valid cookie format
cookies = load_krisp_cookies()
assert isinstance(cookies, list)
assert 'name' in cookies[0]
assert 'value' in cookies[0]
```

**Test 2: Filename Parsing**
```python
# Test various Krisp filename formats
meta = parse_krisp_filename("03_59_pm_-_slack_meeting_october_31_transcript.txt")
assert meta['time'] == '15:59'
assert meta['month'] == 'october'
assert meta['day'] == 31
assert meta['source'] == 'slack'
```

**Test 3: Calendar Matching**
```python
# Test ±15 min window
transcript_meta = {'time': '15:59', 'month': 'october', 'day': 31}
calendar_event = {'time': '16:05', 'title': 'Slack Meeting'}
match, confidence = match_transcript_to_calendar(transcript_meta, [calendar_event])
assert match is not None
assert confidence == 'high_confidence'
```

### Integration Testing

**Test 1: Auth Test**
```bash
# With valid cookies
python3 krisp-download-transcripts.py --test-auth
# Expected: Exit 0, "Authentication successful"

# With expired cookies
# Expected: Exit 1, Telegram alert sent
```

**Test 2: End-to-End (Manual)**
1. Place test transcript in `/tmp/test-transcript.txt`
2. Create matching calendar event in khal
3. Run orchestrator: `bash krisp-orchestrator.sh`
4. Verify:
   - Transcript saved to person folder
   - Obsidian note updated
   - Cache updated
   - Telegram success notification

**Test 3: Failure Scenarios**
- Expired cookies → Telegram alert, no crash
- Missing person → Saved to Inbox
- AI API down → Retries 3x, then alerts
- Calendar mismatch → Saved to failed_matches

### Performance Testing

**Target Metrics:**
- Auth test: < 5 seconds
- Meeting list scrape: < 10 seconds
- Transcript download: < 5 seconds per meeting
- AI analysis: 10-20 seconds
- Note update: < 1 second
- **Total per meeting:** 20-40 seconds
- **Hourly batch (5 meetings):** < 3 minutes

**Cost Monitoring:**
- Log OpenAI API usage
- Target: $0.01 per transcript
- Daily cap: $0.50 (50 meetings max)

---

## Deployment Strategy

### Initial Deployment

1. **Manual Testing Phase (Week 1)**
   - Run orchestrator manually: `bash krisp-orchestrator.sh`
   - Process 3-5 test transcripts
   - Verify note quality
   - Adjust AI prompts if needed

2. **Hourly Automation (Week 2)**
   - Install LaunchAgent
   - Monitor logs daily
   - Fix any auth/scraping issues

3. **Monitoring & Optimization (Week 3+)**
   - Review Telegram alerts
   - Optimize AI prompts for better summaries
   - Tune calendar matching thresholds

### Rollback Plan

If automation fails repeatedly:

```bash
# 1. Disable LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.user.krisp-automation.plist

# 2. Check logs
tail -100 ~/.config/sketchybar/logs/krisp-automation.log

# 3. Fix issue (cookie refresh, code fix, etc.)

# 4. Test manually
bash ~/.config/sketchybar/helpers/krisp-orchestrator.sh

# 5. Re-enable if successful
launchctl load -w ~/Library/LaunchAgents/com.user.krisp-automation.plist
```

### LaunchAgent Configuration

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.krisp-automation</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/v/.config/sketchybar/helpers/krisp-orchestrator.sh</string>
    </array>

    <key>StartInterval</key>
    <integer>3600</integer> <!-- Run every hour -->

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>

    <key>StandardOutPath</key>
    <string>/Users/v/.config/sketchybar/logs/krisp-automation-stdout.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/v/.config/sketchybar/logs/krisp-automation-stderr.log</string>

    <key>RunAtLoad</key>
    <false/> <!-- Don't run immediately at login -->

    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
```

### Monitoring Commands

```bash
# Check LaunchAgent status
launchctl list | grep krisp-automation

# View logs
tail -f ~/.config/sketchybar/logs/krisp-automation.log

# View processed meetings cache
cat ~/Library/Mobile\ Documents/iCloud~md~obsidian/Documents/U/claude-obsidian/cache/processed-meetings.json | jq

# View failed matches
cat ~/Library/Mobile\ Documents/iCloud~md~obsidian/Documents/U/claude-obsidian/cache/processed-meetings.json | jq '.failed_matches'

# Manual trigger
launchctl start com.user.krisp-automation

# Disable
launchctl unload ~/Library/LaunchAgents/com.user.krisp-automation.plist

# Re-enable
launchctl load -w ~/Library/LaunchAgents/com.user.krisp-automation.plist
```

---

## Security Considerations

1. **Cookie Security**
   - Store in vault directory (iCloud encrypted)
   - Never log cookie values
   - Refresh every 30 days (manual)

2. **API Keys**
   - Store in `.env` (git-ignored)
   - Never commit to repository
   - Rotate if compromised

3. **Transcript Privacy**
   - Transcripts sent to OpenAI API (review ToS)
   - Consider using local LLM for sensitive meetings
   - Transcripts stored in encrypted iCloud vault

4. **Rate Limiting**
   - Random delays (500-2000ms) prevent detection
   - Max 5 transcripts per hour (safe limit)
   - Monitor for HTTP 429 (too many requests)

---

## Cost Analysis

### Per-Meeting Costs

| Component | Cost |
|-----------|------|
| Playwright browser automation | Free |
| OpenAI GPT-4o-mini analysis | $0.01 |
| Telegram notifications | Free |
| **Total per meeting** | **$0.01** |

### Monthly Projections

Assuming 10 meetings/day with transcripts:
- Daily: 10 meetings × $0.01 = **$0.10**
- Monthly: 10 × 30 = 300 meetings = **$3.00**
- Yearly: 300 × 12 = 3,600 meetings = **$36.00**

**Budget:** $50/month cap (5,000 meetings max)

---

## Future Enhancements

1. **Auto-cookie refresh** - Playwright session persistence
2. **Local LLM option** - Privacy-focused alternative (Ollama)
3. **Speaker diarization** - Better action item attribution
4. **Meeting insights dashboard** - Aggregate metrics over time
5. **Slack integration** - Post summaries to Slack channels
6. **Multi-source transcripts** - Otter.ai, Fireflies.ai, etc.
7. **Obsidian Canvas view** - Visual meeting relationship mapping

---

**Generated:** 2025-11-02
**Status:** Ready for Story Generation (Level 1 - 5 stories)
