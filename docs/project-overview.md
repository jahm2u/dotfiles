# Project Overview - Dotfiles Configuration System

## Project Summary

**Name**: Personal Dotfiles Configuration Management System

**Type**: Infrastructure as Code (Configuration Management)

**Purpose**: Comprehensive macOS productivity environment configuration system using version-controlled, symlink-based deployment for portable and maintainable system setups.

**Repository**: https://github.com/jahm2u/dotfiles

## What is This Project?

This repository manages configuration files (dotfiles) for a complete macOS productivity environment. It provides a single source of truth for:

- **Window Management**: Automated tiling and workspace organization (AeroSpace)
- **Status Bar**: Customizable system monitoring and information display (Sketchybar)
- **Automation**: macOS scripting and hotkey management (Hammerspoon)
- **Keyboard Customization**: Advanced key remapping (Karabiner-Elements)
- **Launcher**: Quick access to applications and commands (Raycast)
- **Note-Taking**: Knowledge management system (Obsidian)
- **AI Assistant**: Development workflow integration (Claude + BMAD framework)
- **Calendar**: Terminal calendar with status bar integration (khal)

All configurations are:
- ✅ Version controlled in Git
- ✅ Deployed via symlinks for instant updates
- ✅ Portable across multiple machines
- ✅ Documented and maintainable

## Technology Stack

### Core Technologies

| Category | Technology | Version | Purpose |
|----------|-----------|---------|---------|
| **Package Manager** | Homebrew | 4.x | Application installation |
| **Version Control** | Git | 2.x | Configuration tracking |
| **Scripting** | Bash | 5.x | Automation, plugins |
| **Automation Language** | Lua | 5.4 | Hammerspoon scripting |
| **Config Formats** | TOML, JSON, YAML | Various | Application configs |
| **Runtime** | Node.js | 20.x | CLI tools, Claude |

### Application Stack

**Window & UI Management**:
- **AeroSpace** (0.13+) - Tiling window manager
- **Sketchybar** (2.x) - Custom status bar
- **Hammerspoon** (0.9+) - macOS automation framework

**Productivity Tools**:
- **Raycast** - Spotlight replacement and launcher
- **Obsidian** - Markdown-based knowledge management
- **Claude** - AI assistant with BMAD framework integration
- **khal** - Command-line calendar application
- **Karabiner-Elements** - Keyboard remapping

**Development Tools**:
- Warp (terminal), VS Code (editor), Postman (API testing)
- GitHub CLI, OrbStack (Docker alternative)
- Node.js ecosystem tools

**Communication & Productivity**:
- Slack, Telegram, Discord (communication)
- Mailspring (email), Todoist (tasks), Notion (workspace)

## Architecture Type

**Pattern**: Symlink-Based Configuration Management

```
Repository Structure:
~/dotfiles/config/{tool}/  ──symlink──▶  ~/.config/{tool}/

Deployment Model:
1. Clone repository
2. Run install script
3. Symlinks created automatically
4. Changes in repo = changes in system
```

**Benefits**:
- Single source of truth
- Instant configuration updates
- Easy multi-machine synchronization
- Full version control history

## Repository Structure

### High-Level Organization

```
dotfiles/
├── config/           # All tool configurations (symlinked to system)
├── bmad/            # BMAD framework (AI-assisted development)
├── scripts/         # Installation and utility scripts
├── docs/            # Project documentation (this directory)
├── Brewfile         # Homebrew package manifest
└── README.md        # Main documentation
```

### Key Directories

| Directory | Purpose | Target Location |
|-----------|---------|-----------------|
| `config/aerospace/` | Window manager config | `~/.config/aerospace/` |
| `config/sketchybar/` | Status bar with plugins | `~/.config/sketchybar/` |
| `config/hammerspoon/` | Automation scripts | `~/.hammerspoon/` |
| `config/karabiner/` | Keyboard mappings | `~/.config/karabiner/` |
| `config/claude/` | AI assistant config | `~/.claude/` |
| `config/raycast/` | Launcher settings | `~/.config/raycast/` |
| `config/obsidian/` | Note-taking config | iCloud location |
| `config/khal/` | Calendar config | `~/.config/khal/` |
| `bmad/` | AI workflow framework | N/A (used by Claude) |
| `scripts/` | Installation scripts | N/A (executed manually) |
| `docs/` | Documentation | N/A (reference) |

