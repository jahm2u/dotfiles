# Architecture Documentation - Dotfiles Configuration System

## Executive Summary

This dotfiles repository implements a comprehensive macOS productivity environment configuration management system using a symlink-based deployment strategy. The architecture enables version-controlled, portable, and maintainable system configurations across multiple tools and applications.

**Key Characteristics:**
- **Type**: Infrastructure as Code (Configuration Management)
- **Deployment Model**: Symlink-based from central repository
- **Version Control**: Git-managed configurations
- **Target Platform**: macOS (Apple Silicon and Intel)
- **Integration Level**: Deep system integration via accessibility APIs
- **Scope**: Window management, automation, AI assistance, note-taking, calendar

**Current Enhancement (2025-10-28):** This architecture document has been updated with architectural decisions for two new epic implementations: Environment Configuration (multi-environment support with Brazil color scheme) and Calendar Automation (zero-touch calendar synchronization). See "New Feature Implementation Architecture" section below.

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         macOS System                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  AeroSpace   │  │  Sketchybar  │  │ Hammerspoon  │      │
│  │  (Window     │  │  (Status     │  │  (Automation │      │
│  │   Manager)   │  │   Bar)       │  │   Engine)    │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
│         │                  │                  │              │
│         └──────────────────┼──────────────────┘              │
│                           │                                 │
│  ┌──────────────┐  ┌──────▼───────┐  ┌──────────────┐      │
│  │  Karabiner   │  │   Raycast    │  │   Obsidian   │      │
│  │  (Keyboard)  │  │  (Launcher)  │  │   (Notes)    │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │    Claude    │  │     khal     │  │   Homebrew   │      │
│  │    (AI)      │  │  (Calendar)  │  │   (Packages) │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
        ┌───────────────────────────────────────┐
        │     ~/dotfiles Repository (Git)       │
        ├───────────────────────────────────────┤
        │                                       │
        │  config/  ──symlinks──▶ ~/.config/   │
        │  scripts/ ──installs──▶ symlinks     │
        │  bmad/    ──integrates─▶ workflows   │
        │  docs/    ──documents─▶ system       │
        │                                       │
        └───────────────────────────────────────┘
```

## Architecture Patterns

### 1. Symlink-Based Configuration Management

**Pattern**: Central Repository with Symlink Deployment

**Implementation**:
```bash
# Repository Structure
~/dotfiles/config/{tool}/  →  Symlink Target

# Deployed Structure
~/.config/{tool}/  ←  Symlink to ~/dotfiles/config/{tool}/
```

**Benefits**:
- Single source of truth for all configurations
- Changes in repository immediately reflected system-wide
- Version control tracks all configuration history
- Easy deployment to new machines (clone + run install script)
- No configuration duplication

**Trade-offs**:
- Requires symlink creation step (handled by install.sh)
- Symlink targets must be compatible with application expectations
- Some apps require specific paths (Hammerspoon → `~/.hammerspoon`, not `~/.config/`)

### 2. Event-Driven Integration

**Pattern**: Hook-Based Communication Between Tools

**Example: AeroSpace → Sketchybar Integration**

```toml
# aerospace.toml
exec-on-workspace-change = [
    '/bin/bash', '-c',
    'CONFIG_DIR=$HOME/.config/sketchybar \
     $HOME/.config/sketchybar/plugins/aerospace_update_all.sh \
     $AEROSPACE_FOCUSED_WORKSPACE'
]
```

**Flow**:
1. User switches workspace in AeroSpace
2. AeroSpace triggers `exec-on-workspace-change` hook
3. Hook executes Sketchybar plugin script
4. Plugin updates workspace indicators in status bar
5. Visual feedback appears in under 100ms

**Benefits**:
- Loose coupling between components
- Real-time synchronization of UI state
- Extensible via plugin system

### 3. Multi-Environment Configuration

**Pattern**: Environment-Specific Config Selection

**Implementation in Sketchybar**:
```
sketchybarrc           # Dispatcher (selects appropriate config)
sketchybarrc-desktop   # Desktop-specific settings
sketchybarrc-laptop    # Laptop-specific settings
sketchybarrc-*-privacy # Privacy mode variants
```

**Selection Logic**:
```bash
# config_manager.sh determines environment
if [[ $(hostname) == "desktop-hostname" ]]; then
    ACTIVE_CONFIG="desktop"
else
    ACTIVE_CONFIG="laptop"
