# Engineering Backlog

This backlog collects cross-cutting or future action items that emerge from reviews and planning.

Routing guidance:

- Use this file for non-urgent optimizations, refactors, or follow-ups that span multiple stories/epics.
- Must-fix items to ship a story belong in that story's `Tasks / Subtasks`.
- Same-epic improvements may also be captured under the epic Tech Spec `Post-Review Follow-ups` section.

| Date | Story | Epic | Type | Severity | Owner | Status | Notes |
| ---- | ----- | ---- | ---- | -------- | ----- | ------ | ----- |
| 2025-10-29 | 2.4 | 2 | Bug | MEDIUM | TBD | Open | Fix khal PATH in LaunchAgent context - Add EnvironmentVariables key to plist or use absolute path to khal binary. Stale event cleanup currently failing. Related files: sync-calendars.sh:208-212, com.user.calendar-sync.plist |
| 2025-10-29 | 2.4 | 2 | TechDebt | LOW | TBD | Open | Simplify .env discovery logic - Standardize on single location or environment variable. Current implementation tries 4 hardcoded paths. Related: sync-calendars.sh:28-40 |
| 2025-10-29 | 2.4 | 2 | Enhancement | LOW | TBD | Open | Implement log rotation for high-frequency scripts - Add rotation to display-detection.sh and environment-loader.sh (currently 1.7MB and 1.5MB). Configure max size 1MB, retention 10 files per architecture.md |
| 2025-10-29 | 2.4 | 2 | Enhancement | LOW | TBD | Open | Add automated integration test for AC #7 - Create test script that triggers sync and verifies widget state change. Document test procedure in story or test plan |
| 2025-10-29 | 2.4 | 2 | Enhancement | OPTIONAL | TBD | Open | Add script path validation in install.sh - Before loading LaunchAgent, verify sync-calendars.sh exists and is executable to prevent loading broken configuration |
| 2025-10-29 | 2.5 | 2 | Bug | MEDIUM | Dev | Open | Remove ERR trap or reconcile with error handling strategy - sync-calendars.sh:54 creates ambiguous error conditions with set -u but no set -e. Related: AC#4 |
| 2025-10-29 | 2.5 | 2 | Testing | MEDIUM | Dev | Open | Create test script for AC#8 error scenarios - test-calendar-error-handling.sh following test-loader.sh pattern for network failure, invalid URL, parse error, widget fallback |
| 2025-10-29 | 2.5 | 2 | Enhancement | MEDIUM | Dev | Open | Log HTTP error response content - sync-calendars.sh:207 should capture first 200 bytes of response on curl exit 22 for better debuggability |
| 2025-10-29 | 2.5 | 2 | Security | LOW | Dev | Open | Restrict cache file permissions - Use (umask 077; echo "..." > "$FILE") pattern at sync-calendars.sh:402-407, meeting.sh:81, 109 |
| 2025-10-29 | 2.5 | 2 | TechDebt | LOW | Dev | Open | Rename misleading function - meeting.sh:38 get_calendar_hash() returns count not hash, rename to get_calendar_change_count() |
| 2025-10-29 | 2.5 | 2 | TechDebt | LOW | Dev | Open | Document 30-minute stale threshold - meeting.sh:59 hardcoded value should be documented or made configurable in .env |