## Quick Reference

### Installation Commands

```bash
# Complete setup (new machine)
git clone https://github.com/jahm2u/dotfiles.git ~/dotfiles && cd ~/dotfiles && ./scripts/bootstrap.sh

# Config-only deployment (apps already installed)
cd ~/dotfiles && ./scripts/install.sh

# Package installation only
cd ~/dotfiles && brew bundle
```

### Service Management

```bash
# Start/restart services
open -a AeroSpace
brew services restart sketchybar
# Hammerspoon: Menu bar → Reload Config

# Check service status
pgrep -fl AeroSpace
brew services list | grep sketchybar
```

### Key Shortcuts (Highlights)

| Shortcut | Action |
|----------|--------|
| **Ctrl+Alt+Shift+Arrows** | Focus window in direction |
| **Ctrl+Alt+Shift+1-7** | Switch to workspace |
| **Ctrl+Alt+Cmd+]** | Cycle audio device forward |
| **Ctrl+Alt+D** | Translate selected text |
| **Ctrl+Alt+B** | Toggle screen brightness |
| **Ctrl+Alt+Cmd+P** | Toggle Sketchybar privacy mode |
| **Caps Lock** | Hyper key (Cmd+Alt+Ctrl+Shift) |

### File Locations

| What | Where |
|------|-------|
| Repository | `~/dotfiles/` |
| Config source | `~/dotfiles/config/` |
| System configs | `~/.config/` (symlinks) |
| Hammerspoon | `~/.hammerspoon/` (symlink) |
| Claude | `~/.claude/` (symlink) |
| Logs | `~/Library/Logs/sketchybar/` |

## Project Features

### ✨ Highlights

1. **Complete Environment in One Repo**
   - All productivity tool configurations
   - Package management (Brewfile)
   - Automated deployment scripts
   - Comprehensive documentation

2. **Instant Synchronization**
   - Edit file in repo → immediate system effect
   - No manual copy/paste of configs
   - Git tracks all changes

3. **Multi-Machine Support**
   - Same repo works on desktop and laptop
   - Device-specific configurations (Sketchybar)
   - Privacy mode for sensitive information

4. **Deep System Integration**
   - Window manager ↔ Status bar communication
   - Keyboard remapping unlocks custom shortcuts
   - Automation responds to system events
   - Calendar ↔ Task ↔ Status bar integration

5. **AI-Powered Development**
   - BMAD framework embedded in repo
   - Claude integration for AI assistance
   - Workflow automation for development tasks

6. **Modular & Extensible**
   - Sketchybar plugin system
   - Hammerspoon Spoon architecture
   - Easy to add new tools and configs

### 🎯 Use Cases

**For Productivity Enthusiasts**:
- Automated window management
- Real-time system monitoring in status bar
- Global hotkeys for common tasks
- Calendar awareness (meeting reminders)

**For Developers**:
- Full development environment config
- AI-assisted coding workflows
- Version-controlled development setup
- Quick machine provisioning

**For macOS Power Users**:
- Deep system customization
- Keyboard-driven workflows
- Custom automation scripts
- Advanced key mapping (Hyper key)

**For Multi-Machine Users**:
- Sync configs across devices
- Device-specific optimizations
- Single repo, multiple environments
- Easy new machine setup

## Getting Started

### Prerequisites

- macOS (tested on Sonoma 14.0+)
- ~2GB disk space
- Basic command-line familiarity

### Installation (3 Steps)

1. **Clone the repository**:
   ```bash
   git clone https://github.com/jahm2u/dotfiles.git ~/dotfiles
   cd ~/dotfiles
   ```

2. **Run bootstrap script**:
   ```bash
   ./scripts/bootstrap.sh
   ```
   This installs Homebrew, all applications, fonts, and creates symlinks.

3. **Grant permissions**:
   - System Settings → Privacy & Security → Accessibility
   - Enable: AeroSpace, Hammerspoon, Karabiner-Elements, Raycast

### First Steps After Installation

