# Source Tree Analysis - Dotfiles Repository

## Overview

This document provides a comprehensive analysis of the dotfiles repository structure, highlighting critical directories, entry points, and organizational patterns.

## Repository Structure

```
dotfiles/
├── config/                     # Main configuration directory
│   ├── aerospace/              # AeroSpace window manager config
│   │   ├── aerospace.toml      # Main AeroSpace configuration
│   │   ├── workspace_change.sh # Workspace change handler
│   │   └── workspace_move.sh   # Workspace move handler
│   │
│   ├── sketchybar/             # Status bar configurations
│   │   ├── sketchybarrc        # Main config file
│   │   ├── sketchybarrc-desktop        # Desktop-specific config
│   │   ├── sketchybarrc-laptop         # Laptop-specific config
│   │   ├── sketchybarrc-*-privacy      # Privacy mode configs
│   │   ├── colors.sh           # Color scheme definitions
│   │   ├── config_manager.sh   # Configuration switching logic
│   │   ├── toggle_config.sh    # Privacy mode toggle
│   │   ├── plugins/            # Desktop plugins (production)
│   │   └── plugins-laptop/     # Laptop-specific plugins
│   │
│   ├── hammerspoon/            # macOS automation scripts
│   │   ├── init.lua            # Entry point - loads all modules
│   │   ├── update.lua          # Auto-update functionality
│   │   ├── Spoons/             # Hammerspoon extension modules
│   │   └── README.md           # Hammerspoon documentation
│   │
│   ├── karabiner/              # Keyboard remapping
│   │   ├── karabiner.json      # Main keyboard mapping config
│   │   ├── assets/             # Karabiner resources
│   │   └── automatic_backups/  # Auto-generated backups
│   │
│   ├── raycast/                # Raycast launcher
│   │   ├── config.json         # Raycast settings
│   │   └── extensions/         # Custom Raycast extensions
│   │
│   ├── obsidian/               # Obsidian note-taking
│   │   ├── *.json              # Core settings files
│   │   ├── plugins/            # Plugin configurations
│   │   └── workspace/          # Workspace layouts
│   │
│   ├── claude/                 # Claude AI assistant
│   │   ├── settings.json       # Claude Code settings
│   │   ├── config.json         # Claude configuration
│   │   ├── commands/           # Custom slash commands
│   │   ├── workflows/          # Workflow definitions
│   │   ├── hooks/              # Event hooks for notifications
│   │   ├── plugins/            # Plugin configurations
│   │   ├── history.jsonl       # Conversation history
│   │   └── statusline.sh       # Status line script
│   │
│   ├── khal/                   # Calendar application
│   │   └── config              # khal configuration
│   │
│   └── logs/                   # Shared log directory
│       ├── notifications.json  # Notification events
│       ├── stop.json           # Stop events
│       └── subagent_stop.json  # Subagent stop events
│
├── bmad/                       # BMAD Framework integration
│   ├── core/                   # BMAD Core module
│   │   ├── agents/             # Core agents
│   │   ├── workflows/          # Core workflows
│   │   ├── tasks/              # Reusable tasks
│   │   ├── tools/              # Utility tools
│   │   └── config.yaml         # Core configuration
│   │
│   ├── bmm/                    # BMad Method module
│   │   ├── agents/             # BMM agents (PM, Dev, Architect, etc.)
│   │   ├── workflows/          # BMM workflows (PRD, architecture, etc.)
│   │   ├── tasks/              # BMM-specific tasks
│   │   ├── teams/              # Team configurations
│   │   └── config.yaml         # BMM configuration
│   │
│   ├── bmb/                    # BMad Builder module
│   │   ├── agents/             # Builder agents
│   │   ├── workflows/          # Builder workflows
│   │   └── config.yaml         # Builder configuration
│   │
│   ├── cis/                    # Creative & Innovation Studio
│   │   ├── agents/             # Creative agents
│   │   ├── workflows/          # Creative workflows
│   │   ├── teams/              # Team configurations
│   │   └── config.yaml         # CIS configuration
│   │
│   ├── _cfg/                   # BMAD installation metadata
│   │   ├── manifest.yaml       # Module manifest
│   │   └── *-manifest.csv      # Component manifests
│   │
│   └── docs/                   # BMAD documentation
│       └── claude-code-instructions.md
│
├── scripts/                    # Installation and utility scripts
│   ├── install.sh              # Main symlink installer (entry point)
│   ├── bootstrap.sh            # Complete environment setup
│   ├── setup-audio-multioutput.sh   # Audio device configuration
│   └── position_authenticator.sh    # Window positioning helper
│
├── docs/                       # Project documentation
│   ├── bmm-workflow-status.md  # BMM workflow tracking
│   ├── project-scan-report.json     # Documentation scan state
│   ├── CHEATSHEET.md           # Quick reference guide
│   ├── technical-decisions-template.md  # Decision documentation template
│   └── stories/                # Development user stories
│
├── Brewfile                    # Homebrew package manifest
├── README.md                   # Main project documentation
├── CLAUDE.md                   # Claude AI context document
└── .gitignore                  # Git ignore rules

```

## Critical Directories

### Configuration Management (`config/`)

The heart of the dotfiles system. Each subdirectory contains complete configuration for a specific tool:

- **Purpose**: Centralized configuration storage
- **Deployment**: Symlinked to system locations by `scripts/install.sh`
- **Organization**: One directory per tool for clean separation

### Installation Scripts (`scripts/`)

**Entry Point**: `scripts/install.sh`

Scripts in this directory handle:
- Symlink creation to `~/.config/` and other system locations
- Backup of existing configurations
- Directory structure verification
- Bootstrap process (`bootstrap.sh` for complete setup)

