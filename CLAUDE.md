# Claude Code Context for Dotfiles Repository

This document provides essential context for Claude Code instances working with this dotfiles repository.

## Repository Overview

This is a comprehensive macOS dotfiles management system containing configurations for productivity tools, window managers, and development utilities. All configurations are managed via symlinks created by the installation script.

## Installation Script Architecture

### Overview

The installation script (`scripts/install.sh`) uses a clean **four-phase declarative architecture** designed for minimal user interruption and maximum clarity.

**Core Principles:**
- **Separation of concerns**: Configuration, planning, and execution are distinct phases
- **Upfront questions**: All user input gathered at the beginning (no scattered prompts)
- **Smart defaults**: Only asks what's unknown based on system state
- **Clean progress**: Minimal output with detailed logs available
- **Idempotent**: Safe to run multiple times

### The Four Phases

**Phase 1: System State Detection**
- Silently scans system (no user interaction)
- Detects: Homebrew, khal, sketchybar, aerospace, .env contents, LaunchAgents, symlinks
- Stores state in global variables (STATE_*)
- ~1 second execution time

**Phase 2: Configuration Gathering**
- Batches ALL questions upfront in logical groups:
  - Dependencies (missing tools)
  - Environment variables (OpenAI API, Obsidian vault, Calendar URLs)
  - Features (LaunchAgent preferences)
- Uses smart defaults based on detected state
- Clear, professional prompts

**Phase 3: Plan Generation & Display**
- Builds structured execution plan based on configuration
- Displays clear summary of all actions before executing
- Single approval gate (prevents surprises)
- Shows step count and descriptions

**Phase 4: Execution**
- Clean progress indicators: `[1/6] Action... ✓`
- Verbose output redirected to `~/.config/dotfiles-install.log`
- Status tracking (success/warning/error counts)
- Error handling with graceful degradation

**Phase 5: Summary Report**
- Final counts: ✓ successes, ⚠ warnings, ✗ errors
- Context-aware next steps
- Log file location
- Clean professional finish

### Command-Line Flags

```bash
# Standard installation (recommended)
./scripts/install.sh

# Show detailed output during execution
./scripts/install.sh --verbose

# Preview what would be done without executing
./scripts/install.sh --dry-run

# Show usage information
./scripts/install.sh --help
```

### Key Features

- **Smart defaults**: If .env exists with config, doesn't ask redundant questions
- **Idempotent**: Can run multiple times safely; skips existing configurations
- **Graceful degradation**: Non-critical failures don't stop installation
- **Automatic backups**: Existing configs backed up with timestamps before changes
- **Clean logs**: Detailed execution log at `~/.config/dotfiles-install.log`
- **Python venv setup**: Automatically creates venv with dependencies for meeting-prep and Krisp automation
- **Cache clearing**: Clears stale calendar cache and khal database for fresh sync on new machines

### Metrics

- Main script reduced from 1136 lines to ~850 lines of clean, modular code
- User prompts reduced from 11+ scattered locations to single batched section
- Output verbosity: <30 lines (vs 100+ lines previously)
- Execution time: <2 minutes for typical update run

### Architecture Benefits

1. **Maintainability**: Clear separation makes adding features easy
2. **User Experience**: Professional, non-overwhelming interaction
3. **Debugging**: Detailed logs separate from clean UI
4. **Testing**: Dry-run mode allows safe preview
5. **Extensibility**: New steps slot into plan array cleanly

## Core Tools & Configurations

### 1. AeroSpace (Tiling Window Manager)
- **Config**: `config/aerospace/aerospace.toml`
- **Key Bindings**: Uses Ctrl+Alt+Shift for most commands, adds Cmd as modifier for some actions
- **Workspace Layout**: Spatial navigation with arrows
- **Important**: User has custom Hyper key bindings that must not conflict:
  - Hyper+W = Screenshot
  - Hyper+S = Translation
  - Hyper+Space = Raycast

### 2. Karabiner-Elements (Keyboard Remapping)
- **Config**: `config/karabiner/karabiner.json`
- **Primary Function**: Map Caps Lock to Hyper key
- **Device-specific**: Contains rules for external keyboard (vendor_id: 12136)