1. **Verify symlinks**: `ls -la ~/.config/` (look for `->` arrows)
2. **Start services**: Open AeroSpace, restart Sketchybar
3. **Test hotkeys**: Try `Ctrl+Alt+Shift+1` (workspace switch)
4. **Check status bar**: Should appear at top of screen
5. **Review documentation**: Read `docs/CHEATSHEET.md` for shortcuts

## Integration Ecosystem

### Tool Integration Map

```
┌─────────────────────────────────────────────────────────┐
│                    macOS System                         │
└─────────────────────────────────────────────────────────┘
              │
              ▼
┌───────────────────────────────────────────────────────────┐
│  AeroSpace ─────▶ Sketchybar (workspace indicators)       │
│     │                    │                                 │
│     │                    ▼                                 │
│     │              khal ─────▶ Meeting plugin              │
│     │                                                       │
│     ▼                                                       │
│  Hammerspoon ──▶ Window positioning, hotkeys              │
│     │                                                       │
│     ▼                                                       │
│  Karabiner ────▶ Hyper key ──▶ Custom shortcuts           │
│                                                             │
│  Claude ───────▶ BMAD workflows ──▶ AI-assisted dev       │
└───────────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│        ~/dotfiles (Git Repository)                      │
│        Single Source of Truth                           │
└─────────────────────────────────────────────────────────┘
```

### Key Integrations

1. **AeroSpace → Sketchybar**: Workspace change hooks update status bar
2. **Karabiner → Hammerspoon**: Hyper key enables custom automation hotkeys
3. **khal → Sketchybar**: Calendar events displayed in status bar
4. **Claude → BMAD**: AI workflows for development processes
5. **Hammerspoon → macOS**: System-wide automation and scripting

## Development & Maintenance

### Making Changes

1. Edit files in `~/dotfiles/config/`
2. Changes reflected immediately (symlinks)
3. Test changes
4. Commit to git: `git add . && git commit -m "description"`
5. Push to remote: `git push`

### Deploying to New Machine

```bash
git clone https://github.com/jahm2u/dotfiles.git ~/dotfiles
cd ~/dotfiles
./scripts/bootstrap.sh
# Grant permissions manually
# Done!
```

### Updating Existing Setup

```bash
cd ~/dotfiles
git pull
brew bundle  # If packages changed
# Symlinks already in place, changes active immediately
```

## Documentation Index

This repository includes comprehensive documentation:

- **README.md** - Main project documentation with setup instructions
- **CLAUDE.md** - Context for Claude AI assistant
- **docs/CHEATSHEET.md** - Quick reference for keyboard shortcuts
- **docs/architecture.md** - Detailed architecture documentation (this doc)
- **docs/development-guide.md** - Development and testing guide
- **docs/source-tree-analysis.md** - Repository structure analysis
- **config/hammerspoon/README.md** - Hammerspoon-specific documentation
- **bmad/docs/claude-code-instructions.md** - BMAD framework documentation

## Support & Resources

### Documentation
- **Local Docs**: `~/dotfiles/docs/`
- **Main README**: `~/dotfiles/README.md`
- **Cheat Sheet**: `~/dotfiles/docs/CHEATSHEET.md`

### Official Tool Documentation
- **AeroSpace**: https://nikitabobko.github.io/AeroSpace/
- **Sketchybar**: https://github.com/FelixKratz/SketchyBar
- **Hammerspoon**: https://www.hammerspoon.org/
- **Karabiner**: https://karabiner-elements.pqrs.org/

### Community
- **Dotfiles Wiki**: https://dotfiles.github.io/
- **r/unixporn**: Customization showcase
- **Hammerspoon Spoons**: https://www.hammerspoon.org/Spoons/

## Project Status

**Current Version**: Active Development

**Stability**: Production-ready for personal use

**Maintenance**: Regularly updated and maintained

**Compatibility**: macOS Sonoma (14.0+), works on Apple Silicon and Intel

## License

MIT License - See LICENSE file for details

## Acknowledgments

- **AeroSpace** by nikitabobko - Tiling window manager
- **Sketchybar** by FelixKratz - Status bar
- **Hammerspoon** community - Automation framework
- **Raycast** team - Launcher application

---

*Generated by BMM Document Project workflow*
*Date: 2025-10-27*
