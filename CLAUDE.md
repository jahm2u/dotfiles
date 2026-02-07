# Claude Code Context for Dotfiles Repository

This document provides essential context for Claude Code instances working with this dotfiles repository.

## Repository Overview

This is a comprehensive macOS dotfiles management system containing configurations for productivity tools, window managers, and development utilities. All configurations are managed via symlinks created by the installation script.

## Installation Script Architecture

The installation script (`scripts/install.sh`) uses a **four-phase declarative architecture** designed for minimal user interruption and maximum clarity.

### Core Principles & Phases

**Principles:** Separation of concerns | Upfront questions | Smart defaults | Clean progress | Idempotent

1. **System State Detection**: Silent scan - detects Homebrew, khal, sketchybar, aerospace, .env, LaunchAgents, symlinks (~1 sec)
2. **Configuration Gathering**: Batches ALL questions upfront - dependencies, env variables, features
3. **Plan Generation**: Builds structured plan, displays summary, single approval gate
4. **Execution**: Clean progress `[1/6] Action... ✓`, logs to `~/.config/dotfiles-install.log`
5. **Summary Report**: Final counts, next steps, log location

### Command-Line Flags
```bash
./scripts/install.sh            # Standard installation (recommended)
./scripts/install.sh --verbose  # Show detailed output during execution
./scripts/install.sh --dry-run  # Preview without executing
./scripts/install.sh --help     # Show usage information
```

### Key Features
- **Smart defaults**: Skips redundant questions if .env already configured
- **Idempotent**: Safe to run multiple times
- **Graceful degradation**: Non-critical failures don't stop installation
- **Automatic backups**: Timestamped backups before changes
- **Python venv setup**: Auto-creates venv for meeting-prep automation
- **Cache clearing**: Clears stale caches for fresh sync on new machines

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

## Automation Architecture

All automation features follow this standard pattern:

**Data Flow Pattern:**
```
.env → LaunchAgent (interval) → main script →
components → cache/API → event trigger → widget update
```

### Automation Components Summary

| Automation | Interval | Main Script | Purpose | Key Files |
|------------|----------|-------------|---------|-----------|
| **Calendar** | 15 min | `sync-calendars.sh` | Sync iCal → khal → meeting widget | `meeting.sh`, LaunchAgent: `calendar-sync` |
| **Todoist** | 30 sec | `todoist-precache.sh` | Precache tasks → instant popup | `todoist_popup.sh`, `todoist.sh`, LaunchAgent: `todoist-precache` |
| **Meeting Prep** | On-click | `meeting-prep.sh` | AI-powered meeting note generation | `classify-meeting.py`, `analyze-meeting-history.py`, `generate-meeting-note.py` |

### Component Details

#### Calendar Automation
- **Components**: `sync-calendars.sh` (60s timeout, curl → khal import) | `meeting.sh` (widget with countdown)
- **Config**: `.env`: `ICAL_URLS="https://url1,https://url2"` | History: `CALENDAR_HISTORY_DAYS=7`
- **Events**: `calendar_synced` triggered on success | Widget subscribes for reactive updates
- **Manual**: `bash ~/.config/sketchybar/helpers/sync-calendars.sh`

#### Todoist Automation
- **Components**: `todoist-precache.sh` (30s interval, API fetch) | `todoist_popup.sh` (instant cache read) | `todoist.sh` (focus widget)
- **Config**: `.env`: `TODOIST_API_TOKEN="token"` | Cache: `~/.cache/sketchybar/todoist_tasks_cache`
- **Events**: `todoist_focus_changed` when task clicked | Widget updates reactively
- **Performance**: <100ms popup open, <1s sync

#### Meeting Prep Automation
- **Workflow**: Icon click → classify meeting → find person folder → analyze history (GPT-4o-mini) → generate note → open Obsidian
- **Components**: `classify-meeting.py` (regex patterns) | `find-person-folder.sh` (vault search) | `analyze-meeting-history.py` (AI extraction) | `generate-meeting-note.py` (AI generation)
- **Config**: `.env`: `OBSIDIAN_VAULT_PATH="/path/to/vault"`, `OPENAI_API_KEY="sk-..."`
- **Performance**: 15-45s total, ~$0.010 per prep

### LaunchAgent Operations

**Service Names:** `calendar-sync` | `todoist-precache`

```bash
# Check status (replace {SERVICE} with service name)
launchctl list | grep {SERVICE}

# Reload service
launchctl unload ~/Library/LaunchAgents/com.user.{SERVICE}.plist
launchctl load -w ~/Library/LaunchAgents/com.user.{SERVICE}.plist

# View logs
tail -f ~/.config/sketchybar/logs/{SERVICE}.log
tail -f ~/.config/sketchybar/logs/{SERVICE}-stdout.log
tail -f ~/.config/sketchybar/logs/{SERVICE}-stderr.log

# Trigger manually
launchctl start com.user.{SERVICE}
```

## macOS LaunchAgent Best Practices

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
- `~/dotfiles/config/raycast` → `~/.config/raycast`
- `~/dotfiles/config/obsidian` → `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/.obsidian`
- `~/dotfiles/config/khal` → `~/.config/khal`