### 3. Sketchybar (Status Bar)
- **Config**: `config/sketchybar/`
- **Integration**: Updates workspace indicators via AeroSpace hooks
- **Path References**: Uses hardcoded paths to user home directory

#### Calendar Automation Architecture

The calendar automation system provides zero-touch synchronization between iCal sources and the Sketchybar meeting widget, with comprehensive error handling and graceful degradation.

**Complete Data Flow:**
```
.env (ICAL_URLS) → LaunchAgent (15min) → sync-calendars.sh →
curl fetch (.ics) → khal import → database → calendar_synced event →
meeting.sh plugin → widget display (countdown timer)
```

**Component Details:**

1. **sync-calendars.sh** (`config/sketchybar/helpers/sync-calendars.sh`)
   - Main synchronization script with 60-second network timeout
   - Sources `.env` for `ICAL_URLS` configuration
   - Downloads iCal files via curl with error handling
   - Imports events to khal database with batch processing
   - Removes stale events (configurable history window)
   - Triggers `calendar_synced` custom event on success
   - Comprehensive logging to `logs/calendar-sync.log`
   - **Typical sync duration**: Initial large import ~3 minutes (observed: 186s for 11K+ events), incremental syncs <30 seconds

2. **meeting.sh** (`config/sketchybar/plugins/meeting.sh`)
   - Sketchybar widget plugin displaying next meeting
   - Queries khal database for upcoming events
   - Calculates countdown timer with urgency-based icons
   - Subscribes to `calendar_synced` event for reactive updates
   - MD5 change detection to prevent spam updates
   - Shows fallback state on sync failures

3. **LaunchAgent** (`~/Library/LaunchAgents/com.user.calendar-sync.plist`)
   - macOS background service for periodic execution
   - Runs sync every 15 minutes (900 seconds interval)
   - Persists across system restarts
   - Logs stdout/stderr to separate log files
   - Installed automatically by `scripts/install.sh`

4. **Event System** (Sketchybar custom events)
   - `calendar_synced`: Triggered after successful sync
   - Enables reactive widget updates without polling
   - Meeting widget subscribes via `--subscribe meeting calendar_synced`
   - Reduces unnecessary processing and improves performance

**Configuration:**
- Calendar URLs: `.env` file in project root (git-ignored)
- Format: `ICAL_URLS="https://url1,https://url2"`
- Individual URLs: `CALENDAR_URL_PRIMARY=https://...` (optional)
- History window: `CALENDAR_HISTORY_DAYS=7` (default: 7 days)
- Timeout: `CALENDAR_SYNC_TIMEOUT=60` (default: 60 seconds)

**Manual Sync Options:**
- Quick trigger: `bash ~/.config/sketchybar/helpers/trigger-calendar-sync.sh`
- Direct sync: `bash ~/.config/sketchybar/helpers/sync-calendars.sh`
- Via LaunchAgent: `launchctl start com.user.calendar-sync`

**LaunchAgent Management:**
- Check status: `launchctl list | grep calendar-sync`
- View stdout logs: `tail -f ~/.config/sketchybar/logs/calendar-sync-stdout.log`
- View error logs: `tail -f ~/.config/sketchybar/logs/calendar-sync-stderr.log`
- Unload: `launchctl unload ~/Library/LaunchAgents/com.user.calendar-sync.plist`
- Reload: `launchctl load -w ~/Library/LaunchAgents/com.user.calendar-sync.plist`

**Error Handling & Logging:**
- **Log Location**: `~/.config/sketchybar/logs/calendar-sync.log`
- **Log Format**: `YYYY-MM-DD HH:MM:SS [LEVEL] message`
- **Log Levels**: INFO (success), WARN (degraded), ERROR (failure)
- **Log Rotation**: Automatic - keeps last 10 logs or 1MB max per file
- **Exit Codes**: 0=success, 1=partial failure, 2=complete failure
- **Sync Status**: Cached at `~/.cache/sketchybar/last_sync_status`
- **Graceful Degradation**: Widget shows cached data + "stale" indicator on sync failure
- **Non-blocking**: Sync failures never crash Sketchybar or widget