fi
```

**Benefits**:
- Single repository serves multiple machines
- Device-specific optimizations (battery indicators on laptop only)
- Privacy modes hide sensitive information (meetings, tasks)

### 4. Modular Plugin Architecture

**Pattern**: Plugin-Based Extensibility (Sketchybar & Hammerspoon)

**Sketchybar Plugin System**:
```
config/sketchybar/
├── sketchybarrc          # Plugin registration
├── plugins/
│   ├── meeting.sh        # Calendar integration
│   ├── todoist.sh        # Task management
│   ├── volume.sh         # Audio control
│   ├── network.sh        # Network monitoring
│   └── aerospace_*.sh    # Workspace indicators
└── plugins-laptop/
    └── battery.sh        # Laptop-only plugin
```

Each plugin:
- Implements standard interface (subscribes to events)
- Fetches data independently
- Updates its own display segment
- Handles errors gracefully

**Hammerspoon Spoons**:
```
config/hammerspoon/
├── init.lua              # Spoon loader
└── Spoons/
    ├── AudioDeviceCycler.spoon
    ├── WindowManagement.spoon
    └── Translation.spoon
```

## Component Architecture

### 1. AeroSpace (Window Manager)

**Architecture**: Tiling window manager with spatial workspace model

**Configuration**: TOML-based declarative config
- Workspace definitions and monitor assignments
- Keybindings for window/workspace manipulation
- Layout rules (tiling algorithm, gaps, padding)
- Callbacks for lifecycle events

**Integration Points**:
- **Sketchybar**: Updates workspace indicators via hooks
- **Hammerspoon**: Complementary automation (AeroSpace handles layout, Hammerspoon handles hotkeys/scripts)
- **macOS Accessibility API**: Window positioning and focus control

**Key Files**:
- `config/aerospace/aerospace.toml` - Main configuration
- `config/aerospace/workspace_change.sh` - Workspace change handler
- `config/aerospace/workspace_move.sh` - Window move handler

### 2. Sketchybar (Status Bar)

**Architecture**: Plugin-based status bar with shell script plugins

**Data Flow**:
```
Event Source → Plugin Script → Sketchybar API → Visual Update
     ↓              ↓                ↓               ↓
  (Timer)      (fetch data)    (set display)   (render bar)
  (Hook)       (process)        (configure)     (macOS)
  (System)
```

**Plugin Categories**:
- **System Monitors**: CPU, memory, network
- **Application Integrations**: Calendar (khal), Tasks (Todoist), Music (Spotify)
- **Window Manager**: AeroSpace workspace indicators
- **Device-Specific**: Battery (laptop only)

**Configuration Strategy**:
- Dispatcher config (`sketchybarrc`) detects environment
- Loads device-specific config (`sketchybarrc-desktop` or `sketchybarrc-laptop`)
- Privacy toggle switches to `*-privacy` variant (hides meetings/tasks)

**Key Files**:
- `config/sketchybar/sketchybarrc` - Main dispatcher
- `config/sketchybar/colors.sh` - Color scheme
- `config/sketchybar/plugins/*.sh` - Individual plugins
- `config/sketchybar/config_manager.sh` - Environment detection

### 3. Hammerspoon (Automation Engine)

**Architecture**: Lua-based macOS automation with extensive API access

**Capabilities**:
- **Window Management**: Position, resize, move windows
- **Hotkey Management**: Global keyboard shortcuts
- **Application Control**: Launch, quit, focus applications
- **Audio Control**: Device switching, volume management
- **Translation**: Text selection translation (English ↔ Portuguese)
- **System Control**: Brightness, dock visibility
- **Watchers**: File system, application, network events

**Modular Structure**:
```lua
-- init.lua (entry point)
hs.loadSpoon("AudioDeviceCycler")
hs.loadSpoon("WindowManagement")
hs.loadSpoon("Translation")

-- Each Spoon is self-contained module
-- Spoons/AudioDeviceCycler.spoon/init.lua
```

**Key Integrations**:
- **macOS Accessibility API**: Window manipulation
- **macOS Audio API**: Device enumeration and control
- **HTTP API**: External service integration (translation)
- **Shell Commands**: Execute system commands

**Key Files**:
- `config/hammerspoon/init.lua` - Main entry point
- `config/hammerspoon/Spoons/` - Modular extensions
- `config/hammerspoon/update.lua` - Auto-update logic

### 4. Karabiner-Elements (Keyboard Remapping)

**Architecture**: Kernel-level keyboard event interceptor

**Primary Function**: Map Caps Lock → Hyper Key (Cmd+Alt+Ctrl+Shift)

**Purpose**:
- Unlocks additional modifier combinations
- Enables custom global hotkeys without conflicts
- Used extensively by Hammerspoon and system shortcuts

**Configuration**: JSON-based complex modifications

**Key Files**:
- `config/karabiner/karabiner.json` - Main config with device-specific rules
- `config/karabiner/assets/` - Karabiner resources
- `config/karabiner/automatic_backups/` - Auto-generated backups

### 5. Claude AI Integration

**Architecture**: AI-assisted development workflow system

**Components**:
- **Claude Code**: VS Code-like AI coding assistant
- **BMAD Framework**: Business Model & Development methodology
- **Custom Workflows**: Project management and development processes

**Integration Points**:
- **Slash Commands**: Quick access to workflows (`.claude/commands/`)
- **Hooks**: Event notifications (`.claude/hooks/`)
- **BMAD Workflows**: Structured development processes (`bmad/*/workflows/`)

**Configuration**:
- `config/claude/settings.json` - Claude Code settings with tool hooks
- `config/claude/config.json` - Claude configuration
- `config/claude/workflows/` - Custom workflow definitions
- `config/claude/commands/` - Slash command implementations

**BMAD Framework Structure**:
```
bmad/
├── core/       # Core workflows (brainstorming, party-mode)
├── bmm/        # Business Model Method (PRD, architecture, dev)
├── bmb/        # BMad Builder (module creation)
└── cis/        # Creative & Innovation Studio
```

### 6. Calendar & Task Integration

**Components**:
- **khal**: Terminal calendar application
- **Sketchybar Meeting Plugin**: Visual meeting reminders
- **Calendar Sync**: iCal URL synchronization

**Architecture**:
```
iCal URLs (stored in .env)
    ↓
