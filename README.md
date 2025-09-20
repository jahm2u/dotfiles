# 🏠 Personal Dotfiles

A comprehensive dotfiles management system for macOS productivity and development workflow.

## 📋 Overview

This repository contains configuration files for various productivity tools, window managers, and development utilities, organized for easy management and deployment via symlinks.

## 🛠 Tools & Applications

### Window Management & UI
- **🚀 AeroSpace** - Tiling window manager for macOS
- **📊 SketchyBar** - Customizable status bar
- **⌨️ Karabiner-Elements** - Keyboard customization

### Development Tools
- **💻 Warp** - Modern terminal with AI features
- **🆚 Visual Studio Code** - Code editor
- **📮 Postman** - API development and testing
- **🐳 Docker Desktop** - Containerization platform
- **⚙️ Node.js 20** - JavaScript runtime
- **🐙 GitHub CLI** - GitHub command line tool
- **🤖 Claude CLI** - Claude AI command line interface
- **📟 Codex CLI** - Codex command line tool

### Communication & Productivity
- **💬 Slack** - Team communication
- **📱 Telegram** - Messaging app
- **📧 Mailspring** - Email client
- **✅ Todoist** - Task management
- **📚 Notion** - All-in-one workspace
- **🎮 Discord** - Gaming and community chat

### Security & Utilities
- **🔒 Tresorit** - Secure cloud storage
- **🔌 Pritunl** - VPN client

### Entertainment & Browsers
- **🎵 Spotify** - Music streaming
- **🌐 Google Chrome** - Web browser
- **🦊 Firefox** - Web browser

### Configuration & Automation  
- **🔨 Hammerspoon** - macOS automation and scripting
- **🔍 Raycast** - Spotlight replacement with extensions
- **📝 Obsidian** - Knowledge management vault
- **🧠 Claude** - AI assistant configuration
- **📅 Khal** - Calendar application

### Fonts & Typography
- **🔤 JetBrains Mono Nerd Font** - Required for sketchybar and terminal icons


## 📁 Project Structure

```
dotfiles/
├── .claude/                    # Claude AI assistant configs (root level)
├── config/                     # Main configuration directory
│   ├── aerospace/              # AeroSpace window manager & config
│   ├── hammerspoon/            # Hammerspoon automation scripts
│   ├── karabiner/              # Keyboard mapping configs  
│   ├── obsidian/               # Obsidian vault configurations
│   ├── raycast/                # Raycast launcher configs
│   └── sketchybar/             # Status bar configurations
├── scripts/
│   └── install.sh              # Automated symlink installer
├── docs/                       # Documentation
├── PLAN.md                     # Implementation progress
├── FUTURE_PLANS.md             # Enhancement roadmap
├── README.md                   # This file
└── vps_setup.sh               # VPS deployment script
```

## ⚡ Quick Start (One-Liner)

```bash
git clone https://github.com/jahm2u/dotfiles.git ~/dotfiles && cd ~/dotfiles && ./scripts/bootstrap.sh
```

## 🚀 Complete Environment Setup

For a complete development environment with all applications and tools:

```bash
# Clone the repository
git clone https://github.com/jahm2u/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Run the bootstrap script (installs everything)
./scripts/bootstrap.sh
```

The bootstrap script will:
- Install/update Homebrew
- Install all applications via Brewfile (25+ packages including dev tools, browsers, communication apps)
- Set up all configuration symlinks (calls install.sh automatically)
- Install JetBrains Mono Nerd Font for sketchybar
- Configure Node.js and CLI tools (GitHub CLI, Claude CLI)
- Verify installations and provide next steps

## 📦 Manual Package Installation

If you prefer to install packages manually:

```bash
# Install packages from Brewfile
brew bundle

# Or just set up config symlinks
./scripts/install.sh
```

## 🚀 Detailed Setup

### Prerequisites

1. **Homebrew** (macOS package manager)
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

2. **Required Applications**
```bash
# Install core applications
brew install --cask nikitabobko/tap/aerospace
brew install FelixKratz/formulae/sketchybar  
brew install --cask hammerspoon
brew install --cask raycast
brew install --cask obsidian
```

### Installation

1. **Clone Repository**
```bash
git clone <repository-url> ~/dotfiles
cd ~/dotfiles
```

2. **Run Installation Script**
```bash
./scripts/install.sh
```