**Troubleshooting:**
- If LaunchAgent not running: Check `launchctl list | grep calendar-sync` shows the service
- If sync fails: Check `~/.config/sketchybar/logs/calendar-sync.log` for detailed error messages
- If logs empty: Verify LaunchAgent is loaded and logs directory exists at `~/.config/sketchybar/logs/`
- System logs: `log show --predicate 'subsystem == "com.apple.launchd"' --last 5m | grep calendar-sync`
- **Network errors**: Logged with curl exit codes (6=DNS, 7=connection refused, 28=timeout)
- **Parse errors**: Logged with event details and source URL
- **Widget shows "stale"**: Last sync failed - check logs, verify calendar URLs in `.env` are accessible

#### Todoist Automation Architecture

The Todoist automation system provides instant popup performance and reactive focus task updates through background precaching and event-based widget synchronization.

**Complete Data Flow:**
```
.env (TODOIST_API_TOKEN) → LaunchAgent (30sec) → todoist-precache.sh →
curl fetch (Todoist API) → Python parse → cache → todoist_synced event →
todoist_popup.sh (instant) → user clicks task → todoist_focus_changed event →
todoist.sh widget (immediate update)
```

**Component Details:**

1. **todoist-precache.sh** (`config/sketchybar/helpers/todoist-precache.sh`)
   - Background precache script with 30-second timeout
   - Sources `.env` for `TODOIST_API_TOKEN`
   - Fetches tasks from Todoist REST API v2 (filter: today | overdue)
   - Python JSON parsing (top 25 tasks, sorted by priority)
   - Writes cache with `SYNC_STATUS` header and pipe-delimited task format
   - Comprehensive logging to `logs/todoist-precache.log`
   - Triggers `todoist_synced` custom event on success
   - **Performance**: Sync completes in <1 second, enables <100ms popup open time

2. **todoist_popup.sh** (`config/sketchybar/plugins/todoist_popup.sh`)
   - Sketchybar popup plugin showing top 25 priority tasks
   - Reads from cache instead of making live API calls (instant performance)
   - Priority circles: P1=red, P2=orange, P3=blue, P4=unfilled
   - Yellow highlight shows currently focused task
   - Click handler: writes task ID to cache + triggers `todoist_focus_changed` event + auto-closes popup
   - Handles missing cache ("Refreshing tasks..."), failed sync (retry option)
   - Falls back gracefully on errors - never blocks user

3. **todoist.sh** (`config/sketchybar/plugins/todoist.sh`)
   - Main Todoist widget plugin
   - Subscribes to `todoist_focus_changed` event for reactive updates
   - Reads focused task from `~/.cache/sketchybar/todoist_working_task`
   - Displays focused task with randomized completion messages when done
   - Focus task persists across Sketchybar restarts (cache-based)

4. **LaunchAgent** (`~/Library/LaunchAgents/com.user.todoist-precache.plist`)
   - macOS background service for periodic precaching
   - Runs sync every 30 seconds (user preference for fast updates)
   - Within Todoist API rate limits (450 req/15min, using 120 req/hour)
   - RunAtLoad: true for immediate first sync
   - Logs stdout/stderr to separate log files

5. **Event System** (Sketchybar custom events)
   - `todoist_synced`: Triggered after successful precache (optional)
   - `todoist_focus_changed`: Triggered when user clicks task in popup
   - Enables reactive widget updates without polling
   - Todoist widget subscribes via `--subscribe todoist todoist_focus_changed`

**Configuration:**
- API Token: `.env` file in project root (git-ignored)
- Format: `TODOIST_API_TOKEN="your-token-here"`
- Token location: `~/dotfiles/.env` or `~/repos/02_personal/dotfiles/.env`
- Precache interval: 30 seconds (configurable in LaunchAgent plist)
- API timeout: 30 seconds

**Manual Sync Options:**
- Trigger immediate precache: `bash ~/.config/sketchybar/helpers/todoist-precache.sh`
- Via LaunchAgent: `launchctl start com.user.todoist-precache`
- Check sync status: `cat ~/.cache/sketchybar/todoist_tasks_cache | head -2`

