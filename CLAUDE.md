# Claude Code Context for Dotfiles Repository

This document provides essential context for Claude Code instances working with this dotfiles repository.

## Repository Overview

This is a comprehensive macOS dotfiles management system containing configurations for productivity tools, window managers, and development utilities. All configurations are managed via symlinks created by the installation script.

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