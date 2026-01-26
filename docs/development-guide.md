# Development Guide - Dotfiles Repository

## Overview

This guide provides comprehensive instructions for setting up, developing, and maintaining the dotfiles configuration management system.

## Prerequisites

### System Requirements
- **Operating System**: macOS (tested on macOS Sonoma 14.0+)
- **Architecture**: Apple Silicon (M1/M2/M3) or Intel
- **Disk Space**: ~2GB for all applications and configurations

### Required Tools

#### Package Manager
```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

#### Git
```bash
# Usually pre-installed on macOS, or install via Homebrew
brew install git
```

## Installation

### Quick Start (Recommended)

**One-liner for complete setup**:
```bash
git clone https://github.com/jahm2u/dotfiles.git ~/dotfiles && cd ~/dotfiles && ./scripts/bootstrap.sh
```

This command will:
1. Clone the repository to `~/dotfiles`
2. Run the bootstrap script which:
   - Installs/updates Homebrew
   - Installs all applications from Brewfile (25+ packages)
   - Creates all configuration symlinks
   - Installs required fonts (JetBrains Mono Nerd Font)
   - Sets up Node.js and CLI tools
   - Provides post-installation instructions

### Step-by-Step Setup

#### 1. Clone Repository
```bash
git clone https://github.com/jahm2u/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

#### 2. Option A: Full Bootstrap (Recommended for New Machines)
```bash
./scripts/bootstrap.sh
```

#### 2. Option B: Configuration Only (If Apps Already Installed)
```bash
./scripts/install.sh
```

#### 3. Option C: Manual Package Installation
```bash
# Install all packages from Brewfile
brew bundle

# Then create symlinks
./scripts/install.sh
```

## Post-Installation

### 1. Grant System Permissions

Several applications require accessibility permissions:

**System Settings → Privacy & Security → Accessibility**
- ✓ AeroSpace
- ✓ Hammerspoon
- ✓ Karabiner-Elements
- ✓ Raycast

**System Settings → Privacy & Security → Screen Recording** (if using screen capture features)
- ✓ Hammerspoon

### 2. Start Services

```bash
# Start AeroSpace window manager
open -a AeroSpace

# Start Sketchybar status bar
brew services start sketchybar

# Verify services are running
brew services list | grep sketchybar
pgrep -fl AeroSpace
```

### 3. Configure Applications

#### Karabiner-Elements
- Should automatically load config from `~/.config/karabiner/`
- Verify Caps Lock → Hyper key mapping is active

#### Hammerspoon
- Launch Hammerspoon (should appear in menu bar)
- Grant necessary permissions when prompted
- Click "Reload Config" from menu bar icon

#### Raycast
- Launch Raycast (Cmd+Space or configured hotkey)
- Sign in if needed
- Extensions should load from `~/.config/raycast/extensions/`

#### Obsidian
- Symlink points to iCloud location
- First launch: Obsidian will download plugin binaries
- Settings and configurations are preserved from repo

#### Claude CLI
```bash
# Claude is installed via bootstrap.sh
# Verify installation
claude --version

# Authenticate (if needed)
claude auth login
```

## Development Workflow

### Making Configuration Changes

#### 1. Edit Configuration Files
All configs are in `~/dotfiles/config/`. Changes are immediately active via symlinks:

```bash
# Example: Edit Hammerspoon config
vim ~/dotfiles/config/hammerspoon/init.lua

# Example: Edit AeroSpace config
vim ~/dotfiles/config/aerospace/aerospace.toml
```

#### 2. Reload Services

**AeroSpace**:
```bash
aerospace reload-config
```

**Sketchybar**:
```bash
brew services restart sketchybar
# or
sketchybar --reload
```

**Hammerspoon**:
- Menu bar → Reload Config
- Or programmatically: `hs.reload()`

**Karabiner-Elements**:
- Changes apply automatically (no reload needed)

### Testing Changes

#### Verify Symlinks
```bash
# Check all symlinks are intact
ls -la ~/.config/* | grep "^l"
ls -la ~/.hammerspoon

# Verify targets exist
readlink ~/.config/aerospace
readlink ~/.hammerspoon
```

#### Test Specific Tools

**AeroSpace Window Management**:
```bash
# Check AeroSpace is running
pgrep -fl AeroSpace

# Test workspace switching (Ctrl+Alt+Shift+1-7)
# Test window focus (Ctrl+Alt+Shift+Arrows)
```

