# Story: Production Deployment & Monitoring

**Epic:** 4.2 - Krisp Transcript Automation
**Story Points:** 3
**Priority:** High
**Status:** ready-for-dev

## Story

As a macOS user with automated transcript processing,
I want reliable hourly execution with comprehensive error handling and alerting,
so that the automation runs unattended and I'm notified of any issues.

## Acceptance Criteria

### AC #1: Orchestration Script with 6-Step Workflow
**Given** Stories 1 & 2 scripts are functional
**When** running krisp-orchestrator.sh
**Then** it should execute in exact sequence:

1. **Auth Test**
   - Call krisp-download-transcripts.py --test-auth
   - If fails: Send Telegram alert, exit with code 1
   - If succeeds: Continue to step 2

2. **Download Transcripts**
   - Call krisp-download-transcripts.py --download-new
   - Parse JSON output (array of meeting objects)
   - Count: TRANSCRIPT_COUNT
   - If 0: Log "No new transcripts", exit with code 0
   - If > 0: Continue to step 3

3. **Process Each Transcript** (loop):
   - For each meeting in TRANSCRIPTS:
     - Match to calendar (krisp-match-meetings.py)
     - If no_match: Log warning, add to failed_matches, continue
     - Classify meeting (reuse Story 4-1)
     - Find person folder (reuse Story 4-1)
     - Analyze transcript (krisp-analyze-transcript.py)
     - Update note (krisp-update-note.py)
     - Organize transcript file
     - Mark as processed in cache
     - Track: PROCESSED++ or FAILED++

4. **Trigger Meeting Prep**
   - If PROCESSED > 0: Call meeting-prep.sh (Story 4-1)
   - Else: Skip

5. **Send Summary Notification**
   - Send Telegram message: "✅ Krisp Automation Success\n\n{PROCESSED} transcripts processed\n{FAILED} failed"

6. **Clean Up**
   - Delete temp files from /tmp/
   - Log final summary
   - Exit with code 0

**Script requirements:**
- Bash 5.2+ with `set -euo pipefail`
- Activates Python venv before any Python calls
- Sources .env for environment variables
- Logs all output to krisp-automation.log
- Returns appropriate exit codes (0=success, 1=failure)

### AC #2: Comprehensive Logging System
**Given** the orchestration script running
**When** logging events
**Then** it should:
- Write to: `~/.config/sketchybar/logs/krisp-automation.log`
- Log format: `[YYYY-MM-DD HH:MM:SS] message`
- Log levels:
  - INFO: Normal operations (e.g., "Downloaded 5 transcripts")
  - WARNING: Non-critical issues (e.g., "No calendar match for meeting X")
  - ERROR: Critical failures (e.g., "Auth test failed")
- Include context in logs:
  - Meeting ID for per-meeting operations
  - Error messages with full stack trace
  - Timing info (e.g., "Processing completed in 45s")
- Rotate logs:
  - Keep last 30 days
  - Max 10 MB per file
  - Compress old logs

**Log helper function:**
```bash
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}
```