### Environment Variables

**Required Environment Variables (.env file at repository root):**

```bash
# Obsidian Integration (required for meeting prep)
OBSIDIAN_VAULT_PATH="/Users/username/Library/Mobile Documents/iCloud~md~obsidian/Documents/VaultName"

# OpenAI API (required for AI features: meeting prep)
OPENAI_API_KEY="sk-proj-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Calendar Sync (required for calendar widget)
ICAL_URLS="https://calendar-url-1.ics,https://calendar-url-2.ics"

# Todoist Integration (required for task widget)
TODOIST_API_TOKEN="your-todoist-api-token-here"
```

**Setup:** `cp ~/dotfiles/.env.example ~/dotfiles/.env` then edit with your values

**Getting API Keys:**
- **OpenAI**: https://platform.openai.com/api-keys
- **Todoist**: Settings → Integrations → API token
- **Calendar URLs**: Google Calendar → Settings → Secret iCal address | iCloud → Right-click → Share → Public Calendar
- **Telegram**: @BotFather → /newbot | @userinfobot for Chat ID

### Python Virtual Environment

**Location:** `~/.config/sketchybar/venv`

**Dependencies:** `openai==1.12.0`, `python-dotenv==1.0.0`, `pyyaml==6.0.1`, `requests`, `python-dateutil`

```bash
# Verify dependencies
~/.config/sketchybar/venv/bin/pip list

# All scripts use absolute path
~/.config/sketchybar/venv/bin/python3 script.py
```

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

## Development & Troubleshooting

### Common Commands
```bash
# Reload configs
aerospace reload-config
brew services restart sketchybar

# Check symlinks
ls -la ~/.config/* | grep "^l"

# Quick health check
launchctl list | grep "com.user"
ls -lh ~/.config/sketchybar/logs/
tail -f ~/.config/sketchybar/logs/*.log
```

### Testing Components

```bash
# Calendar: bash ~/.config/sketchybar/helpers/sync-calendars.sh
# Todoist: bash ~/.config/sketchybar/helpers/todoist-precache.sh
# Meeting: bash ~/.config/sketchybar/helpers/meeting-prep.sh

# Check caches
ls -lh ~/.cache/sketchybar/

# Verify .env
cat ~/dotfiles/.env | grep -v "^#" | grep -v "^$"

# Test APIs
source ~/dotfiles/.env
curl -H "Authorization: Bearer $OPENAI_API_KEY" https://api.openai.com/v1/models | jq '.data[0].id'
curl -H "Authorization: Bearer $TODOIST_API_TOKEN" https://api.todoist.com/rest/v2/projects | jq '.[0].name'
```

### Troubleshooting Quick Reference

**Common Issues & Solutions:**

| Issue | Symptom | Solution |
|-------|---------|----------|
| **LaunchAgent not running** | `launchctl list \| grep {SERVICE}` empty | `launchctl load -w ~/Library/LaunchAgents/com.user.{SERVICE}.plist` |
| **Empty logs** | No log output | `mkdir -p ~/.config/sketchybar/logs && chmod 755 ~/.config/sketchybar/logs` |
| **API auth fails** | 401/403 errors | Check token in `.env`, test with curl |
| **Network errors** | Curl exit codes 6/7/28 | DNS=6, refused=7, timeout=28 - check connectivity |
| **Widget stale** | Shows old data | Trigger manual sync for service |
| **Python fails** | ModuleNotFoundError | Reinstall venv: `python3 -m venv ~/.config/sketchybar/venv && ~/.config/sketchybar/venv/bin/pip install -r ~/.config/sketchybar/requirements.txt` |
| **khal not found** | Exit code 127 | Check LaunchAgent PATH configuration (see above) |
| **Permissions denied** | Can't write logs | Check directory permissions |

**Force Complete Resync (Calendar Example):**
```bash
launchctl unload ~/Library/LaunchAgents/com.user.calendar-sync.plist
rm -rf ~/.cache/sketchybar/ ~/.local/share/khal/calendars/google
launchctl load -w ~/Library/LaunchAgents/com.user.calendar-sync.plist
bash ~/.config/sketchybar/helpers/sync-calendars.sh
brew services restart sketchybar
```

### Log & Cache Locations

**Logs:** `~/.config/sketchybar/logs/`
- `{SERVICE}.log` - Main service logs
- `{SERVICE}-stdout.log` - Standard output
- `{SERVICE}-stderr.log` - Error output
- `meeting-prep.log` - Meeting prep workflow
- `~/.config/dotfiles-install.log` - Installation log

**Caches:** `~/.cache/sketchybar/`
- `last_sync_status` - Calendar sync status
- `todoist_tasks_cache` - Todoist tasks
- `todoist_working_task` - Current focus
- `last_meeting_prep_result.json` - Meeting prep result

## Contact & Support
Repository: https://github.com/jahm2u/dotfiles
For Claude-specific issues: Check `.claude/hooks/` for custom scripts