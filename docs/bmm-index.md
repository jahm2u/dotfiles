# Dotfiles Repository - Documentation Index

**Primary Entry Point for AI-Assisted Development**

---

## Project Overview

**Name**: Personal Dotfiles Configuration Management System
**Type**: Infrastructure as Code (Configuration Management)
**Architecture**: Symlink-based deployment, monolith repository
**Target Platform**: macOS (Apple Silicon & Intel)
**Project Level**: 2 (Brownfield - Enhancement)

### Quick Summary

This repository manages a comprehensive macOS productivity environment using version-controlled configuration files deployed via symlinks. It integrates window management (AeroSpace), status bar (Sketchybar), automation (Hammerspoon), keyboard customization (Karabiner), AI assistance (Claude + BMAD), and productivity tools (Obsidian, Raycast, khal) into a unified, portable system.

**Key Value Proposition**: Single source of truth for entire macOS productivity setup. Clone repo → run script → complete environment ready.

---

## Quick Reference

### Technology Stack Summary

| Category | Primary Technology | Supporting Tools |
|----------|-------------------|------------------|
| **Package Management** | Homebrew | Brewfile for declarative packages |
| **Scripting** | Bash (5.x) | Shell scripts for plugins and automation |
| **Automation Language** | Lua (5.4) | Hammerspoon Spoons and scripts |
| **Config Formats** | TOML, JSON, YAML | Tool-specific configurations |
| **Version Control** | Git | GitHub for remote backup |
| **Window Management** | AeroSpace | TOML-based tiling configuration |
| **Status Bar** | Sketchybar | Plugin-based shell script system |
| **Keyboard** | Karabiner-Elements | JSON complex modifications |
| **AI Integration** | Claude + BMAD Framework | YAML workflows, MD commands |

### Architecture Pattern

**Symlink-Based Configuration Management**:
```
~/dotfiles/config/{tool}/ ──symlink──▶ ~/.config/{tool}/
                                       ~/.hammerspoon/
                                       ~/.claude/
```

**Benefits**: Instant updates, version control, portable, no duplication

---

## Project Structure

```
dotfiles/
├── config/                     # Main configurations (symlinked to system)
│   ├── aerospace/              # Window manager (TOML)
│   ├── sketchybar/             # Status bar (shell scripts + plugins)
│   ├── hammerspoon/            # Automation (Lua + Spoons)
│   ├── karabiner/              # Keyboard remapping (JSON)
│   ├── claude/                 # AI assistant (JSON + workflows)
│   ├── raycast/                # Launcher (JSON + extensions)
│   ├── obsidian/               # Notes (JSON configs)
│   └── khal/                   # Calendar (INI-style config)
│
├── bmad/                       # BMAD Framework (AI workflows)
│   ├── core/                   # Core workflows & agents
│   ├── bmm/                    # Business Model Method
│   ├── bmb/                    # BMad Builder
│   └── cis/                    # Creative & Innovation Studio
│
├── scripts/                    # Installation & utilities
│   ├── install.sh              # Symlink creator (main installer)
│   └── bootstrap.sh            # Complete environment setup
│
├── docs/                       # Project documentation
│   ├── bmm-index.md            # This file (master index)
│   ├── architecture.md         # Detailed architecture
│   ├── development-guide.md    # Dev setup & workflow
│   ├── source-tree-analysis.md # Directory structure
│   ├── project-overview.md     # High-level summary
│   └── CHEATSHEET.md           # Keyboard shortcuts
│
├── Brewfile                    # Homebrew package manifest
├── README.md                   # Main project documentation
└── CLAUDE.md                   # Claude AI context document
```

---

## Generated Documentation

### Primary Documentation Files

1. **[Project Overview](./project-overview.md)** ✓
   - Executive summary
   - Technology stack table
   - Quick start guide
   - Use cases and features
   - Getting started steps

2. **[Architecture](./architecture.md)** ✓
   - System architecture diagrams
   - Component descriptions (AeroSpace, Sketchybar, Hammerspoon, etc.)
   - Integration patterns
   - Data flow diagrams
   - Technology stack details
   - Performance considerations
   - Security & privacy