**LaunchAgent Management:**
- Check status: `launchctl list | grep todoist-precache`
- View logs: `tail -f ~/.config/sketchybar/logs/todoist-precache.log`
- View stdout: `tail -f ~/.config/sketchybar/logs/todoist-precache-stdout.log`
- View stderr: `tail -f ~/.config/sketchybar/logs/todoist-precache-stderr.log`
- Unload: `launchctl unload ~/Library/LaunchAgents/com.user.todoist-precache.plist`
- Reload: `launchctl load -w ~/Library/LaunchAgents/com.user.todoist-precache.plist`

**Error Handling & Logging:**
- **Log Location**: `~/.config/sketchybar/logs/todoist-precache.log`
- **Log Format**: `YYYY-MM-DD HH:MM:SS [LEVEL] message`
- **Log Levels**: INFO (success), ERROR (failure)
- **Exit Codes**: 0=success, 1=partial failure, 2=complete failure
- **Cache Format**: Line 1: `SYNC_STATUS=success|failed`, Line 2: `TASKS_START`, Line 3+: pipe-delimited tasks
- **Graceful Degradation**: Popup shows cached data with "Sync failed - click to retry" on failure
- **Non-blocking**: Sync failures never crash Sketchybar or prevent widget display

**Troubleshooting:**
- If LaunchAgent not running: `launchctl list | grep todoist-precache` should show PID
- If sync fails: Check `~/.config/sketchybar/logs/todoist-precache.log` for errors
- If popup slow: Verify cache exists at `~/.cache/sketchybar/todoist_tasks_cache`
- **Missing API token**: Popup closes silently - verify `TODOIST_API_TOKEN` in `.env`
- **Invalid token**: Check stderr log for HTTP 401/403 errors
- **Network errors**: Logged with curl exit codes (6=DNS, 7=connection refused, 28=timeout)
- **Empty popup**: Verify tasks match filter "today | overdue" in Todoist app

**Performance Metrics:**
- Popup open time: <100ms (down from 500-1000ms before precaching)
- Precache sync duration: <1 second typical
- Focus task update: Instant (event-triggered, no polling)
- API rate usage: ~120 requests/hour (well under 450/15min limit)

#### Obsidian Meeting Prep Automation Architecture

The Obsidian meeting prep system provides AI-powered meeting note generation with one-click preparation. When you click a meeting icon, it automatically analyzes previous meetings, generates pre-filled notes, and opens them in Obsidian.

**Complete Data Flow:**
```
Icon Click → meeting-prep.sh → classify-meeting.py → find-person-folder.sh →
analyze-meeting-history.py (OpenAI) → generate-meeting-note.py (OpenAI) →
save to vault → open in Obsidian
```

**Component Details:**

1. **meeting-prep.sh** (`config/sketchybar/helpers/meeting-prep.sh`)
   - Main orchestration script with loading animation
   - Sources `.env` for `OBSIDIAN_VAULT_PATH` and `OPENAI_API_KEY`
   - Fetches next meeting from khal calendar database
   - Orchestrates 5-step workflow with comprehensive error handling
   - Opens generated note in Obsidian via URL scheme
   - Comprehensive logging to `logs/meeting-prep.log`
   - **Total execution**: 15-45 seconds typical

2. **classify-meeting.py** (`config/sketchybar/helpers/classify-meeting.py`)
   - Python script for meeting type classification
   - Regex pattern matching for 1-on-1s, company meetings, team meetings
   - Extracts participant names (excluding "Jeff Hamersly")
   - Determines company context (IPMedia, TP, MT, DT, PD, etc.)
   - Returns JSON with meeting_type, company, participant, confidence
   - **Performance**: <100ms

3. **find-person-folder.sh** (`config/sketchybar/helpers/find-person-folder.sh`)
   - Bash script for locating person folders in vault
   - Priority search order:
     1. `Business/People/IPMedia/{PersonName}/`
     2. `Business/People/CO/{Company}/{PersonName}/`
     3. `Business/People/Cross-Company/{PersonName}/`
     4. `Business/People/Archive/{PersonName}/`
   - Verifies folder structure (Meetings/ directory exists)
   - Returns absolute path to person folder
   - **Performance**: <200ms