sync_calendars.sh (fetches events)
    ↓
khal (local calendar database)
    ↓
meeting.sh plugin (queries next meeting)
    ↓
Sketchybar (displays in status bar)
```

**Privacy Consideration**:
- Meeting details visible in default configs
- Privacy mode configs hide meeting information
- Toggle via `Ctrl+Alt+Cmd+P` hotkey

**Key Files**:
- `config/khal/config` - Calendar application config
- `config/sketchybar/plugins/meeting.sh` - Meeting display plugin
- `config/sketchybar/plugins/sync_calendars.sh` - Calendar sync script
- `.env` (project root) - Calendar URLs (gitignored)

## Data Flow Diagrams

### Workspace Change Event Flow

```
User switches workspace
         │
         ▼
┌─────────────────┐
│   AeroSpace     │
│  detects change │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────┐
│ exec-on-workspace-change hook   │
│ executes with $WORKSPACE_ID     │
└────────┬────────────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│ aerospace_update_all.sh          │
│ - Updates workspace indicators   │
│ - Highlights active workspace    │
│ - Updates window count           │
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────────┐
│   Sketchybar API     │
│   renders updates    │
└──────────────────────┘
```

### Audio Device Cycling Flow

```
User presses Ctrl+Alt+Cmd+]
         │
         ▼
┌─────────────────────┐
│   Karabiner maps    │
│   to Hammerspoon    │
└────────┬────────────┘
         │
         ▼