3. **[Source Tree Analysis](./source-tree-analysis.md)** ✓
   - Complete directory tree with annotations
   - Critical folders explained
   - Entry points documented
   - File organization patterns
   - Deployment model
   - Development workflow

4. **[Development Guide](./development-guide.md)** ✓
   - Prerequisites and installation
   - Post-installation setup
   - Development workflow
   - Testing procedures
   - Debugging techniques
   - Scripts reference
   - Troubleshooting

---

## Existing Documentation

### User-Created Documentation

1. **[README.md](../README.md)** - Main project documentation
   - Overview of all tools
   - Installation instructions
   - Keyboard shortcuts
   - Troubleshooting guide

2. **[CLAUDE.md](../CLAUDE.md)** - Claude AI assistant context
   - Repository overview
   - Core tools and configurations
   - Installation and management
   - Critical context and known issues
   - Development guidelines

3. **[CHEATSHEET.md](./CHEATSHEET.md)** - Quick reference
   - Keyboard shortcuts organized by tool
   - Common commands
   - Quick access reference

4. **[config/hammerspoon/README.md](../config/hammerspoon/README.md)** - Hammerspoon docs
   - Hammerspoon-specific configuration
   - Custom Spoons documentation

5. **[bmad/docs/claude-code-instructions.md](../bmad/docs/claude-code-instructions.md)**
   - BMAD framework instructions for Claude Code
   - Workflow definitions and usage

---

## Getting Started for AI Assistants

### Context for New Features

When planning new features or enhancements:

1. **Read this index first** - Understand overall structure
2. **Review architecture.md** - Understand integration patterns
3. **Check source-tree-analysis.md** - Locate relevant code
4. **Reference development-guide.md** - Follow development practices
5. **Consult CLAUDE.md** - Understand constraints and conventions

### Typical AI-Assisted Workflows

**Adding New Tool Configuration**:
1. Create directory in `config/`
2. Add configuration files
3. Update `scripts/install.sh` with symlink
4. Add to `Brewfile` if package install needed
5. Document in README.md

**Modifying Existing Config**:
1. Locate config in `config/{tool}/`
2. Make changes (live via symlinks)
3. Test immediately
4. Reload relevant service
5. Commit changes

**Creating Sketchybar Plugin**:
1. Create script in `config/sketchybar/plugins/`
2. Make executable: `chmod +x`
3. Register in `sketchybarrc`
4. Test: `bash ~/.config/sketchybar/plugins/plugin.sh`
5. Restart Sketchybar

**Creating Hammerspoon Spoon**:
1. Create directory: `config/hammerspoon/Spoons/Name.spoon/`
2. Implement `init.lua` in Spoon
3. Load in `config/hammerspoon/init.lua`
4. Reload Hammerspoon config
5. Test functionality

---

## Critical Integration Points

### 1. AeroSpace ↔ Sketchybar

**Purpose**: Update workspace indicators when user switches workspaces

**Mechanism**:
```toml
# aerospace.toml
exec-on-workspace-change = ['/bin/bash', '-c',
    'CONFIG_DIR=$HOME/.config/sketchybar \
     $HOME/.config/sketchybar/plugins/aerospace_update_all.sh \
     $AEROSPACE_FOCUSED_WORKSPACE'
]
```

**Files**:
- `config/aerospace/aerospace.toml` - Hook configuration
- `config/sketchybar/plugins/aerospace_update_all.sh` - Update handler

### 2. Karabiner ↔ Hammerspoon

**Purpose**: Caps Lock → Hyper key enables custom Hammerspoon hotkeys

**Mechanism**:
```json
// karabiner.json
"from": {"key_code": "caps_lock"},
"to": [{"key_code": "left_command", "modifiers": ["left_control", "left_option", "left_shift"]}]
```

**Result**: Hyper (Cmd+Alt+Ctrl+Shift) unlocks ~20 custom shortcuts