**Sketchybar Status Bar**:
```bash
# Check service status
brew services list | grep sketchybar

# Check for errors
tail -f ~/Library/Logs/sketchybar/sketchybar.log

# Test plugins manually
bash ~/.config/sketchybar/plugins/meeting.sh
```

**Hammerspoon Automation**:
```bash
# Open Hammerspoon console
open -a Hammerspoon

# Check console for Lua errors
# Test hotkeys (Ctrl+Alt+B for brightness toggle, etc.)
```

### Version Control Workflow

#### 1. Check Status
```bash
cd ~/dotfiles
git status
```

#### 2. Commit Changes
```bash
# Add specific files
git add config/hammerspoon/init.lua
git add config/aerospace/aerospace.toml

# Or add all changes
git add .

# Commit with descriptive message
git commit -m "feat: add brightness toggle hotkey to Hammerspoon"
```

#### 3. Push to Remote
```bash
git push origin main
```

#### 4. Deploy to Other Machines
```bash
# On another machine with dotfiles already set up
cd ~/dotfiles
git pull
./scripts/install.sh  # Re-run if symlinks need updating
```

## Build & Deployment

### No Build Step Required
This is a configuration management repository. There is no compilation or build process.

### Deployment Process

#### Fresh Machine Setup
```bash
# 1. Clone repo
git clone https://github.com/jahm2u/dotfiles.git ~/dotfiles

# 2. Run bootstrap
cd ~/dotfiles
./scripts/bootstrap.sh

# 3. Grant permissions (manual)
# Open System Settings → Privacy & Security

# 4. Restart applications
```

#### Updating Existing Setup
```bash
# 1. Pull latest changes
cd ~/dotfiles
git pull

# 2. Update packages (if Brewfile changed)
brew bundle

# 3. Symlinks should already be in place
# Run install.sh only if new tools added
./scripts/install.sh

# 4. Reload configs
aerospace reload-config
brew services restart sketchybar
# Hammerspoon → Reload Config
```

## Testing

### Manual Testing Checklist

#### Window Management
- [ ] AeroSpace tiling works correctly
- [ ] Workspace switching (Ctrl+Alt+Shift+1-7)
- [ ] Window focus navigation (Ctrl+Alt+Shift+Arrows)
- [ ] Moving windows between workspaces
- [ ] Sketchybar shows correct workspace indicators