### BMAD Framework (`bmad/`)

Integrated project management and development methodology framework:

- **Multi-module structure**: core, bmm, bmb, cis
- **Purpose**: AI-assisted development workflows
- **Integration**: Seamlessly embedded in dotfiles for development work
- **Key files**: `config.yaml` in each module, agents, workflows, tasks

## Entry Points

### 1. Initial Setup
**File**: `scripts/bootstrap.sh`
- Complete environment setup from scratch
- Installs Homebrew, all packages, creates all symlinks
- One-command deployment

### 2. Configuration Deployment
**File**: `scripts/install.sh`
- Creates symlinks for all configurations
- Backs up existing configs with timestamps
- Idempotent (safe to run multiple times)

### 3. Window Manager
**File**: `config/aerospace/aerospace.toml`
- AeroSpace entry point and main configuration
- Hooks for Sketchybar integration
- Workspace and tiling rules

### 4. Status Bar
**File**: `config/sketchybar/sketchybarrc`
- Loads appropriate config based on environment
- Delegates to desktop/laptop specific configs
- Manages plugins and visual elements

### 5. Automation Engine
**File**: `config/hammerspoon/init.lua`
- Hammerspoon entry point
- Loads all Spoons and custom modules
- Initializes hotkeys and watchers

### 6. Claude AI Integration
**File**: `config/claude/settings.json`
- Claude Code configuration
- Defines tool hooks and event handlers
- Integrates with BMAD workflows

## Integration Points

### AeroSpace ↔ Sketchybar
- **Hook**: `aerospace.toml` calls `sketchybar/plugins/aerospace_update_all.sh`
- **Purpose**: Update workspace indicators when workspace changes
- **Trigger**: On startup and workspace change events

### Hammerspoon ↔ System
- **Interface**: Lua API to macOS accessibility and automation features
- **Capabilities**: Window management, hotkeys, audio control, translation
- **Extensions**: Spoons directory contains modular functionality

### Karabiner ↔ Hyper Key
- **Mapping**: Caps Lock → Hyper (Cmd+Alt+Ctrl+Shift)
- **Purpose**: Unlock additional hotkey combinations
- **Integration**: Used by Hammerspoon and system shortcuts

### BMAD ↔ Claude
- **Connection**: Claude commands reference BMAD workflows
- **Location**: `.claude/commands/` links to `bmad/*/workflows/`
- **Purpose**: AI-assisted development methodology

### Sketchybar ↔ External Services
- **Calendar**: `khal` integration for meeting display
- **Task Management**: Todoist API integration
- **System Stats**: Network, CPU, memory monitoring plugins

## File Organization Patterns

### Configuration Files
- **TOML**: AeroSpace (`aerospace.toml`)
- **Lua**: Hammerspoon (`*.lua`)
- **JSON**: Claude, Karabiner, Obsidian, Raycast (`*.json`)
- **Shell**: Sketchybar config and plugins (`*.sh`, `sketchybarrc`)
- **YAML**: BMAD framework configurations (`config.yaml`)

### Naming Conventions
- **Sketchybar configs**: `sketchybarrc-{device}-{mode}`
  - Device: `desktop` | `laptop`
  - Mode: `(default)` | `privacy` | `minimal`
- **Plugins**: Descriptive names matching functionality (`meeting.sh`, `volume.sh`)
- **BMAD workflows**: Kebab-case with category prefixes

### Backup Strategy
- **Automatic**: Install script creates timestamped backups
- **Location**: `~/.config/{tool}.backup.{timestamp}`
- **Karabiner**: Built-in automatic backups in `automatic_backups/`

## Deployment Model

### Symlink Architecture
```
~/dotfiles/config/aerospace/aerospace.toml  →  ~/.config/aerospace/aerospace.toml
~/dotfiles/config/sketchybar/             →  ~/.config/sketchybar/
~/dotfiles/config/hammerspoon/            →  ~/.hammerspoon/
~/dotfiles/config/karabiner/              →  ~/.config/karabiner/
~/dotfiles/config/claude/                 →  ~/.claude/
~/dotfiles/config/raycast/                →  ~/.config/raycast/
~/dotfiles/config/khal/                   →  ~/.config/khal/
~/dotfiles/config/obsidian/               →  ~/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/.obsidian/
```

### Benefits
- **Live updates**: Edit files in repo, changes reflected immediately
- **Version control**: All configs in git
- **Portability**: Clone repo on new machine, run install script
- **No duplication**: Single source of truth

## Key Observations

1. **Multi-environment support**: Separate configs for desktop/laptop in Sketchybar
2. **Privacy mode**: Toggle configs hide sensitive information (meetings, tasks)
3. **BMAD integration**: Full project management framework embedded
4. **Modular design**: Each tool's config is self-contained
5. **Automation-first**: Heavy use of Hammerspoon for productivity
6. **AI integration**: Claude configurations and BMAD workflows for AI-assisted development
7. **Calendar integration**: khal + Sketchybar for meeting awareness
8. **Comprehensive**: Covers window management, automation, AI, notes, calendar, development

## Development Workflow

1. **Edit configs**: Make changes in `~/dotfiles/config/`
2. **Test immediately**: Changes reflect via symlinks
3. **Reload services**:
   - AeroSpace: `aerospace reload-config`
   - Sketchybar: `brew services restart sketchybar`
   - Hammerspoon: Menu → Reload Config
4. **Commit changes**: `git commit` in dotfiles repo
5. **Deploy elsewhere**: `git pull && ./scripts/install.sh` on other machines

---

*Generated by BMM Document Project workflow*
*Last Updated: 2026-01-13 (Exhaustive Rescan)*