**Files**:
- `config/karabiner/karabiner.json` - Key mapping
- `config/hammerspoon/init.lua` - Hotkey bindings

### 3. khal ↔ Sketchybar

**Purpose**: Display next meeting in status bar

**Data Flow**:
```
.env (Calendar URLs)
    ↓
sync_calendars.sh
    ↓
khal (local DB)
    ↓
meeting.sh plugin
    ↓
Sketchybar display
```

**Files**:
- `config/sketchybar/.env` - Calendar URLs (gitignored)
- `config/sketchybar/plugins/sync_calendars.sh` - Sync script
- `config/sketchybar/plugins/meeting.sh` - Display plugin
- `config/khal/config` - Calendar config

### 4. Claude ↔ BMAD Framework

**Purpose**: AI-assisted development workflows

**Structure**:
```
.claude/commands/ → Slash commands
bmad/*/workflows/ → Workflow definitions
bmad/*/agents/    → Agent definitions
```

**Usage**: `/bmad:bmm:agents:analyst` invokes Business Analyst agent

**Files**:
- `config/claude/settings.json` - Claude settings
- `bmad/core/agents/bmad-master.md` - Master orchestrator
- `bmad/bmm/workflows/` - BMM workflows (PRD, architecture, dev)

---

## Entry Points by Task

### Configuration Changes

| Task | Entry File |
|------|------------|
| Window management rules | `config/aerospace/aerospace.toml` |
| Status bar plugins | `config/sketchybar/plugins/*.sh` |
| Keyboard shortcuts | `config/hammerspoon/init.lua` |
| Key remapping | `config/karabiner/karabiner.json` |
| AI workflows | `config/claude/workflows/` or `bmad/*/workflows/` |

### Installation & Deployment

| Task | Entry Script |
|------|-------------|
| Fresh machine setup | `scripts/bootstrap.sh` |
| Config deployment only | `scripts/install.sh` |
| Package installation | `brew bundle` (uses `Brewfile`) |

### Service Management

| Task | Command |
|------|---------|
| Reload AeroSpace | `aerospace reload-config` |
| Restart Sketchybar | `brew services restart sketchybar` |
| Reload Hammerspoon | Menu bar → Reload Config |
| Verify symlinks | `ls -la ~/.config/` (check for `->`) |

---

## Development Workflow for AI

### Standard Change Workflow

1. **Understand requirement**
   - Review relevant documentation
   - Identify affected components
   - Check integration points

2. **Locate files**
   - Use source-tree-analysis.md
   - Navigate to `config/{tool}/`
   - Review existing implementation

3. **Make changes**
   - Edit files in repository
   - Changes reflect immediately (symlinks)
   - No build step required

4. **Test**
   - Reload relevant service
   - Verify functionality
   - Check for errors in logs

5. **Document**
   - Update README if user-facing
   - Update CLAUDE.md if AI-relevant
   - Add comments for complex logic

6. **Commit**
   - Descriptive commit message
   - Atomic commits (one logical change)

### Testing Locations

| Component | Test Method |
|-----------|-------------|
| AeroSpace | Try workspace switching, window movement |
| Sketchybar | Check status bar display, run plugin manually |
| Hammerspoon | Test hotkeys, check console for errors |
| Karabiner | Test key mappings |

### Log Locations

| Component | Log Location |
|-----------|-------------|
| Sketchybar | `~/Library/Logs/sketchybar/sketchybar.log` |
| Hammerspoon | App → Console window |
| AeroSpace | `aerospace check-config` for syntax validation |

---

## Common AI Tasks

### Task: Add New Sketchybar Plugin

**Steps**:
1. Create plugin: `touch config/sketchybar/plugins/newplugin.sh`
2. Make executable: `chmod +x config/sketchybar/plugins/newplugin.sh`
3. Implement plugin (fetch data, call `sketchybar --set`)
4. Register in `config/sketchybar/sketchybarrc`
5. Test: `bash ~/.config/sketchybar/plugins/newplugin.sh`
6. Restart Sketchybar