4. **analyze-meeting-history.py** (`config/sketchybar/helpers/analyze-meeting-history.py`)
   - Python script using OpenAI GPT-4o-mini for AI analysis
   - Finds last 5 meeting files (YYYY-MM-DD*.md pattern)
   - Extracts via AI:
     * Open Action Items (with owner, days open, priority)
     * Recurring Topics (patterns and trends)
     * Active Blockers (impediments and resolutions)
     * Unresolved Threads (questions without answers)
     * Suggested Agenda (must/should/could discuss)
     * Meeting Patterns (frequency, last meeting date)
   - Graceful handling of first meetings (no previous history)
   - **Performance**: 8-15 seconds (AI processing)
   - **Cost**: ~$0.005 per analysis

5. **generate-meeting-note.py** (`config/sketchybar/helpers/generate-meeting-note.py`)
   - Python script using OpenAI GPT-4o-mini for note generation
   - Loads appropriate template (1on1, company, team)
   - Generates pre-filled Meeting Prep sections:
     * Critical/Urgent Items (overdue actions)
     * Prepared Questions (3-5 specific questions)
     * Key Topics to Cover (prioritized agenda)
     * Follow-ups from Last Meeting (action tracking)
     * Context from Last Meeting (summary)
   - Leaves Capture sections empty for live notes
   - Creates Obsidian wikilinks for people/companies
   - Determines save path based on meeting type
   - **Performance**: 5-10 seconds (AI generation)
   - **Cost**: ~$0.005 per generation

6. **Sketchybar Integration** (icon click handler)
   - Icon click triggers workflow (NOT label click - that shows popup)
   - Loading animation displays during execution (... → :.. → .:. → ..:)
   - Configured via `icon.click_script` in sketchybarrc
   - Widget resets to normal state on completion
   - Triggers `calendar_synced` event for refresh