The script will:
- Create necessary directories
- Back up existing configurations
- Create symlinks for all configs
- Provide post-installation instructions

### Manual Configuration

If you prefer manual setup:

```bash
# AeroSpace
ln -sf ~/dotfiles/config/aerospace/aerospace.toml ~/.config/aerospace/aerospace.toml

# SketchyBar  
ln -sf ~/dotfiles/config/sketchybar ~/.config/sketchybar

# Karabiner
ln -sf ~/dotfiles/config/karabiner ~/.config/karabiner

# Hammerspoon
ln -sf ~/dotfiles/config/hammerspoon ~/.hammerspoon

# Raycast
ln -sf ~/dotfiles/config/raycast ~/.config/raycast

# Obsidian (to iCloud location)
ln -sf ~/dotfiles/config/obsidian "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/.obsidian"

# Claude (root level)
ln -sf ~/dotfiles/.claude ~/.claude
```

## 🔧 Post-Installation

1. **Start Services**
```bash
# Start AeroSpace
open -a AeroSpace

# Start SketchyBar  
brew services start sketchybar

# Reload Hammerspoon (if already running)
# Use Hammerspoon menu or: hs.reload()
```

2. **Verify Installation**
- AeroSpace: Should start tiling windows automatically
- SketchyBar: Custom status bar should appear
- Hammerspoon: Check menu bar for Hammerspoon icon
- Raycast: Press ⌘+Space (or your configured hotkey)

## 🎯 Key Features

### Repository Optimization
- **Lightweight**: Obsidian config optimized from 84MB to 188KB (99.8% reduction)
- **Essential-only**: Includes settings and plugin configurations, excludes binaries and cache
- **Smart .gitignore**: Prevents accidental inclusion of large files and personal workspace layouts

### AeroSpace Configuration
- **Tiling Window Management**: Automatic window organization
- **Multi-monitor Support**: Seamless workspace management
- **Custom Keybindings**: Vim-style navigation

### SketchyBar Setup
- **System Monitoring**: CPU, memory, network stats
- **Workspace Integration**: AeroSpace workspace indicators
- **Custom Styling**: Minimal, informative design

### Hammerspoon Automation
- **Window Management**: Advanced window positioning
- **Application Shortcuts**: Quick app switching
- **Custom Workflows**: Personalized automation scripts
- **Audio Device Control**: Cycle through audio outputs with volume control
- **Translation**: Instant text translation between English and Portuguese

### Raycast Extensions
- **Quick Actions**: System controls and shortcuts  
- **Custom Commands**: Workflow automation
- **Extension Ecosystem**: Productivity boosters

## ⌨️ Keyboard Shortcuts

### Hammerspoon Shortcuts

