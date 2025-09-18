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
- **Current Issue**: Config has complex workspace mappings that need removal
- **Device-specific**: Contains rules for external keyboard (vendor_id: 12136)

### 3. Sketchybar (Status Bar)
- **Config**: `config/sketchybar/`
- **Integration**: Updates workspace indicators via AeroSpace hooks
- **Path References**: Uses hardcoded paths to user home directory
- **Meeting Widget**: Uses khal calendar tool with iCal URLs from `.env` file
  - Calendar URLs stored in `config/sketchybar/.env` (git-ignored)
  - Sync calendars: `bash ~/.config/sketchybar/plugins/sync_calendars.sh`
  - Shows next meeting with countdown timer

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

### 4. Path Hardcoding
Multiple configs contain hardcoded paths to specific user directories. When working with this repo:
- Check for paths containing `/Users/richardoliverbray/` or `/Users/t/`
- Update paths to be relative or use environment variables where possible

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

## Future Enhancements
See `FUTURE_PLANS.md` for planned improvements including:
- NixOS/Home Manager migration
- Cross-platform support
- Enhanced automation features

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

## Contact & Support
Repository: https://github.com/jahm2u/dotfiles
For Claude-specific issues: Check `.claude/hooks/` for custom scripts