**Files to modify**:
- `config/sketchybar/plugins/newplugin.sh` (new file)
- `config/sketchybar/sketchybarrc` (add registration)

### Task: Add New Hammerspoon Hotkey

**Steps**:
1. Open `config/hammerspoon/init.lua`
2. Add hotkey binding:
   ```lua
   hs.hotkey.bind({"ctrl", "alt", "cmd"}, "K", function()
       -- Your action here
   end)
   ```
3. Reload Hammerspoon
4. Test hotkey

**Files to modify**:
- `config/hammerspoon/init.lua`

### Task: Add New Tool Configuration

**Steps**:
1. Create directory: `mkdir config/newtool`
2. Copy configs: `cp ~/.config/newtool/* config/newtool/`
3. Update install script: Add symlink in `scripts/install.sh`
4. Add to Brewfile: `brew "newtool"` or `cask "newtool"`
5. Document in README.md
6. Test: `./scripts/install.sh`

**Files to modify**:
- `config/newtool/*` (new directory)
- `scripts/install.sh` (add symlink)
- `Brewfile` (add package)
- `README.md` (document)

---

## Next Steps

### For AI Assistants Starting Work

1. ✅ **Read this index** (you're here!)
2. ✅ **Review [architecture.md](./architecture.md)** - Understand system design
3. ✅ **Scan [source-tree-analysis.md](./source-tree-analysis.md)** - Know where things are
4. ✅ **Check [development-guide.md](./development-guide.md)** - Development practices
5. ✅ **Consult [CLAUDE.md](../CLAUDE.md)** - AI-specific context

### For Planning New Features

1. Determine affected components (AeroSpace, Sketchybar, Hammerspoon, etc.)
2. Review existing integration patterns
3. Identify files to modify
4. Plan testing approach
5. Document changes

### For Brownfield PRD Creation

When using this documentation for a brownfield PRD:
- Reference this index for complete system understanding
- Link to architecture.md for technical details
- Use source-tree-analysis.md for file locations
- Follow integration patterns for new features
- Maintain symlink-based deployment model

---

## Maintenance Status

**Generated**: 2025-10-27
**Last Rescanned**: 2026-01-13 (Exhaustive)
**Documentation Version**: 1.1
**Scan Level**: Exhaustive
**Project Status**: Active development, production-ready

---

## Key Constraints & Conventions

### From CLAUDE.md

1. **Hyper Key**: Cannot combine with other modifiers (it IS all modifiers)
2. **Spatial Navigation**: Use arrows not numbers for workspace nav
3. **Path References**: Use `~` or `$HOME`, avoid hardcoded paths
4. **Privacy Mode**: Sketchybar configs hide sensitive info when toggled
5. **Calendar URLs**: Store in `.env` files (gitignored)
6. **Symlink Targets**: Some apps require non-standard locations (Hammerspoon → `~/.hammerspoon/`)

### Development Guidelines

1. **Test locally first** - Changes are live via symlinks
2. **Atomic commits** - One logical change per commit
3. **Descriptive messages** - Clear commit descriptions
4. **Document complex changes** - Add comments
5. **Backup automatically** - Install script handles this

---

## Support Resources

### Documentation
- **This Index**: Primary AI reference point
- **README.md**: User-facing documentation
- **CLAUDE.md**: AI assistant context
- **Architecture Docs**: `docs/architecture.md`, `docs/development-guide.md`

### Official Tool Docs
- **AeroSpace**: https://nikitabobko.github.io/AeroSpace/
- **Sketchybar**: https://github.com/FelixKratz/SketchyBar
- **Hammerspoon**: https://www.hammerspoon.org/
- **Karabiner**: https://karabiner-elements.pqrs.org/

---

*This index is the primary entry point for AI-assisted development on this dotfiles repository. All paths are relative to repository root (`~/dotfiles/`).*

**Generated by**: BMM Document Project Workflow
**Last Updated**: 2026-01-13 (Exhaustive Rescan)
**Maintained By**: Automated documentation system