#### Audio Control
- **Ctrl+Option+Cmd+]** - Cycle audio forward (0% → 33% → 66% → 100% → next device)
- **Ctrl+Option+Cmd+[** - Cycle audio backward (100% → 66% → 33% → 0% → previous device)
  - Works with all audio devices (Mac speakers, LG monitors, Multi-Output Device)
  - Multi-Output Device controls both LG monitors simultaneously

#### Translation (English ↔ Portuguese)
- **Ctrl+Alt+D** or **Option+D** - Replace selected text with translation
- **Option+S** - Show translation in popup overlay

#### System Controls
- **Ctrl+Alt+B** - Toggle screen brightness (0% ↔ saved level)
- **Ctrl+Alt+Cmd+O** - Toggle dock auto-hide
- **Ctrl+Alt+Cmd+P** - Toggle Sketchybar privacy mode (hides meetings/Todoist)

#### Utilities
- **Ctrl+Alt+G** - Check network latency (ping test)
- **Cmd+Shift+E** - Open inbox (via Shortcuts)
- **Shift+Delete** - Forward delete
- **Option+Space** - Trigger Spotlight/Raycast (maps to Cmd+Space)
- **Option+Tab** - App switcher (maps to Cmd+Tab)

### AeroSpace Window Manager
- See `config/aerospace/aerospace.toml` for full keybindings
- Uses Ctrl+Alt+Shift as primary modifier
- Spatial navigation with arrow keys

### Karabiner-Elements
- **Caps Lock** - Hyper key (Cmd+Alt+Ctrl+Shift)

## 🔄 Updating Configurations

To update configurations:

1. **Edit files in the dotfiles repository**
2. **Changes reflect immediately** (via symlinks)
3. **Commit changes to version control**

```bash
# Example: Update Hammerspoon config
vim ~/dotfiles/config/hammerspoon/init.lua
# Changes are immediately active via symlink
```

## 🚨 Troubleshooting

### Quick Health Check
```bash
# Verify all symlinks are working
ls -la ~/.config/* | grep "^l" && echo "✓ Symlinks intact"

# Check if all applications can be launched
open -a AeroSpace && echo "✓ AeroSpace OK"
open -a Raycast && echo "✓ Raycast OK" 
brew services list | grep -E "(sketchybar|running)" && echo "✓ SketchyBar OK"
```

### Common Issues

1. **Installation Script Fails**
   - **Existing files/symlinks**: Script automatically backs up existing configs with timestamp
   - **Permission denied**: Don't run with `sudo` - check file ownership and permissions
   - **Homebrew not found**: Install Homebrew first: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
   - **Git repository access**: Ensure you have access to the GitHub repository

2. **Symlinks not working**
   - Check file permissions: `ls -la ~/.config`
   - Verify paths in install script match your actual directory structure
   - Validate targets exist: `ls -la ~/dotfiles/config/`
   - Fix broken symlinks: Re-run `./scripts/install.sh`

3. **Applications not finding configs**
   - **Restart required**: Many apps need restart to detect new configs
   - **Check symlink targets**: `readlink ~/.hammerspoon` should point to your dotfiles
   - **Application-specific paths**: Some apps have non-standard config locations
   - **macOS version differences**: Configs may vary between macOS versions

4. **AeroSpace Issues**
   - **Not tiling**: Check if AeroSpace is running in Activity Monitor
   - **Config errors**: Validate aerospace.toml syntax
   - **Permissions**: Grant accessibility permissions in System Settings > Privacy & Security

5. **SketchyBar Problems**
   - **Not appearing**: `brew services list | grep sketchybar` should show "started"
   - **Restart service**: `brew services restart sketchybar`
   - **Plugin errors**: Check plugins directory permissions and script executability
   - **Memory usage**: SketchyBar scripts may consume CPU if misconfigured

6. **Hammerspoon Issues**  
   - **Scripts not loading**: Check Hammerspoon console for Lua errors
   - **Permissions needed**: Grant accessibility and automation permissions
   - **Spoons not working**: Verify Spoons directory structure is intact
   - **Reload config**: Use Hammerspoon menu > "Reload Config"

7. **Raycast Problems**
   - **Extensions missing**: Check if extensions copied correctly to config
   - **Shortcuts not working**: Verify no conflicts with system shortcuts
   - **Database corruption**: May need to reset Raycast if config is severely corrupted

8. **Obsidian Configuration**
   - **iCloud sync issues**: Ensure iCloud is enabled and syncing
   - **Plugin reinstall needed**: Plugin binaries are excluded - let Obsidian download them automatically
   - **Settings preserved**: Plugin configurations (data.json) are included and will be restored
   - **Vault not found**: Verify the iCloud path is correct for your system

### Recovery Options

**Full Reset**
```bash
# Remove all symlinks (if needed)
rm ~/.hammerspoon ~/.config/aerospace ~/.config/sketchybar ~/.config/karabiner ~/.config/raycast

# Restore from backups (created automatically by install script)
ls -la ~/.*backup* ~/.config/*backup*

# Fresh installation
cd ~/dotfiles && ./scripts/install.sh
```

**Partial Reset**
```bash
# Reset specific application (example: Hammerspoon)
rm ~/.hammerspoon
ln -sf ~/dotfiles/config/hammerspoon ~/.hammerspoon
```

### Getting Help

- **AeroSpace**: [Documentation](https://nikitabobko.github.io/AeroSpace/)
- **SketchyBar**: [GitHub Repository](https://github.com/FelixKratz/SketchyBar)
- **Hammerspoon**: [Getting Started Guide](https://www.hammerspoon.org/go/)

## 📝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- [AeroSpace](https://github.com/nikitabobko/AeroSpace) by nikitabobko
- [SketchyBar](https://github.com/FelixKratz/SketchyBar) by FelixKratz
- [Hammerspoon](https://www.hammerspoon.org/) community
- [Raycast](https://raycast.com/) team

---

*Last updated: $(date)*