┌─────────────────────────────────┐
│  Hammerspoon hotkey handler     │
│  AudioDeviceCycler.spoon        │
└────────┬────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│  Query all audio devices        │
│  (macOS Audio API)              │
└────────┬────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│  Cycle to next device           │
│  Set volume level (0/33/66/100) │
└────────┬────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│  Display notification           │
│  "🔊 Device Name - 66%"         │
└─────────────────────────────────┘
```

## Deployment Architecture

### Installation Flow

```
┌──────────────────────────────────┐
│  Fresh macOS Machine             │
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│  git clone dotfiles repo         │
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│  ./scripts/bootstrap.sh          │
├──────────────────────────────────┤
│  1. Install/update Homebrew      │
│  2. brew bundle (install apps)   │
│  3. Install JetBrains Mono font  │
│  4. Install Node.js CLI tools    │
│  5. Call install.sh (symlinks)   │
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│  ./scripts/install.sh            │
├──────────────────────────────────┤
│  For each tool:                  │
│  1. Check if target exists       │
│  2. Backup if exists             │
│  3. Create symlink               │
│  4. Verify symlink               │
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│  Manual: Grant Permissions       │
│  - Accessibility                 │
│  - Screen Recording              │
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│  Start Services                  │
│  - open -a AeroSpace             │
│  - brew services start sketchybar│
│  - Launch Hammerspoon            │
└──────────────────────────────────┘
```

### Symlink Mapping

| Source (Repository) | Target (System) | Notes |
|---------------------|-----------------|-------|
| `config/aerospace/aerospace.toml` | `~/.config/aerospace/aerospace.toml` | File symlink |
| `config/sketchybar/` | `~/.config/sketchybar/` | Directory symlink |
| `config/hammerspoon/` | `~/.hammerspoon/` | Non-standard location |
| `config/karabiner/` | `~/.config/karabiner/` | Directory symlink |
| `config/claude/` | `~/.claude/` | Root-level directory |
| `config/raycast/` | `~/.config/raycast/` | Directory symlink |
| `config/khal/` | `~/.config/khal/` | Directory symlink |
| `config/obsidian/` | `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/.obsidian/` | iCloud location |

## Technology Stack

### Core Technologies

| Technology | Purpose | Version |
|------------|---------|---------|
| **Shell (Bash)** | Scripting, plugins, automation | bash 5.x |
| **Lua** | Hammerspoon automation scripting | Lua 5.4 |
| **TOML** | AeroSpace configuration | TOML 1.0 |
| **JSON** | Configs (Karabiner, Claude, Obsidian) | JSON |
| **YAML** | BMAD framework configs | YAML 1.2 |
| **Git** | Version control | git 2.x |
| **Homebrew** | Package management | brew 4.x |

### Application Stack

| Application | Category | Configuration Method |
|-------------|----------|---------------------|
| **AeroSpace** | Window Manager | TOML config file |
| **Sketchybar** | Status Bar | Shell script config + plugins |
| **Hammerspoon** | Automation | Lua scripts + Spoons |
| **Karabiner-Elements** | Keyboard Remapping | JSON complex modifications |
| **Raycast** | Launcher | JSON config + extensions |
| **Obsidian** | Note-Taking | JSON settings + plugin configs |
| **Claude** | AI Assistant | JSON settings + workflows |
| **khal** | Calendar | INI-style config |

### Development Tools

- **Node.js 20**: JavaScript runtime for Claude CLI and tools
- **GitHub CLI (gh)**: GitHub command-line interface
- **Visual Studio Code**: Code editor
- **Postman**: API development and testing
- **OrbStack**: Docker Desktop alternative

## Performance Considerations

### Startup Performance
- **AeroSpace**: ~100ms initialization
- **Sketchybar**: ~200ms with all plugins
- **Hammerspoon**: ~300ms loading all Spoons

### Runtime Performance
- **Event latency**: <50ms for window operations
- **Plugin refresh**: 1-5 seconds per plugin (configurable)
- **Memory footprint**: ~150MB total for all background processes

### Optimization Strategies
- Lazy loading of Hammerspoon Spoons
- Cached plugin data in Sketchybar
- Debounced event handlers (prevent rapid re-execution)
- Minimal dependencies in shell scripts

## Security & Privacy

### Sensitive Data Handling
- **Calendar URLs**: Stored in `.env` files (gitignored)
- **API tokens**: Environment variables, not in configs
- **Personal layouts**: Obsidian workspace files gitignored
- **Privacy mode**: Dedicated configs hide meetings and tasks

### Permission Model
- **Accessibility**: Required for window management (AeroSpace, Hammerspoon)
- **Screen Recording**: Optional (Hammerspoon screenshot features)
- **Automation**: Required for inter-app control (Hammerspoon)

### Access Control
- Repository is public (only generic configurations)
- Machine-specific secrets in `.env` files
- Personal data excluded via `.gitignore`

## Extension & Customization

### Adding a New Tool Configuration

1. **Create config directory**:
   ```bash
   mkdir -p ~/dotfiles/config/newtool
   ```

2. **Add configuration files**:
   ```bash
   cp ~/.config/newtool/* ~/dotfiles/config/newtool/
   ```

3. **Update install script**:
   ```bash
   # Edit scripts/install.sh
   ln -sf "$DOTFILES_DIR/config/newtool" "$HOME/.config/newtool"
   ```

4. **Add to Brewfile** (if applicable):
   ```ruby
   brew "newtool"  # or cask "newtool"
   ```

5. **Document in README**:
   - Add to tools list
   - Document key features
   - Add setup instructions

### Creating a Sketchybar Plugin

1. **Create plugin file**:
   ```bash
   touch ~/dotfiles/config/sketchybar/plugins/myplugin.sh
   chmod +x ~/dotfiles/config/sketchybar/plugins/myplugin.sh
   ```

2. **Implement plugin**:
   ```bash
   #!/bin/bash
   # Fetch data
   DATA=$(fetch_your_data)

   # Update Sketchybar
   sketchybar --set myplugin label="$DATA"
   ```

3. **Register in config**:
   ```bash
   # sketchybarrc
   sketchybar --add item myplugin right \
              --set myplugin update_freq=60 \
                             script="$PLUGIN_DIR/myplugin.sh"
   ```

### Creating a Hammerspoon Spoon

1. **Create Spoon structure**:
   ```bash
   mkdir -p ~/dotfiles/config/hammerspoon/Spoons/MySpoon.spoon
   touch ~/dotfiles/config/hammerspoon/Spoons/MySpoon.spoon/init.lua
   ```

2. **Implement Spoon**:
   ```lua
   local obj = {}
   obj.__index = obj
   obj.name = "MySpoon"

   function obj:init()
       -- Initialization
   end

   function obj:start()
       -- Start functionality
   end

   return obj
   ```

3. **Load in init.lua**:
   ```lua
   hs.loadSpoon("MySpoon")
   spoon.MySpoon:start()
   ```

## Maintenance & Operations

### Regular Maintenance Tasks

**Weekly**:
- Review Hammerspoon console for errors
- Check Sketchybar logs for plugin failures
- Test all hotkeys and shortcuts

**Monthly**:
- Update packages: `brew update && brew upgrade`
- Review and clean old backups
- Sync changes across machines

**Quarterly**:
- Review and optimize plugin refresh rates
- Audit gitignore for new sensitive files
- Update documentation

### Monitoring & Logging

**Sketchybar**:
```bash
# View logs
tail -f ~/Library/Logs/sketchybar/sketchybar.log

# Check plugin output
bash ~/.config/sketchybar/plugins/meeting.sh
```

**Hammerspoon**:
- Open Hammerspoon app → Console
- Lua errors appear in console
- `print()` statements for debugging

**AeroSpace**:
```bash
# Validate config syntax
aerospace check-config

# Check running status
pgrep -fl AeroSpace
```

## New Feature Implementation Architecture

This section documents architectural decisions for implementing Environment Configuration (Epic 1) and Calendar Automation (Epic 2) enhancements to the dotfiles system.

### Enhancement Overview

**Epic 1: Environment Configuration (7 stories)**
- Multi-environment support (IPM vs Personal)
- Dynamic color scheme selection (Brazil colors for IPM)
- Display mode detection (laptop vs external monitor)
- Notch-aware padding adjustments
- Automatic environment loading

**Epic 2: Calendar Automation (7 stories)**
- Automated calendar synchronization via LaunchAgent
- Stale event cleanup from khal database
- .env-based calendar URL configuration
- Comprehensive error handling and logging
- Zero-touch operation

### Decision Summary

The following architectural decisions ensure consistent implementation across all AI agents:

| Category | Decision | Version/Value | Affects Epics | Rationale |
|----------|----------|---------------|---------------|-----------|
| **Configuration** | .env file location | `.env` (project root) | Epic 1, Epic 2 | Central configuration, git-ignored for secrets |
| **Environment Detection** | ENV_TYPE variable | IPM \| PERSONAL | Epic 1 | Simple string comparison for env selection |
| **Color Schemes** | Color file pattern | `colors-{ENV_TYPE}.sh` | Epic 1 | Modular, extensible, clear fallback to colors.sh |
| **Brazil Colors** | Color values | Green: #009B3A, Yellow: #FEDD00, Blue: #002776 | Epic 1 | Official Brazil flag colors in ARGB hex format |
| **Display Detection** | Detection mechanism | `sketchybar --query displays` | Epic 1 | Uses existing Sketchybar API, no external deps |
| **Padding Strategy** | Variable naming | PADDING_LAPTOP, PADDING_EXTERNAL | Epic 1 | Clear distinction, extensible for more modes |
| **Calendar Sync** | Automation mechanism | macOS LaunchAgent | Epic 2 | Native macOS, persistent across reboots |
| **Sync Frequency** | Interval | 15 minutes (900 seconds) | Epic 2 | Balances freshness vs resource usage |
| **Sync Timeout** | Network timeout | 60 seconds | Epic 2 | Meets NFR001 requirement |
| **Script Organization** | Location pattern | helpers/ for utilities, plugins/ for widgets | Epic 1, Epic 2 | Follows existing Sketchybar conventions |
| **Logging** | Log directory | `config/sketchybar/logs/` | Epic 1, Epic 2 | Centralized, easy to monitor and rotate |
| **Log Rotation** | Rotation policy | Keep last 10 files or 1MB max per log | Epic 2 | Prevents disk bloat, retains debug history |
| **Error Handling** | Strategy | Graceful degradation, non-blocking | Epic 1, Epic 2 | Widget continues with fallback/stale data |
| **Event System** | Custom events | calendar_synced, environment_loaded | Epic 1, Epic 2 | Decoupled component communication |
| **Calendar URLs** | Configuration | CALENDAR_URL_* in .env | Epic 2 | Git-ignored private URLs, supports multiple calendars |
| **Stale Events** | Cleanup strategy | Remove events older than current datetime | Epic 2 | Keeps database lean, only relevant events |

### Epic to Architecture Mapping

**Epic 1: Environment Configuration**

| Story | Component | File/Location |
|-------|-----------|---------------|
| 1.1 - .env Configuration | Configuration file | `.env` (project root), `.env.example` |
| 1.2 - Color Files | Color schemes | `config/sketchybar/colors-ipm.sh`, `colors-personal.sh` |
| 1.3 - Display Detection | Helper script | `config/sketchybar/helpers/detect-display-mode.sh` |
| 1.4 - Environment Loader | Helper script | `config/sketchybar/helpers/load-env-config.sh` |
| 1.5 - Dynamic Padding | Sketchybar variants | `config/sketchybar/sketchybarrc-laptop`, `sketchybarrc-desktop` |
| 1.6 - Startup Integration | Install script | `scripts/install.sh` enhancement |
| 1.7 - Display Events | Plugin | `config/sketchybar/plugins/handle-display-change.sh` |

**Epic 2: Calendar Automation**

| Story | Component | File/Location |
|-------|-----------|---------------|
| 2.1 - Script Consolidation | Helper script | `config/sketchybar/helpers/sync-calendars.sh` |
| 2.2 - Stale Cleanup | Sync script logic | Part of `sync-calendars.sh` |
| 2.3 - .env Calendar URLs | Configuration | `.env` (project root, CALENDAR_URL_*) |
| 2.4 - LaunchAgent | macOS LaunchAgent | `~/Library/LaunchAgents/com.user.calendar-sync.plist` |
| 2.5 - Error Handling | Logging system | `config/sketchybar/logs/calendar-sync.log` |
| 2.6 - Widget Updates | Plugin enhancement | `config/sketchybar/plugins/meeting.sh` |
| 2.7 - Testing & Docs | Documentation | `CLAUDE.md` updates, test procedures |

### New File Structure

The following files will be added to support the new features:

```
config/sketchybar/
├── .env                                # New: Environment configuration (gitignored)
├── .env.example                        # New: Template with documentation
├── colors-ipm.sh                       # New: IPM (Brazil) color scheme
├── colors-personal.sh                  # New: Personal color scheme
├── helpers/
│   ├── load-env-config.sh              # New: Environment loader
│   ├── detect-display-mode.sh          # New: Display detection utility
│   └── sync-calendars.sh               # Relocated: From scattered locations
├── plugins/
│   ├── handle-display-change.sh        # New: Display change handler
│   └── meeting.sh                      # Modified: Enhanced with event subscription
└── logs/                               # New: Log directory
    ├── calendar-sync.log               # New: Calendar sync logs
    ├── environment-loader.log          # New: Environment logs
    └── display-detection.log           # New: Display detection logs

~/Library/LaunchAgents/
└── com.user.calendar-sync.plist        # New: Calendar sync LaunchAgent
```

### Implementation Patterns for Agent Consistency

These patterns ensure all AI agents implement stories with consistent conventions:

#### Naming Conventions

**Shell Scripts:**
- Format: `{verb}-{noun}.sh`
- Examples: `detect-display-mode.sh`, `sync-calendars.sh`, `load-env-config.sh`
- All scripts must be executable: `chmod +x`
- Location: `helpers/` for utilities, `plugins/` for Sketchybar widgets

**Environment Variables:**
- Format: `SCREAMING_SNAKE_CASE`
- Examples: `ENV_TYPE`, `PADDING_LAPTOP`, `PADDING_EXTERNAL`, `CALENDAR_URL_PRIMARY`
- Scope prefix pattern: `{DOMAIN}_{NAME}` (e.g., `CALENDAR_URL_WORK`)

**Color Variables:**
- Follow Sketchybar conventions: `BAR_COLOR`, `ACCENT_COLOR`, `BACKGROUND`, `FOREGROUND`
- Format: ARGB hexadecimal `0xAARRGGBB`
- Examples: `0xff009B3A` (Brazil green), `0xffFEDD00` (Brazil yellow)

**Log Files:**
- Format: `{component}-{purpose}.log`
- Examples: `calendar-sync.log`, `environment-loader.log`, `display-detection.log`
- Location: `config/sketchybar/logs/`

**Event Names:**
- Format: `{component}_{action}` in snake_case
- Examples: `calendar_synced`, `display_changed`, `environment_loaded`
- Used with: `sketchybar --subscribe {item} {event}`

#### Script Structure Template

All new scripts must follow this structure:

```bash
#!/bin/bash

# Script: {script-name}.sh
# Purpose: {brief description}
# Epic: {Epic N}
# Story: {Story N.N}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../../.env"  # Project root .env
LOG_DIR="${SCRIPT_DIR}/../logs"
LOG_FILE="${LOG_DIR}/{script-name}.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Log function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

# Load environment
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
    log "INFO" "Environment loaded from $ENV_FILE"
else
    log "WARN" ".env file not found, using defaults"
    # Set defaults here
fi

# Validate required variables
if [[ -z "$REQUIRED_VAR" ]]; then
    log "ERROR" "REQUIRED_VAR not set in .env"
    exit 1
fi

# Main logic
# ...

# Success
log "INFO" "Operation completed successfully"
exit 0
```

#### LaunchAgent Pattern

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.{service-name}</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>{full-path-to-script}</string>
    </array>

    <key>StartInterval</key>
    <integer>{interval-in-seconds}</integer>

    <key>StandardOutPath</key>
    <string>{log-path}/stdout.log</string>

    <key>StandardErrorPath</key>
    <string>{log-path}/stderr.log</string>

    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```

#### Environment Configuration (.env) Structure

```bash
# Environment Configuration
# This file is gitignored - do not commit to repository

# Environment Type: IPM | PERSONAL
ENV_TYPE=IPM

# Display Padding (in pixels)
PADDING_LAPTOP=40      # Padding for laptop mode (with notch on IPM)
PADDING_EXTERNAL=10    # Padding for external monitor mode

# Calendar Configuration
CALENDAR_URL_PRIMARY=https://calendar.example.com/ical/feed1.ics
CALENDAR_URL_SECONDARY=https://calendar.example.com/ical/feed2.ics
# Add more calendar URLs as CALENDAR_URL_* pattern

# Sync Configuration
CALENDAR_SYNC_TIMEOUT=60        # Network timeout in seconds (NFR001)
CALENDAR_HISTORY_DAYS=7         # Keep events from last N days

# Logging Configuration
LOG_RETENTION_COUNT=10          # Keep last N log files
LOG_MAX_SIZE_MB=1              # Max size per log file in MB
```

#### Data Flow Patterns

**Environment Loading Sequence:**
```
1. Sketchybar initialization
2. Call load-env-config.sh
3. Source .env file
4. Read ENV_TYPE variable
5. Call detect-display-mode.sh
6. Select appropriate PADDING value
7. Source colors-{ENV_TYPE}.sh (fallback to colors.sh)
8. Export variables for sketchybarrc
9. Load appropriate variant config
10. Render Sketchybar with environment settings
```

**Calendar Synchronization Flow:**
```
1. LaunchAgent triggers sync-calendars.sh (every 15 minutes)
2. Script sources .env for CALENDAR_URL_* variables
3. For each calendar URL:
   a. Fetch .ics file via curl (60s timeout)
   b. Import to khal database
   c. Log success or error
4. Query khal for current datetime
5. Remove events older than current datetime
6. Log stale event count
7. Trigger calendar_synced event via sketchybar
8. meeting.sh plugin receives event
9. Plugin queries khal for next meeting
10. Update widget display
```

**Display Change Event Flow:**
```
1. User connects/disconnects external monitor
2. macOS triggers display configuration change
3. Sketchybar detects display_change event
4. handle-display-change.sh plugin executes
5. Call detect-display-mode.sh
6. Determine laptop or external mode
7. Source .env for appropriate PADDING value
8. Update Sketchybar bar configuration
9. Trigger Sketchybar reload
10. Bar repositions with correct padding
```

#### Error Handling Patterns

**Non-Blocking Failures:**
- Calendar sync failure → Widget shows "Sync Failed (HH:MM)" + last successful data
- Display detection failure → Use last known configuration (log warning)
- .env missing → Use hardcoded defaults + log warning + continue operation
- Color scheme file missing → Fall back to `colors.sh` + log warning

**Validation Requirements:**
- Check file existence before sourcing: `[[ -f "$FILE" ]] && source "$FILE"`
- Validate required variables: `[[ -z "$VAR" ]] && { log ERROR; exit 1; }`
- Test command availability: `command -v {tool} >/dev/null || { log ERROR; exit 1; }`
- Verify write permissions: `[[ -w "$DIR" ]] || { log ERROR; exit 1; }`

**Logging Requirements:**
- Every script must write to its designated log file
- Timestamp format: `YYYY-MM-DD HH:MM:SS`
- Log levels: INFO (success), WARN (degraded), ERROR (failure)
- Include context: Operation name, input values, error details
- Log both entry and exit of critical operations

#### Consistency Rules

**File Permissions:**
- All `.sh` scripts: `chmod +x` (executable)
- All `.env` files: `chmod 600` (owner read/write only)
- All log directories: `chmod 755` (owner full, others read/execute)

**Color Scheme Integration:**
- All color files must export same variable names as `colors.sh`
- Use ARGB format: `0xAARRGGBB` (alpha + RGB)
- Document color purpose in comments (e.g., `# Primary accent color`)

**Event Subscription:**
- Plugins subscribe to events in their initialization
- Event handlers must be idempotent (safe to call multiple times)
- Events should trigger updates, not contain data (widgets query for data)

**Backward Compatibility:**
- New features must not break existing configurations
- Fallback to existing behavior if new config missing
- Existing environment variables must continue to work

### Testing Strategy

**Unit Testing (Per Story):**
- Test scripts in isolation with mock .env files
- Verify error handling with invalid inputs
- Check logging output format and content

**Integration Testing (Per Epic):**
- Epic 1: Test environment switching (IPM ↔ Personal)
- Epic 1: Test display mode changes (laptop ↔ external)
- Epic 2: Test calendar sync end-to-end with test .ics URLs
- Epic 2: Verify LaunchAgent triggers sync on schedule

**System Testing:**
- Full dotfiles installation on fresh macOS system
- Verify all components integrate correctly
- Test permission requirements (accessibility, etc.)

**Acceptance Testing:**
- User Journey 1: Add calendar event → verify appears in widget
- User Journey 2: Disconnect monitor → verify padding adjusts
- User Journey 3: New computer setup → verify environment applies

### Non-Functional Requirements

**Performance:**
- NFR001: Calendar sync completes within 60 seconds (enforced via curl timeout)
- NFR002: Display mode changes trigger adjustment in <100ms (event-driven)

**Reliability:**
- All scripts must handle network failures gracefully
- Widget must never crash Sketchybar (catch all errors)
- Log rotation prevents disk space issues

**Maintainability:**
- All code follows consistent naming conventions
- Comprehensive logging for debugging
- .env.example documents all configuration options

**Security:**
- Calendar URLs stored in gitignored .env file
- No secrets in repository code
- File permissions restrict .env access to owner only

## Future Architecture Considerations

### Potential Enhancements

1. **Cross-platform support**: Extend to Linux with tool alternatives
2. **Remote sync**: Sync state between machines (beyond git)
3. **Advanced automation**: More complex Hammerspoon workflows
4. **Plugin marketplace**: Share custom Sketchybar plugins
5. **Configuration profiles**: Quick-switch between work/personal setups
6. **Automated testing**: CI/CD for config validation
7. **Backup automation**: Automated backups of system state

### Scalability

Current architecture scales well for:
- ✅ Single user, multiple machines
- ✅ 5-15 integrated tools
- ✅ Dozens of Sketchybar plugins
- ✅ Moderate Hammerspoon automation complexity

May need rearchitecture for:
- ❌ Team-wide dotfiles (multi-user)
- ❌ 50+ integrated tools
- ❌ Real-time synchronization across machines
- ❌ Complex plugin dependency management

---

*Original brownfield documentation generated: 2025-10-27*
*Updated with new feature architecture decisions: 2025-10-28*
*Last Updated: 2026-01-13 (Exhaustive Rescan)*
*Generated by BMAD Decision Architecture Workflow*