#### Keyboard Shortcuts
- [ ] Caps Lock functions as Hyper key
- [ ] Hammerspoon hotkeys work:
  - [ ] Ctrl+Alt+B - Brightness toggle
  - [ ] Ctrl+Alt+Cmd+] - Audio cycle forward
  - [ ] Ctrl+Alt+Cmd+[ - Audio cycle backward
  - [ ] Ctrl+Alt+D - Translation (replace)
  - [ ] Option+S - Translation (popup)
  - [ ] Ctrl+Alt+G - Network latency check

#### Status Bar
- [ ] Sketchybar displays correctly
- [ ] Workspace indicators update
- [ ] System stats display (CPU, memory, network)
- [ ] Meeting widget shows next meeting
- [ ] Privacy mode toggles correctly (Ctrl+Alt+Cmd+P)

#### Automation
- [ ] Hammerspoon loads without errors
- [ ] Window positioning works
- [ ] Audio device switching functional
- [ ] Translation services operational

### Debugging

#### Check Logs

**Sketchybar**:
```bash
tail -f ~/Library/Logs/sketchybar/sketchybar.log
```

**Hammerspoon**:
- Open Hammerspoon app
- Window → Console
- Check for Lua errors

**AeroSpace**:
```bash
# Check if running
ps aux | grep -i aerospace

# Check config syntax
aerospace check-config
```

#### Common Issues

**Symlinks Broken**:
```bash
# Remove broken symlinks
find ~/.config -type l ! -exec test -e {} \; -delete

# Re-create all symlinks
cd ~/dotfiles
./scripts/install.sh
```

**Sketchybar Not Appearing**:
```bash
# Check service status
brew services list | grep sketchybar

# Restart service
brew services restart sketchybar

# Check for plugin errors
bash ~/.config/sketchybar/plugins/meeting.sh
```

**Hammerspoon Hotkeys Not Working**:
1. Check accessibility permissions
2. Open Hammerspoon console for errors
3. Reload config: Menu → Reload Config

**AeroSpace Not Tiling**:
1. Verify AeroSpace is running
2. Check accessibility permissions
3. Reload config: `aerospace reload-config`
4. Check syntax: `aerospace check-config`

## Environment Variables

### Sketchybar Calendar Integration
Create `.env` file in `config/sketchybar/`:

```bash
# config/sketchybar/.env
CALENDAR_URL_1="webcal://your-calendar-url-1"
CALENDAR_URL_2="webcal://your-calendar-url-2"
```

Then sync calendars:
```bash
bash ~/.config/sketchybar/plugins/sync_calendars.sh
```

## Scripts Reference

### Installation Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `bootstrap.sh` | Complete environment setup | `./scripts/bootstrap.sh` |
| `install.sh` | Create configuration symlinks | `./scripts/install.sh` |
| `setup-audio-multioutput.sh` | Configure multi-output audio device | `./scripts/setup-audio-multioutput.sh` |
| `position_authenticator.sh` | Position authenticator window | `./scripts/position_authenticator.sh` |

### Sketchybar Scripts

Located in `config/sketchybar/plugins/`:

| Plugin | Function |
|--------|----------|
| `aerospace_update_all.sh` | Update workspace indicators |
| `meeting.sh` | Display next meeting from calendar |
| `sync_calendars.sh` | Sync calendars from .env URLs |
| `todoist.sh` | Show Todoist task count |
| `volume.sh` | Display and control volume |
| `network.sh` | Show network status |
| `memory.sh` | Display memory usage |
| `front_app.sh` | Show active application |
| `wifi.sh` | Display WiFi status |

### Configuration Management

| Script | Purpose |
|--------|---------|
| `config_manager.sh` | Switch between config profiles |
| `toggle_config.sh` | Toggle privacy mode |

## Best Practices

### Configuration Changes
1. **Test locally first** - Make changes, test thoroughly
2. **Commit atomically** - One logical change per commit
3. **Descriptive commits** - Clear commit messages
4. **Document complex changes** - Add comments in configs
5. **Backup before major changes** - Install script does this automatically

### Maintenance
1. **Keep packages updated**:
   ```bash
   brew update
   brew upgrade
   brew bundle cleanup  # Remove packages not in Brewfile
   ```

2. **Review logs periodically**:
   ```bash
   tail ~/.config/sketchybar/error.log
   ```

3. **Clean up old backups**:
   ```bash
   find ~/.config -name "*.backup.*" -mtime +30 -delete
   ```

### Security
1. **Never commit secrets** - Use `.env` files (gitignored)
2. **Sensitive data** - Calendar URLs, API tokens go in `.env`
3. **Review changes** - Check `git diff` before committing
4. **Personal data** - Obsidian workspace layouts are gitignored

## Troubleshooting

### Reset Everything
```bash
# Remove all symlinks
rm ~/.hammerspoon
rm -rf ~/.config/aerospace
rm -rf ~/.config/sketchybar
rm -rf ~/.config/karabiner
rm -rf ~/.config/raycast
rm ~/.claude

# Fresh installation
cd ~/dotfiles
./scripts/install.sh
```

### Partial Reset (Single Tool)
```bash
# Example: Reset Hammerspoon only
rm ~/.hammerspoon
ln -sf ~/dotfiles/config/hammerspoon ~/.hammerspoon
```

### Verify Installation
```bash
# Check all symlinks point to correct locations
ls -la ~/.config/aerospace
ls -la ~/.config/sketchybar
ls -la ~/.config/karabiner
ls -la ~/.hammerspoon
ls -la ~/.claude

# Should all show → pointing to ~/dotfiles/config/...
```

## Additional Resources

### Official Documentation
- **AeroSpace**: https://nikitabobko.github.io/AeroSpace/
- **Sketchybar**: https://github.com/FelixKratz/SketchyBar
- **Hammerspoon**: https://www.hammerspoon.org/go/
- **Karabiner-Elements**: https://karabiner-elements.pqrs.org/
- **Raycast**: https://developers.raycast.com/

### Community Resources
- **Dotfiles Wiki**: https://dotfiles.github.io/
- **r/unixporn**: Community showcase and inspiration
- **Hammerspoon Spoons**: https://www.hammerspoon.org/Spoons/

---

*Generated by BMM Document Project workflow*
*Last Updated: 2026-01-13 (Exhaustive Rescan)*