**Configuration:**
- Environment variables: `.env` file in project root (git-ignored)
- Required: `OBSIDIAN_VAULT_PATH` (absolute path to vault root)
- Required: `OPENAI_API_KEY` (from https://platform.openai.com/api-keys)
- Python venv: `~/.config/sketchybar/venv` (isolated dependencies)
- Dependencies: `openai==1.12.0`, `python-dotenv==1.0.0`, `pyyaml==6.0.1`

**Manual Trigger:**
```bash
bash ~/.config/sketchybar/helpers/meeting-prep.sh
```

**Error Handling & Logging:**
- **Log Location**: `~/.config/sketchybar/logs/meeting-prep.log`
- **Log Format**: `YYYY-MM-DD HH:MM:SS [LEVEL] message`
- **Cache Location**: `~/.cache/sketchybar/last_meeting_prep_result.json`
- **Exit Codes**: 0=success, 1=failure with helpful error messages
- **Graceful Degradation**:
  * Person not found → Error message with onboarding suggestion
  * No previous meetings → First-meeting template with welcome content
  * OpenAI API failure → Error logged with clear troubleshooting steps
  * Template not found → Falls back to default 1on1 template
  * Vault not accessible → Error with OBSIDIAN_VAULT_PATH guidance

**Troubleshooting:**
- If workflow doesn't trigger: Check `icon.click_script` in sketchybarrc files
- If person not found: Verify vault structure matches expected paths
- If AI fails: Check `OPENAI_API_KEY` is valid and has credits
- If no note opens: Verify `OBSIDIAN_VAULT_PATH` points to correct vault
- Check logs: `tail -f ~/.config/sketchybar/logs/meeting-prep.log`
- Check last result: `cat ~/.cache/sketchybar/last_meeting_prep_result.json | jq`
- Test classification: `~/.config/sketchybar/helpers/classify-meeting.py --title "1on1 with Marcus" --date "2024-11-02" --participants "Marcus Smith"`
- **OpenAI errors**: Check API key, check usage limits, check network connectivity
- **Template errors**: Verify templates exist at `{vault}/bmad/vault-ops/templates/*.md`
- **Python errors**: Verify venv exists and dependencies installed: `~/.config/sketchybar/venv/bin/pip list`

**Performance Metrics:**
- Classification: <100ms
- Person folder search: <200ms
- Meeting history analysis: 8-15 seconds (AI processing)
- Note generation: 5-10 seconds (AI generation)
- Total end-to-end: 15-45 seconds typical
- Cost per meeting prep: ~$0.005 (extremely cheap with GPT-4o-mini)
- Daily cost (5 meetings): ~$0.025

**Integration Notes:**
- Preserves existing meeting.sh functionality (display, popup)
- Separate click handlers: label = popup, icon = prep workflow
- No breaking changes to calendar sync workflow
- Symlink-based deployment (changes immediately reflected)
- Python scripts use venv for dependency isolation

#### macOS LaunchAgent Best Practices

**Critical PATH Configuration:**

LaunchAgents run with a minimal environment that does NOT include Homebrew paths. If your LaunchAgent calls Homebrew-installed tools (like khal, jq, etc.), you MUST configure the PATH explicitly.

**Required EnvironmentVariables in plist:**

```xml
<key>EnvironmentVariables</key>
<dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
</dict>
```

**Why This Matters:**
- Without explicit PATH, commands like `khal` will fail with "command not found" (exit code 127)
- LaunchAgent runs silently in background - failures may go unnoticed
- This was discovered as a critical bug during Story 2.7 E2E testing

**LaunchAgent Template Pattern:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.your-service-name</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/full/path/to/script.sh</string>
    </array>

    <key>StartInterval</key>
    <integer>900</integer> <!-- 15 minutes -->

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>

    <key>StandardOutPath</key>
    <string>/path/to/logs/service-stdout.log</string>

    <key>StandardErrorPath</key>
    <string>/path/to/logs/service-stderr.log</string>

    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```

**Testing LaunchAgents:**

```bash
# Always test with launchctl before assuming it works
launchctl load -w ~/Library/LaunchAgents/com.user.your-service.plist

# Check if running
launchctl list | grep your-service

# Check logs immediately
tail -f /path/to/logs/service-stderr.log
```

### 4. Hammerspoon (Automation)
- **Config**: `config/hammerspoon/`
- **Symlink**: Goes to `~/.hammerspoon` (not ~/.config/)

### 5. Claude AI Assistant
- **Config**: `config/claude/`
- **Hooks**: Custom notification and audio scripts
- **Settings**: Contains tool hooks for PreToolUse notifications

### 6. Other Configurations
- **Raycast**: `config/raycast/`
- **Obsidian**: `config/obsidian/` (syncs to iCloud)

## Installation & Management

### Quick Setup
```bash
git clone https://github.com/jahm2u/dotfiles.git ~/dotfiles && cd ~/dotfiles && ./scripts/install.sh
```

### Symlink Structure
The `scripts/install.sh` script creates these symlinks:
- `~/dotfiles/config/aerospace/aerospace.toml` → `~/.config/aerospace/aerospace.toml`
- `~/dotfiles/config/sketchybar` → `~/.config/sketchybar`
- `~/dotfiles/config/karabiner` → `~/.config/karabiner`
- `~/dotfiles/config/hammerspoon` → `~/.hammerspoon`
- `~/dotfiles/config/claude` → `~/.claude`
- `~/dotfiles/config/raycast` → `~/.config/raycast`
- `~/dotfiles/config/obsidian` → `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/.obsidian`
- `~/dotfiles/config/khal` → `~/.config/khal`

## Critical Context & Known Issues

### 1. Hyper Key Configuration
- **Definition**: Hyper = Cmd+Alt+Ctrl+Shift (all modifiers)
- **Important**: Cannot combine Hyper with any other modifier (e.g., "Hyper+Cmd" is impossible)
- **User's Custom Bindings**: Must preserve existing Hyper key uses

### 2. AeroSpace Window Management
- **Default Modifier**: Alt (Option) key
- **Conflict**: Alt+Shift+2 produces € symbol (user needs this)
- **Solution**: Spatial navigation with arrows instead of numbers

### 3. Claude Hooks System
- **Location**: `config/claude/hooks/`
- **macOS Notifications**: Use simple `display notification` (no System Events)
- **Audio Notifications**: Play sound files for different events
- **Settings**: Configured in `config/claude/settings.json`

### 4. Path Configuration
- Most configs use relative paths or environment variables
- Sketchybar may contain some hardcoded home directory references
- Use `~` or `$HOME` variables when possible for portability

## Development Guidelines

### When Making Changes
1. **Test Symlinks**: Changes to files in the repo immediately affect the system
2. **Backup First**: The install script creates timestamped backups
3. **Reload Services**: Most tools need restart/reload after config changes
4. **Check Permissions**: macOS requires accessibility permissions for many tools

### Common Commands
```bash
# Reload AeroSpace config
aerospace reload-config

# Restart Sketchybar
brew services restart sketchybar

# Check symlinks
ls -la ~/.config/* | grep "^l"
```

### Testing Changes
- **AeroSpace**: Changes take effect after reload
- **Hammerspoon**: Use menu bar icon → "Reload Config"
- **Karabiner**: Changes apply immediately
- **Sketchybar**: Requires service restart

## User Preferences & Workflows

### Window Management Philosophy
- Prefers spatial navigation (arrows) over numbered workspaces
- Uses mode-based commands to reduce modifier complexity
- Values mnemonic shortcuts (M=Move, F=Fling, Z=siZe)

### Workspace Layout
- Workspace 1: Secondary monitor (left)
- Workspaces 2-7: Main monitor
- Mental model: Left arrow = secondary, other arrows = main

### Key Binding Patterns
- Ctrl + Alt + Shift + Arrows: Window focus
- Ctrl + Alt + Shift + Numbers: Workspace navigation
- Cmd + Ctrl + Alt + Shift + Arrows: Window movement
- Cmd + Ctrl + Alt + Shift + Numbers: Move to workspace

## Future Considerations
Potential improvements to explore:
- Cross-platform configuration support
- Enhanced automation and workflows
- Additional productivity tool integrations

## Troubleshooting Quick Reference

### Permissions Issues
- Grant accessibility permissions: System Settings → Privacy & Security
- Check file ownership: `ls -la ~/dotfiles`

### Config Not Loading
1. Verify symlinks: `readlink ~/.config/aerospace`
2. Check for syntax errors in TOML/JSON files
3. Look for hardcoded paths that don't exist

### Integration Problems
- Sketchybar not updating: Check aerospace hooks in config
- Hammerspoon not working: Verify Lua syntax in console
- Karabiner conflicts: Use EventViewer to debug

### Calendar Sync Issues

#### Quick Diagnostic Commands
- **Check sync status**: `cat ~/.cache/sketchybar/last_sync_status`
- **View recent logs**: `tail -50 ~/.config/sketchybar/logs/calendar-sync.log`
- **Check LaunchAgent status**: `launchctl list | grep calendar-sync`
- **Test sync manually**: `bash ~/.config/sketchybar/helpers/sync-calendars.sh`
- **Force immediate sync**: `launchctl start com.user.calendar-sync`
- **View real-time logs**: `tail -f ~/.config/sketchybar/logs/calendar-sync.log`

#### Common Scenarios and Solutions

**1. Events Not Appearing in Widget**
- **Symptom**: Calendar has events but widget shows "No meetings"
- **Causes**:
  - Sync hasn't run yet (15-minute interval)
  - LaunchAgent not running
  - Sync failed silently
- **Solutions**:
  1. Trigger manual sync: `bash ~/.config/sketchybar/helpers/sync-calendars.sh`
  2. Check LaunchAgent: `launchctl list | grep calendar-sync` should show PID
  3. If not listed: `launchctl load -w ~/Library/LaunchAgents/com.user.calendar-sync.plist`
  4. Check logs for errors: `tail -50 ~/.config/sketchybar/logs/calendar-sync.log`
  5. Verify `.env` contains valid `ICAL_URLS`

**2. Network Connectivity Failures**
- **Symptom**: Logs show "DNS resolution failed", "Connection refused", or "Timeout after 60s"
- **Curl Exit Codes**:
  - 6: DNS resolution failed
  - 7: Connection refused
  - 28: Operation timeout
- **Solutions**:
  1. Check internet: `ping 8.8.8.8`
  2. Test calendar URL directly: `curl -I "YOUR_ICAL_URL"`
  3. Check firewall settings
  4. Verify calendar URL is accessible from command line
  5. Widget will show cached data with "stale" indicator until network recovers

**3. Invalid Calendar URL Configuration**
- **Symptom**: Logs show "Invalid calendar file" or HTTP error codes
- **Causes**:
  - URL returns HTML error page instead of .ics file
  - Authentication required but not configured
  - URL expired or revoked
- **Solutions**:
  1. Test URL in browser - should download .ics file
  2. Check `.env` for typos in `ICAL_URLS`
  3. Verify URL format matches `.env.example`
  4. For Google Calendar: Ensure sharing settings allow iCal access
  5. For iCloud: Regenerate calendar link if expired
  6. Check logs for specific HTTP response codes

**4. Widget Shows "Stale" Data**
- **Symptom**: Widget displays meeting info with clock icon or "stale" indicator
- **Meaning**: Last sync attempt failed, showing cached data
- **Solutions**:
  1. Check logs: `tail -50 ~/.config/sketchybar/logs/calendar-sync.log`
  2. Identify error type (network, authentication, parsing)
  3. Resolve underlying issue (see scenarios above)
  4. Manually trigger sync to test: `bash ~/.config/sketchybar/helpers/sync-calendars.sh`
  5. Widget will automatically update on next successful sync

**5. khal Import Failures**
- **Symptom**: Logs show "khal import failed" or khal errors
- **Causes**:
  - khal not installed: `brew install khal`
  - Invalid khal config
  - Database corruption
  - Malformed .ics file
- **Solutions**:
  1. Verify khal installed: `which khal`
  2. Check khal config: `cat ~/.config/khal/config`
  3. Test khal manually: `khal list today 7d`
  4. Reset khal database if corrupted: `rm -rf ~/.local/share/khal/calendars/`
  5. Reinstall via `scripts/install.sh` if needed

**6. LaunchAgent Not Running**
- **Symptom**: `launchctl list | grep calendar-sync` returns nothing
- **Causes**:
  - LaunchAgent not installed
  - Manually unloaded
  - System cleared launch services
- **Solutions**:
  1. Check plist exists: `ls -la ~/Library/LaunchAgents/com.user.calendar-sync.plist`
  2. Load agent: `launchctl load -w ~/Library/LaunchAgents/com.user.calendar-sync.plist`
  3. Verify loaded: `launchctl list | grep calendar-sync`
  4. Check system logs: `log show --predicate 'subsystem == "com.apple.launchd"' --last 5m | grep calendar-sync`
  5. Reinstall if missing: Run `scripts/install.sh`

**7. Permission Issues**
- **Symptom**: Logs show "Permission denied" errors
- **Causes**:
  - Log directory not writable
  - khal database not accessible
  - Script not executable
- **Solutions**:
  1. Check log directory: `ls -la ~/.config/sketchybar/logs/`
  2. Create if missing: `mkdir -p ~/.config/sketchybar/logs`
  3. Fix permissions: `chmod 755 ~/.config/sketchybar/helpers/sync-calendars.sh`
  4. Check khal directory: `ls -la ~/.local/share/khal/`
  5. Verify home directory permissions

**8. Force Complete Resync**
- **When**: After major config changes or persistent issues
- **Steps**:
  1. Stop LaunchAgent: `launchctl unload ~/Library/LaunchAgents/com.user.calendar-sync.plist`
  2. Clear cache: `rm -rf ~/.cache/sketchybar/`
  3. Clear khal database: `rm -rf ~/.local/share/khal/calendars/google`
  4. Reload LaunchAgent: `launchctl load -w ~/Library/LaunchAgents/com.user.calendar-sync.plist`
  5. Trigger manual sync: `bash ~/.config/sketchybar/helpers/sync-calendars.sh`
  6. Monitor logs: `tail -f ~/.config/sketchybar/logs/calendar-sync.log`
  7. Restart Sketchybar: `brew services restart sketchybar`

## Contact & Support
Repository: https://github.com/jahm2u/dotfiles
For Claude-specific issues: Check `.claude/hooks/` for custom scripts