### AC #3: LaunchAgent Hourly Scheduling
**Given** a properly configured LaunchAgent plist
**When** installed at `~/Library/LaunchAgents/com.user.krisp-automation.plist`
**Then** it should:
- Run krisp-orchestrator.sh every 3600 seconds (1 hour)
- Set explicit PATH: `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`
- Set RunAtLoad: false (don't run immediately at login)
- Redirect stdout to: `~/.config/sketchybar/logs/krisp-automation-stdout.log`
- Redirect stderr to: `~/.config/sketchybar/logs/krisp-automation-stderr.log`
- Persist across system restarts
- Run even when user not logged in (optional)

**Installation:**
```bash
cp com.user.krisp-automation.plist ~/Library/LaunchAgents/
launchctl load -w ~/Library/LaunchAgents/com.user.krisp-automation.plist
launchctl list | grep krisp-automation  # Verify running
```

**Critical PATH bug prevention:**
- LaunchAgent runs with minimal environment (no Homebrew paths by default)
- MUST set EnvironmentVariables → PATH in plist
- Without PATH: Commands like `khal`, `jq`, `python3` fail with exit code 127

### AC #4: Telegram Success & Failure Notifications
**Given** Telegram bot configured with token and chat_id
**When** automation completes or fails
**Then** it should send notifications:

**Success notification (if PROCESSED > 0):**
```
✅ *Krisp Automation Success*

5 transcripts processed
1 failed

Last run: 2024-11-02 16:30
Next run: 2024-11-02 17:30
```

**Auth failure notification:**
```
🚨 *Krisp Auth Failed*

Session expired. Refresh authentication:

Run this command:
  bash ~/.config/sketchybar/helpers/krisp-refresh-auth.sh

The script will guide you through:
1. Export cookies from browser (EditThisCookie extension)
2. Export localStorage from DevTools console
3. Paste data when prompted
4. Auth test runs automatically

Script retries next hour.

See logs: ~/.config/sketchybar/logs/krisp-automation.log
```

**Error notification (non-auth failures):**
```
⚠️ *Krisp Automation Error*

Error: OpenAI API timeout

Meeting ID: 103ba1e1b5aa47c3b57704586455c11c
See logs for details: ~/.config/sketchybar/logs/krisp-automation.log
```

**Unmatched meeting notification (NEW - from Story 4-2):**
```
🔍 *Krisp Meeting Not Matched*

Could not match Krisp transcript to calendar event:

Title: 08:25 PM - Signal meeting October 31
Time: 2024-10-31 20:25
Meeting ID: 019a3c973e...

Transcript saved to:
~/.config/sketchybar/krisp-transcripts/unmatched/

Action needed: Manual review or update calendar
```

**Requirements:**
- Markdown formatting (parse_mode: 'Markdown')
- Send within 60 seconds of event
- Retry on Telegram API failure (max 3 attempts)
- Don't spam on repeated failures (rate limit: 1 alert per hour for same error type)
- **Unmatched meetings:** Send alert immediately when transcript can't be matched to calendar (Story 4-3 integration)

### AC #5: Integration with Story 4-1 Meeting Prep
**Given** new transcripts processed successfully
**When** triggering meeting-prep.sh
**Then** it should:
- Call: `bash ~/.config/sketchybar/helpers/meeting-prep.sh`
- Run in background (don't block orchestrator)
- Capture exit code but don't fail orchestrator on error
- Log: "Triggered meeting prep workflow" (INFO)
- If meeting-prep fails: Log warning, continue orchestrator
- Don't trigger if PROCESSED = 0 (no new transcripts)

**Integration point:**
- Story 4-1 prep generates notes for UPCOMING meetings
- Story 4-2 automation processes PAST meetings (transcripts)
- Both update same Obsidian notes (prep = before, transcript = after)
- No conflicts expected (different sections of note)

### AC #6: Error Handling & Graceful Degradation
**Given** various failure scenarios during hourly run
**When** errors occur
**Then** it should handle gracefully:

| Scenario | Behavior | Exit Code | Telegram Alert |
|----------|----------|-----------|----------------|
| Auth test fails | Send alert, exit immediately | 1 | Yes (auth failure) |
| No new transcripts | Log info, exit | 0 | No |
| Calendar match fails (unmatched meeting) | Move to unmatched folder, send alert, continue | 0 | **Yes (unmatched meeting)** |
| Person not found | Log error, add to failed_matches, continue | 0 | No (included in summary) |
| AI API timeout | Retry 3x, log error, continue | 0 | No (included in summary) |
| Note update fails | Log error, continue | 0 | No (included in summary) |
| Meeting prep fails | Log warning, continue | 0 | No |
| Telegram alert fails | Log error, continue (don't block workflow) | 0 | No |
| Script crash | stderr logged, exit | 2 | No (manual log review) |

**Graceful degradation principles:**
- Auth failures block entire workflow (can't proceed)
- Per-meeting failures don't block other meetings
- Notification failures don't block workflow
- Always log context for debugging
- Always clean up temp files

### AC #7: Manual Trigger & Testing Commands
**Given** need to test or manually trigger automation
**When** running manual commands
**Then** these should work:

**Manual trigger (full workflow):**
```bash
bash ~/.config/sketchybar/helpers/krisp-orchestrator.sh
```

**Trigger via LaunchAgent:**
```bash
launchctl start com.user.krisp-automation
```

**Check LaunchAgent status:**
```bash
launchctl list | grep krisp-automation
# Should show PID if running, or exit code from last run
```

**View logs:**
```bash
# Orchestrator log
tail -f ~/.config/sketchybar/logs/krisp-automation.log

# Stdout from LaunchAgent
tail -f ~/.config/sketchybar/logs/krisp-automation-stdout.log

# Stderr from LaunchAgent
tail -f ~/.config/sketchybar/logs/krisp-automation-stderr.log
```

**Stop LaunchAgent:**
```bash
launchctl unload ~/Library/LaunchAgents/com.user.krisp-automation.plist
```

**Restart LaunchAgent:**
```bash
launchctl unload ~/Library/LaunchAgents/com.user.krisp-automation.plist
launchctl load -w ~/Library/LaunchAgents/com.user.krisp-automation.plist
```

### AC #8: End-to-End Testing & Validation
**Given** complete automation installed
**When** running end-to-end tests
**Then** validate:

1. **Fresh Install Test:**
   - Install LaunchAgent
   - Export Krisp cookies manually
   - Wait 1 hour (or trigger manually)
   - Verify transcripts downloaded
   - Verify notes updated
   - Verify Telegram notification received

2. **Multiple Meetings Test:**
   - Have 5 meetings with transcripts available
   - Run orchestrator manually
   - Verify all 5 processed
   - Verify each note updated correctly
   - Verify all transcripts organized
   - Verify cache updated with 5 entries
   - Verify no duplicates on re-run

3. **Failure Recovery Test:**
   - Expire cookies (remove cookie file)
   - Wait 1 hour
   - Verify auth failure alert sent
   - Update cookies manually
   - Wait 1 hour
   - Verify processing resumes

4. **Performance Test:**
   - Measure time for 5-meeting batch
   - Target: < 3 minutes total
   - Per meeting breakdown:
     - Download: < 5s
     - Analyze: 10-20s
     - Update: < 1s
   - Verify no memory leaks
   - Verify temp files cleaned up

5. **Cost Monitoring Test:**
   - Process 10 meetings
   - Check OpenAI usage dashboard
   - Verify: ~$0.10 total (10 × $0.01)
   - Verify daily cap not exceeded

## Tasks / Subtasks

### Task 1: Create Orchestration Script
- [ ] **1.1:** Create krisp-orchestrator.sh skeleton (AC: #1)
  - Bash script with set -euo pipefail
  - Define configuration variables (paths, log file)
  - Implement log() helper function
  - Source .env file
  - Activate Python venv

- [ ] **1.2:** Implement 6-step workflow (AC: #1)
  - Step 1: Auth test with exit on failure
  - Step 2: Download transcripts, parse JSON count
  - Step 3: Process loop with error handling per meeting
  - Step 4: Trigger meeting prep (conditional)
  - Step 5: Send Telegram summary
  - Step 6: Cleanup temp files

- [ ] **1.3:** Add comprehensive logging (AC: #2)
  - Log start/end of orchestrator
  - Log each major step
  - Log per-meeting operations
  - Log timing info
  - Log error details with context

### Task 2: Implement Telegram Notifications
- [ ] **2.1:** Add Telegram helper to krisp-update-note.py (AC: #4)
  - Reuse send_telegram_alert() from Story 2
  - Support markdown formatting
  - Add retry logic (3 attempts)
  - Handle Telegram API failures gracefully

- [ ] **2.2:** Implement notification templates (AC: #4)
  - Success template with counts
  - Auth failure template with instructions
  - Error template with context
  - Rate limiting (1 per hour per error type)

- [ ] **2.3:** Test Telegram integration (AC: #4)
  - Test success notification
  - Test auth failure notification
  - Test error notification
  - Verify markdown rendering
  - Verify delivery time < 60s

### Task 3: Create LaunchAgent Configuration
- [ ] **3.1:** Create com.user.krisp-automation.plist (AC: #3)
  - Label: com.user.krisp-automation
  - Program: /bin/bash orchestrator-full-path
  - StartInterval: 3600 (1 hour)
  - EnvironmentVariables: PATH with Homebrew paths
  - StandardOutPath: stdout log file
  - StandardErrorPath: stderr log file
  - RunAtLoad: false

- [ ] **3.2:** Install and test LaunchAgent (AC: #3)
  - Copy plist to ~/Library/LaunchAgents/
  - Load with launchctl
  - Verify shows in launchctl list
  - Trigger manually to test
  - Verify logs created
  - Verify PATH works (khal, jq accessible)

- [ ] **3.3:** Document LaunchAgent management (AC: #7)
  - Add commands to tech-spec
  - Add troubleshooting section
  - Document PATH bug prevention

### Task 4: Implement Error Handling
- [ ] **4.1:** Add per-meeting error handling (AC: #6)
  - Try-catch equivalent in bash (|| continue pattern)
  - Log errors with meeting context
  - Track PROCESSED and FAILED counters
  - Continue to next meeting on failure

- [ ] **4.2:** Add graceful degradation (AC: #6)
  - Auth failures → exit immediately
  - Per-meeting failures → continue
  - Notification failures → log, continue
  - Always clean up temp files

- [ ] **4.3:** Test failure scenarios (AC: #6)
  - Test auth failure → Telegram alert, exit 1
  - Test calendar mismatch → warning, continue
  - Test AI timeout → retry, continue
  - Test note update fail → error, continue
  - Verify exit codes correct

### Task 5: Integrate with Story 4-1
- [ ] **5.1:** Add meeting prep trigger (AC: #5)
  - Check if PROCESSED > 0
  - Call meeting-prep.sh in background
  - Don't block on meeting-prep completion
  - Log success/failure of trigger

- [ ] **5.2:** Test integration (AC: #5)
  - Process transcript
  - Verify meeting prep triggered
  - Verify both workflows update same note
  - Verify no conflicts (different sections)

### Task 6: End-to-End Testing
- [ ] **6.1:** Fresh install test (AC: #8.1)
  - Install LaunchAgent on clean system
  - Export Krisp cookies
  - Wait for hourly trigger or run manually
  - Verify full workflow completes
  - Verify Telegram notification received

- [ ] **6.2:** Multiple meetings test (AC: #8.2)
  - Queue 5 meetings with transcripts
  - Run orchestrator
  - Verify all 5 processed
  - Verify notes updated
  - Verify cache updated
  - Verify no duplicates on re-run

- [ ] **6.3:** Failure recovery test (AC: #8.3)
  - Simulate auth failure (delete cookies)
  - Verify alert sent
  - Restore cookies
  - Verify recovery on next run

- [ ] **6.4:** Performance test (AC: #8.4)
  - Measure 5-meeting batch time
  - Verify < 3 minutes total
  - Monitor memory usage
  - Verify temp file cleanup

- [ ] **6.5:** Cost monitoring test (AC: #8.5)
  - Process 10 meetings
  - Check OpenAI dashboard
  - Verify ~$0.10 total
  - Verify under daily cap

### Task 7: Documentation & Finalization
- [ ] **7.1:** Update CLAUDE.md (AC: #7)
  - Add Krisp Automation section
  - Document architecture (6-step workflow)
  - Add troubleshooting guide
  - Add manual trigger commands
  - Add LaunchAgent management commands

- [ ] **7.2:** Update .env.example (AC: #7)
  - Document TELEGRAM_BOT_TOKEN
  - Document TELEGRAM_CHAT_ID
  - Add Telegram bot setup instructions
  - Add cookie export instructions

- [ ] **7.3:** Create quick-start guide
  - Installation checklist
  - Configuration steps
  - Testing commands
  - Common issues and solutions

## Dev Notes

### Technical Summary

This story creates production-ready automation with comprehensive monitoring and error handling.

**Story Numbering Note:** This is Story 4-4 in sprint-status.yaml (Epic 4, Story 4) but referenced as "Story 3" in epics-krisp-automation.md (Epic 4.2's third story). Both numbering schemes are correct within their contexts.

**Key Technical Decisions:**

1. **Bash orchestration** - Simple, reliable, no additional dependencies
2. **LaunchAgent** - Native macOS scheduling, persists across reboots
3. **Explicit PATH** - Critical for Homebrew tools (khal, jq) to work
4. **Telegram for alerts** - Simple API, instant notifications
5. **Graceful degradation** - Per-meeting failures don't block batch
6. **Comprehensive logging** - Every operation logged with context

**Error handling philosophy:**
- Auth failures are blocking (can't proceed without valid session)
- Per-meeting failures are non-blocking (process what we can)
- Notification failures are non-critical (don't block workflow)
- Always clean up temp files (prevent disk bloat)

**LaunchAgent best practices:**
- Set explicit PATH (Homebrew not in default PATH)
- Redirect stdout/stderr for debugging
- RunAtLoad: false (don't spam on every login)
- StartInterval over StartCalendarInterval (simpler)

### Project Structure Notes

- **Files to create:**
  - `config/sketchybar/helpers/krisp-orchestrator.sh` (main orchestration)
  - `Library/LaunchAgents/com.user.krisp-automation.plist` (hourly scheduler)
  - `.env` (add TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID)
  - `.env.example` (document new variables)

- **Files to modify:**
  - `CLAUDE.md` (add Krisp Automation documentation)
  - `config/sketchybar/logs/` (create log files)

- **Expected test locations:**
  - Manual E2E testing with real Krisp account
  - LaunchAgent testing over 1 week
  - Failure scenario testing (auth, API, filesystem)

- **Estimated effort:** 3 story points (3 days)
  - Day 1: Orchestration script, logging, basic integration
  - Day 2: LaunchAgent setup, Telegram notifications, error handling
  - Day 3: End-to-end testing, documentation, bug fixes

### References

**Source Documents:**

[Source: docs/epics-krisp-automation.md - Story 3: Production Deployment & Monitoring]
[Source: docs/epics-krisp-automation.md - Implementation Sequence → Prerequisites, Delivers, Validation]
[Source: docs/epics-krisp-automation.md - Epic Details → Dependencies, Technical Complexity]

[Source: docs/architecture.md - Symlink-Based Configuration Management]
[Source: docs/architecture.md - Event-Driven Integration patterns]

[Source: docs/tech-spec-krisp-transcript-automation.md - Technical Details → Orchestration Script]
[Source: docs/tech-spec-krisp-transcript-automation.md - Technical Details → Telegram Error Alerting]
[Source: docs/tech-spec-krisp-transcript-automation.md - Deployment Strategy → LaunchAgent Configuration]
[Source: docs/tech-spec-krisp-transcript-automation.md - Implementation Stack → Core Technologies]

**Story Dependencies:**
- **Story 4-2 (Epic Story 1):** Consumes transcript download functionality
- **Story 4-3 (Epic Story 2):** Consumes analysis and note update functionality
- **Story 4-1:** Integrates with meeting prep workflow

**Technical Dependencies:** bash, launchctl, Telegram Bot API, OpenAI API, khal

### Integration Points

**Story 1 + 2 Integration:**
- Orchestrates both stories into cohesive workflow
- Handles errors from both layers
- Provides end-to-end monitoring

**Story 4-1 Integration:**
- Triggers meeting-prep.sh after transcript processing
- Both workflows update same Obsidian notes (different sections)
- No conflicts expected

**System Integration:**
- LaunchAgent for scheduling
- Filesystem for logging
- Telegram for alerting
- OpenAI API via Story 2

### Monitoring & Debugging

**Key log files:**
1. `krisp-automation.log` - Orchestrator main log
2. `krisp-automation-stdout.log` - LaunchAgent stdout
3. `krisp-automation-stderr.log` - LaunchAgent stderr
4. `processed-meetings.json` - Cache of processed meetings

**Debugging workflow:**
1. Check Telegram for alerts
2. Review krisp-automation.log for errors
3. Check cache for failed_matches
4. Review stderr log for script errors
5. Verify LaunchAgent running: `launchctl list | grep krisp`

**Common issues:**
- PATH not set → khal/jq command not found (exit 127)
- Cookie expired → auth failure, Telegram alert
- OpenAI rate limit → retries exhausted, meeting skipped
- Person not found → failed_matches, manual folder creation needed

### Performance Targets

| Metric | Target |
|--------|--------|
| Orchestrator startup | < 2 seconds |
| Full 5-meeting batch | < 3 minutes |
| Log write overhead | < 100ms per entry |
| Telegram notification | < 5 seconds |
| Temp file cleanup | < 1 second |
| Memory footprint | < 100 MB peak |

### Authentication Management (NEW - Story 4-2 Integration)

**Auth File Location:**
- `~/.config/sketchybar/krisp-auth.json` (git-ignored)
- Contains cookies array + localStorage object
- Updated timestamp tracked for expiry monitoring
- Estimated expiry: ~60 days from creation

**Refresh Workflow:**
When auth fails (Telegram alert sent):
1. User runs: `bash ~/.config/sketchybar/helpers/krisp-refresh-auth.sh`
2. Script prompts for:
   - Browser cookies (via EditThisCookie extension)
   - localStorage (via DevTools console: `JSON.stringify(localStorage)`)
3. Script validates JSON format
4. Creates backup of existing auth file
5. Tests authentication automatically
6. Reports success/failure to user

**Key Features:**
- Interactive prompts with clear instructions
- JSON validation before writing
- Automatic backup with timestamp (e.g., `krisp-auth.json.backup-20251102-153000`)
- File permissions set to 600 (owner read/write only)
- Integrated test after refresh

**Security:**
- Auth file excluded from git (`.gitignore`)
- Backup files also excluded
- No credentials in script source code
- File permissions restrict access

### Security Considerations

**Secrets management:**
- TELEGRAM_BOT_TOKEN in .env (git-ignored)
- Krisp auth in `~/.config/sketchybar/krisp-auth.json` (git-ignored, chmod 600)
- OpenAI API key in .env (git-ignored)
- Never log sensitive values

**Process isolation:**
- LaunchAgent runs as user (not root)
- Python venv isolates dependencies
- Bash script runs with restricted permissions

**Attack surface:**
- Telegram bot is send-only (no commands accepted)
- OpenAI API is request-only (no webhooks)
- Krisp auth can be refreshed via helper script (no manual file editing)

### Cost Analysis

**Development cost:** 3 story points (3 days)

**Operational cost (monthly):**
- LaunchAgent: Free
- Telegram: Free
- OpenAI API: $3.00 (from Story 2)
- **Total:** $3.00/month

**Time savings:** 50-75 minutes/week on transcript processing = **$5,000/month value** (at $100/hour)

**ROI:** Still practically infinite

## Dev Agent Record

### Context Reference

- [Story Context XML](4-4-production-deployment-monitoring.context.xml) - Generated 2025-11-02

### Agent Model Used

<!-- Will be populated during dev-story execution -->

### Debug Log References

<!-- Will be populated during dev-story execution -->

### Completion Notes List

<!-- Will be populated during dev-story execution -->

### File List

<!-- Will be populated during dev-story execution -->

---

## Change Log

<!-- Track changes to this story file during development -->

**2025-11-02 - Validation improvements (Auto-fix)**
- Fixed status from "Draft" to "drafted" (workflow compliance)
- Added missing citations: epics-krisp-automation.md, architecture.md
- Enhanced References section with source document structure
- Added story numbering clarification in Technical Summary
- Initialized Change Log section

---

**Created:** 2025-11-02
**Status:** drafted
**Dependencies:** Story 4-2 (transcript download), Story 4-3 (analysis & note update), Story 4-1 (meeting prep)
**Next Action:** Generate story context for production deployment implementation
