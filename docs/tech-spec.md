# dotfiles - Technical Specification

**Author:** Jeff
**Date:** 2025-10-28
**Project Level:** 2
**Project Type:** software
**Development Context:** brownfield

---

## Source Tree Structure

This section details the exact file structure changes required to implement Environment Configuration (Epic 1) and Calendar Automation (Epic 2).

### New Files

**Epic 1: Environment Configuration**

```
config/sketchybar/
├── .env                                    # Environment configuration (gitignored)
├── .env.example                            # Template with documentation
├── colors-ipm.sh                           # IPM environment (Brazil colors)
├── colors-personal.sh                      # Personal environment colors
├── helpers/
│   ├── detect-display-mode.sh              # Display mode detection utility
│   ├── load-env-config.sh                  # Environment configuration loader
│   └── sync-calendars.sh                   # Calendar sync (relocated from Epic 2)
├── plugins/
│   └── handle-display-change.sh            # Display change event handler
└── logs/                                   # Log directory for all scripts
    ├── calendar-sync.log                   # Calendar sync logs
    ├── environment-loader.log              # Environment loading logs
    └── display-detection.log               # Display detection logs
```

**Epic 2: Calendar Automation**

```
~/Library/LaunchAgents/
└── com.user.calendar-sync.plist            # Calendar sync LaunchAgent
```

### Modified Files

```
config/sketchybar/
├── sketchybarrc-laptop                     # Dynamic padding from env vars
├── sketchybarrc-desktop                    # Dynamic padding from env vars (if exists)
└── plugins/
    └── meeting.sh                          # Enhanced with calendar_synced event

scripts/
└── install.sh                              # Add env loader integration

.gitignore                                  # Add config/sketchybar/.env
```

### File Summary by Epic

**Epic 1 (Environment Configuration): 7 new files, 3 modified files**
- New: .env, .env.example, 2 color schemes, 3 helpers, 1 plugin, logs directory
- Modified: sketchybarrc variants (2), install.sh, .gitignore

**Epic 2 (Calendar Automation): 1 new file, 1 relocated file, 1 modified file**
- New: LaunchAgent plist, log files (in logs/ from Epic 1)
- Relocated: sync-calendars.sh → helpers/
- Modified: meeting.sh plugin

### Directory Structure (Complete View)

```
~/dotfiles/
├── config/
│   └── sketchybar/
│       ├── .env                            # [NEW] Environment config
│       ├── .env.example                    # [NEW] Config template
│       ├── colors.sh                       # [EXISTING] Default colors
│       ├── colors-ipm.sh                   # [NEW] Brazil color scheme
│       ├── colors-personal.sh              # [NEW] Personal color scheme
│       ├── sketchybarrc                    # [EXISTING] Main config
│       ├── sketchybarrc-laptop             # [MODIFIED] Dynamic padding
│       ├── sketchybarrc-desktop            # [MODIFIED] Dynamic padding
│       ├── helpers/
│       │   ├── detect-display-mode.sh      # [NEW] Display detection
│       │   ├── load-env-config.sh          # [NEW] Env loader
│       │   └── sync-calendars.sh           # [NEW/RELOCATED] Calendar sync
│       ├── plugins/
│       │   ├── meeting.sh                  # [MODIFIED] Event subscription
│       │   ├── handle-display-change.sh    # [NEW] Display change handler
│       │   └── [other existing plugins]    # [EXISTING] Unchanged
│       └── logs/                           # [NEW] Log directory
│           ├── calendar-sync.log
│           ├── environment-loader.log
│           └── display-detection.log
├── scripts/
│   └── install.sh                          # [MODIFIED] Env loader integration
└── .gitignore                              # [MODIFIED] Add .env exclusion

~/Library/LaunchAgents/
└── com.user.calendar-sync.plist            # [NEW] Calendar automation
```

### File Count Summary

- **Total new files:** 12
- **Total modified files:** 4
- **Total relocated files:** 1
- **New directories:** 2 (helpers/, logs/)
- **Total impacted files:** 17

---

## Technical Approach

### Overview

This technical specification implements two interdependent epics that enhance the dotfiles system with environment awareness and calendar automation. The approach leverages existing Sketchybar architecture patterns while introducing new configuration and automation layers.

**Core Principles:**
- **Centralized Configuration:** Single `.env` file as source of truth for environment-specific settings
- **Event-Driven Architecture:** Sketchybar custom events for component communication
- **Graceful Degradation:** All features fail safely without breaking the UI
- **Zero-Touch Automation:** Calendar sync runs automatically without user intervention
- **Brownfield Integration:** New features integrate with existing symlink-based deployment

### Epic 1: Environment Configuration Technical Approach

**Pattern: Configuration Selection with Runtime Detection**

The environment configuration system uses a three-layer approach:

1. **Configuration Layer (.env file)**
   - Single source of truth for environment settings
   - Git-ignored for privacy (calendar URLs, personal preferences)
   - Variables: `ENV_TYPE`, `PADDING_LAPTOP`, `PADDING_EXTERNAL`, calendar URLs
   - Validated and loaded at Sketchybar startup

2. **Detection Layer (Helper scripts)**
   - `detect-display-mode.sh`: Queries Sketchybar for display configuration
   - Uses `sketchybar --query displays` API (no external dependencies)
   - Returns "laptop" or "external" mode
   - Idempotent and stateless (can be called repeatedly)

3. **Application Layer (Color schemes + Sketchybar variants)**
   - Environment-specific color files: `colors-ipm.sh`, `colors-personal.sh`
   - Sketchybar variants read padding from environment variables
   - Display change events trigger dynamic reconfiguration
   - Falls back to defaults if environment config missing

**Data Flow:**
```
Startup → load-env-config.sh → source .env → detect display mode
         → export PADDING variable → source colors-{ENV_TYPE}.sh
         → sketchybar loads variant with applied settings
```

**Event Flow:**
```
Display change → handle-display-change.sh → re-run detection
              → export new PADDING → trigger sketchybar reload
              → bar repositions with new padding
```

**Key Decisions:**
- **Why .env?** Standard pattern, easy to edit, git-ignored by convention
- **Why shell scripts?** Consistent with existing Sketchybar plugin architecture
- **Why dynamic padding?** IPM laptop has notch requiring 40px padding; external monitors need 10px
- **Why ENV_TYPE variable?** Simple string comparison, extensible to more environments

### Epic 2: Calendar Automation Technical Approach

**Pattern: Scheduled Sync with Event Notification**

The calendar automation system implements a background sync process that updates the Sketchybar meeting widget:

1. **Sync Orchestration (LaunchAgent)**
   - macOS LaunchAgent runs `sync-calendars.sh` every 15 minutes
   - Configured with `StartInterval=900` seconds
   - Persists across system restarts via `RunAtLoad=true`
   - Logs to dedicated file for debugging

2. **Sync Logic (sync-calendars.sh)**
   - Sources `.env` for calendar URL variables (pattern: `CALENDAR_URL_*`)
   - Fetches each .ics file via curl with 60-second timeout (NFR001)
   - Imports events to khal database via `khal import`
   - Removes stale events (older than current datetime minus configurable history window)
   - Triggers Sketchybar `calendar_synced` custom event on success
   - Comprehensive error logging without blocking

3. **Display Integration (meeting.sh plugin)**
   - Subscribes to `calendar_synced` event for immediate updates
   - Queries khal for next upcoming meeting via `khal list`
   - Calculates countdown timer from current time to meeting start
   - Gracefully handles sync failures (shows last successful data + "Sync Failed" indicator)
   - Refreshes display every 60 seconds even without new events

**Data Flow:**
```
LaunchAgent timer → sync-calendars.sh → curl .ics files → khal import
                 → cleanup stale events → trigger calendar_synced event
                 → meeting.sh receives event → query khal → update widget
```

**Stale Event Cleanup Strategy:**
```sql
-- Conceptual logic (implemented in bash)
DELETE FROM khal.events
WHERE event_end < (CURRENT_DATETIME - HISTORY_WINDOW)
```

**Key Decisions:**
- **Why LaunchAgent?** Native macOS automation, more reliable than cron or Hammerspoon
- **Why 15-minute interval?** Balances freshness vs network/battery impact
- **Why custom events?** Decouples sync from display, allows other plugins to react
- **Why khal?** Already in use, local database, fast queries, iCal-compatible
- **Why 60-second timeout?** Meets NFR001, prevents hung sync on slow networks

### Integration Patterns

**Environment + Calendar Integration:**
- Both features use the same `.env` file for configuration
- Both write logs to centralized `logs/` directory
- Both follow the same error handling pattern (log + degrade gracefully)
- Calendar URLs and environment settings coexist in single config file

**Shared Components:**
- `.env` file: Shared by environment loader and calendar sync
- `logs/` directory: Centralized logging for both epics
- `helpers/` directory: Utility scripts for both features
- Sketchybar event system: Used for display changes and calendar updates

### Error Handling Philosophy

**Non-Blocking Failures:**
- Calendar sync failure → Widget shows stale data + "Sync Failed" message
- Display detection failure → Use last known padding configuration
- `.env` missing → Use hardcoded defaults + log warning
- Color scheme file missing → Fall back to `colors.sh`

**Validation Requirements:**
- Check file existence before sourcing: `[[ -f "$FILE" ]] && source "$FILE"`
- Validate required variables: `[[ -z "$VAR" ]] && log ERROR`
- Test command availability: `command -v khal >/dev/null`
- Verify write permissions: `[[ -w "$DIR" ]]`

**Logging Requirements:**
- Every script writes to its designated log file in `logs/`
- Timestamp format: `YYYY-MM-DD HH:MM:SS`
- Log levels: INFO (success), WARN (degraded), ERROR (failure)
- Include context: Operation name, input values, error details

### Backward Compatibility

**Existing Functionality Preservation:**
- Current Sketchybar configurations continue working without `.env`
- Existing color scheme (`colors.sh`) remains as fallback
- Calendar widget displays even without automated sync
- All new features are additive, nothing breaks existing setup

**Migration Strategy:**
- Installation script creates `.env.example` as template
- User copies to `.env` and fills in their settings
- System works with defaults if user doesn't create `.env`
- Gradual adoption: Environment features and calendar automation are independent

---

## Implementation Stack

### Core Technologies

| Technology | Version | Purpose | Usage |
|------------|---------|---------|-------|
| **Bash** | 5.x | Scripting language | All helper scripts, plugins, sync logic |
| **Sketchybar** | Latest | Status bar framework | UI rendering, event system, plugin host |
| **khal** | 0.11.x | Calendar CLI tool | Local calendar database, event queries |
| **curl** | 7.x+ | HTTP client | Fetch .ics calendar files |
| **macOS LaunchAgent** | Native | Task scheduler | Periodic calendar sync automation |

### Runtime Environment

| Component | Requirement | Notes |
|-----------|-------------|-------|
| **Operating System** | macOS 12+ (Monterey or later) | Native LaunchAgent, Sketchybar compatibility |
| **Shell** | bash 5.x or zsh | Scripts use bash shebang for consistency |
| **Sketchybar** | Installed via Homebrew | Must be running for plugins to work |
| **khal** | Installed via Homebrew/pip | Calendar database backend |
| **Permissions** | Accessibility | Required for Sketchybar automation |

### Configuration Files

| File Type | Format | Purpose | Location |
|-----------|--------|---------|----------|
| **.env** | Shell variables | Environment configuration | `config/sketchybar/.env` |
| **Color schemes** | Shell scripts (exports) | Visual theme definitions | `config/sketchybar/colors-*.sh` |
| **Helper scripts** | Bash scripts | Utility functions | `config/sketchybar/helpers/*.sh` |
| **Plugins** | Bash scripts | Sketchybar widgets | `config/sketchybar/plugins/*.sh` |
| **LaunchAgent** | XML plist | Scheduled task config | `~/Library/LaunchAgents/*.plist` |
| **Sketchybar configs** | Shell scripts | Bar configuration | `config/sketchybar/sketchybarrc*` |

### External Dependencies

**Required:**
- Homebrew (package manager)
- Sketchybar (status bar)
- khal (calendar tool)
- curl (HTTP client, usually pre-installed)

**Optional:**
- None (all features use core dependencies)

### Version Control & Deployment

| Aspect | Technology | Details |
|--------|------------|---------|
| **Version Control** | Git | Central repository at `~/dotfiles` |
| **Deployment Method** | Symlinks | `install.sh` creates symlinks to home directory |
| **Secret Management** | `.env` + `.gitignore` | Sensitive data excluded from repository |
| **Backup Strategy** | Git + timestamped backups | `install.sh` creates backups before symlinking |

### Brazil Color Palette (IPM Environment)

Colors based on official Brazil flag specifications:

| Color | Hex Value | ARGB Format | Usage |
|-------|-----------|-------------|-------|
| **Green** | #009B3A | 0xff009B3A | Primary accent, bar background |
| **Yellow** | #FEDD00 | 0xffFEDD00 | Highlights, active indicators |
| **Blue** | #002776 | 0xff002776 | Secondary accent, text |

### Logging Infrastructure

| Log File | Purpose | Rotation | Location |
|----------|---------|----------|----------|
| **calendar-sync.log** | Calendar sync operations | Last 10 files or 1MB max | `config/sketchybar/logs/` |
| **environment-loader.log** | Environment configuration | Last 10 files or 1MB max | `config/sketchybar/logs/` |
| **display-detection.log** | Display mode detection | Last 10 files or 1MB max | `config/sketchybar/logs/` |

---

## Technical Details

### Epic 1: Environment Configuration - Implementation Details

#### Story 1.1: .env Configuration Structure

**File: `config/sketchybar/.env`**

```bash
# Environment Configuration
# This file is gitignored - do not commit to repository

# Environment Type: IPM | PERSONAL
ENV_TYPE=IPM

# Display Padding (in pixels)
PADDING_LAPTOP=40      # Padding for laptop mode (with notch on IPM)
PADDING_EXTERNAL=10    # Padding for external monitor mode

# Calendar Configuration
CALENDAR_URL_PRIMARY=https://calendar.google.com/calendar/ical/.../basic.ics
CALENDAR_URL_SECONDARY=https://outlook.office365.com/owa/calendar/.../calendar.ics

# Sync Configuration
CALENDAR_SYNC_TIMEOUT=60        # Network timeout in seconds (NFR001)
CALENDAR_HISTORY_DAYS=7         # Keep events from last N days

# Logging Configuration
LOG_RETENTION_COUNT=10          # Keep last N log files
LOG_MAX_SIZE_MB=1              # Max size per log file in MB
```

**File: `config/sketchybar/.env.example`**
- Copy of above with documentation comments
- Example values for both IPM and PERSONAL environments
- Instructions for setup

**.gitignore Entry:**
```
config/sketchybar/.env
```

#### Story 1.2: Environment-Specific Color Files

**File: `config/sketchybar/colors-ipm.sh`**

```bash
#!/bin/bash

# Brazil-inspired color scheme for IPM environment
# Based on official Brazil flag colors

# Primary Colors
export BAR_COLOR=0xff009B3A          # Brazil green
export ACCENT_COLOR=0xffFEDD00       # Brazil yellow
export BACKGROUND=0xff002776         # Brazil blue
export FOREGROUND=0xffffffff         # White text

# Status Colors
export SUCCESS_COLOR=0xff009B3A      # Green
export WARNING_COLOR=0xffFEDD00      # Yellow
export ERROR_COLOR=0xffff0000        # Red
export INFO_COLOR=0xff002776         # Blue

# Workspace Colors
export WORKSPACE_ACTIVE=0xffFEDD00   # Yellow
export WORKSPACE_INACTIVE=0x80009B3A # Dimmed green
```

**File: `config/sketchybar/colors-personal.sh`**
- Copy of existing `colors.sh` with current color scheme
- Maintains existing visual appearance for personal environment

#### Story 1.3: Display Mode Detection Helper

**File: `config/sketchybar/helpers/detect-display-mode.sh`**

```bash
#!/bin/bash

# Script: detect-display-mode.sh
# Purpose: Detect current display mode (laptop vs external)
# Epic: Epic 1
# Story: Story 1.3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs"
LOG_FILE="${LOG_DIR}/display-detection.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Log function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_FILE"
}

# Detect display configuration
detect_display_mode() {
    # Query Sketchybar for display information
    local display_info=$(sketchybar --query displays 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        log "ERROR" "Failed to query Sketchybar displays"
        echo "laptop"  # Default to laptop mode on error
        return 1
    fi

    # Count number of displays
    local display_count=$(echo "$display_info" | grep -c "display")

    log "INFO" "Detected $display_count display(s)"

    if [[ $display_count -gt 1 ]]; then
        echo "external"
        log "INFO" "Display mode: external"
    else
        echo "laptop"
        log "INFO" "Display mode: laptop"
    fi
}

# Main execution
detect_display_mode
```

#### Story 1.4: Environment Configuration Loader

**File: `config/sketchybar/helpers/load-env-config.sh`**

```bash
#!/bin/bash

# Script: load-env-config.sh
# Purpose: Load environment configuration and prepare Sketchybar
# Epic: Epic 1
# Story: Story 1.4

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
COLORS_DIR="${SCRIPT_DIR}/.."
LOG_DIR="${SCRIPT_DIR}/../logs"
LOG_FILE="${LOG_DIR}/environment-loader.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Log function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

# Load .env file
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
    log "INFO" "Environment loaded from $ENV_FILE"
    log "INFO" "ENV_TYPE=$ENV_TYPE"
else
    log "WARN" ".env file not found, using defaults"
    ENV_TYPE="PERSONAL"
    PADDING_LAPTOP=10
    PADDING_EXTERNAL=10
fi

# Detect display mode
DISPLAY_MODE=$(bash "${SCRIPT_DIR}/detect-display-mode.sh")
log "INFO" "Display mode: $DISPLAY_MODE"

# Select appropriate padding
if [[ "$DISPLAY_MODE" == "laptop" ]]; then
    export PADDING=$PADDING_LAPTOP
    log "INFO" "Using laptop padding: $PADDING"
else
    export PADDING=$PADDING_EXTERNAL
    log "INFO" "Using external padding: $PADDING"
fi

# Load environment-specific color scheme
COLOR_FILE="${COLORS_DIR}/colors-${ENV_TYPE,,}.sh"
if [[ -f "$COLOR_FILE" ]]; then
    source "$COLOR_FILE"
    log "INFO" "Loaded color scheme: $COLOR_FILE"
else
    log "WARN" "Color file not found: $COLOR_FILE, falling back to colors.sh"
    source "${COLORS_DIR}/colors.sh"
fi

# Export variables for Sketchybar
export ENV_TYPE
export DISPLAY_MODE
export PADDING

log "INFO" "Environment configuration complete"
```

#### Story 1.5: Dynamic Padding in Sketchybar Variants

**Modification: `config/sketchybar/sketchybarrc-laptop`**

```bash
# Before environment loader integration:
sketchybar --bar height=40 \
                 position=top \
                 padding_left=10 \
                 padding_right=10

# After environment loader integration:
# Source environment configuration first
source "${CONFIG_DIR}/helpers/load-env-config.sh"

# Use dynamic padding from environment
sketchybar --bar height=40 \
                 position=top \
                 padding_left=${PADDING:-10} \
                 padding_right=${PADDING:-10}
```

#### Story 1.7: Display Change Event Handler

**File: `config/sketchybar/plugins/handle-display-change.sh`**

```bash
#!/bin/bash

# Script: handle-display-change.sh
# Purpose: Handle display configuration changes
# Epic: Epic 1
# Story: Story 1.7

CONFIG_DIR="$HOME/.config/sketchybar"

# Reload environment configuration
source "${CONFIG_DIR}/helpers/load-env-config.sh"

# Trigger Sketchybar reload with new configuration
sketchybar --reload

exit 0
```

### Epic 2: Calendar Automation - Implementation Details

#### Story 2.1 & 2.3: Calendar Sync Script

**File: `config/sketchybar/helpers/sync-calendars.sh`**

```bash
#!/bin/bash

# Script: sync-calendars.sh
# Purpose: Synchronize calendar data from iCal URLs to khal
# Epic: Epic 2
# Story: Story 2.1, 2.2, 2.3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
LOG_DIR="${SCRIPT_DIR}/../logs"
LOG_FILE="${LOG_DIR}/calendar-sync.log"
TEMP_DIR="/tmp/calendar-sync-$$"

# Ensure directories exist
mkdir -p "$LOG_DIR"
mkdir -p "$TEMP_DIR"

# Cleanup on exit
trap "rm -rf $TEMP_DIR" EXIT

# Log function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

# Load environment
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
    log "INFO" "Environment loaded"
else
    log "ERROR" ".env file not found"
    exit 1
fi

# Validate required tools
for cmd in curl khal sketchybar; do
    if ! command -v $cmd >/dev/null 2>&1; then
        log "ERROR" "Required command not found: $cmd"
        exit 1
    fi
done

# Sync calendars
SYNC_SUCCESS=0
CALENDAR_COUNT=0

# Find all CALENDAR_URL_* variables
for var in $(env | grep '^CALENDAR_URL_' | cut -d= -f1); do
    CALENDAR_COUNT=$((CALENDAR_COUNT + 1))
    URL="${!var}"

    log "INFO" "Syncing calendar: $var"

    # Fetch calendar with timeout
    TEMP_ICS="${TEMP_DIR}/calendar_${CALENDAR_COUNT}.ics"
    if curl -L -s -m "${CALENDAR_SYNC_TIMEOUT:-60}" "$URL" -o "$TEMP_ICS"; then
        # Import to khal
        if khal import "$TEMP_ICS" 2>>"$LOG_FILE"; then
            log "INFO" "Successfully imported $var"
            SYNC_SUCCESS=1
        else
            log "ERROR" "Failed to import $var to khal"
        fi
    else
        log "ERROR" "Failed to fetch $var from $URL"
    fi
done

# Cleanup stale events (Story 2.2)
HISTORY_DAYS=${CALENDAR_HISTORY_DAYS:-7}
CUTOFF_DATE=$(date -v-${HISTORY_DAYS}d '+%Y-%m-%d' 2>/dev/null || date -d "${HISTORY_DAYS} days ago" '+%Y-%m-%d')

log "INFO" "Cleaning up events older than $CUTOFF_DATE"

# Note: khal doesn't have direct delete, so we use database cleanup
# This is a simplified approach - actual implementation may vary
STALE_COUNT=$(khal list --format "{start-date}" --day-format "" | \
              awk -v cutoff="$CUTOFF_DATE" '$1 < cutoff' | wc -l)

log "INFO" "Found $STALE_COUNT stale events"

# Trigger calendar_synced event
if [[ $SYNC_SUCCESS -eq 1 ]]; then
    sketchybar --trigger calendar_synced
    log "INFO" "Calendar sync complete, triggered calendar_synced event"
else
    log "WARN" "Calendar sync completed with errors"
fi

exit 0
```

#### Story 2.4: LaunchAgent Configuration

**File: `~/Library/LaunchAgents/com.user.calendar-sync.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.calendar-sync</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/YOUR_USERNAME/.config/sketchybar/helpers/sync-calendars.sh</string>
    </array>

    <key>StartInterval</key>
    <integer>900</integer>

    <key>StandardOutPath</key>
    <string>/Users/YOUR_USERNAME/.config/sketchybar/logs/calendar-sync-stdout.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/YOUR_USERNAME/.config/sketchybar/logs/calendar-sync-stderr.log</string>

    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```

#### Story 2.6: Meeting Widget Enhancement

**Modification: `config/sketchybar/plugins/meeting.sh`**

```bash
#!/bin/bash

# Subscribe to calendar_synced event
sketchybar --subscribe meeting calendar_synced

# Query khal for next meeting
NEXT_MEETING=$(khal list now 7d --format "{title}|{start-time}|{start-date}" | head -n 1)

if [[ -n "$NEXT_MEETING" ]]; then
    TITLE=$(echo "$NEXT_MEETING" | cut -d'|' -f1)
    TIME=$(echo "$NEXT_MEETING" | cut -d'|' -f2)
    DATE=$(echo "$NEXT_MEETING" | cut -d'|' -f3)

    # Calculate countdown
    MEETING_TIMESTAMP=$(date -j -f "%Y-%m-%d %H:%M" "$DATE $TIME" "+%s" 2>/dev/null)
    CURRENT_TIMESTAMP=$(date "+%s")
    DIFF=$((MEETING_TIMESTAMP - CURRENT_TIMESTAMP))

    if [[ $DIFF -gt 0 ]]; then
        HOURS=$((DIFF / 3600))
        MINUTES=$(((DIFF % 3600) / 60))

        if [[ $HOURS -gt 0 ]]; then
            COUNTDOWN="${HOURS}h ${MINUTES}m"
        else
            COUNTDOWN="${MINUTES}m"
        fi

        LABEL="📅 $TITLE in $COUNTDOWN"
    else
        LABEL="📅 $TITLE (now)"
    fi
else
    LABEL="📅 No meetings"
fi

sketchybar --set meeting label="$LABEL"
```

### File Permissions

All scripts must be executable:

```bash
chmod +x config/sketchybar/helpers/*.sh
chmod +x config/sketchybar/plugins/*.sh
chmod 600 config/sketchybar/.env  # Owner read/write only
```

### Naming Conventions Summary

- **Scripts:** `{verb}-{noun}.sh` (e.g., `detect-display-mode.sh`)
- **Environment Variables:** `SCREAMING_SNAKE_CASE`
- **Color Variables:** ARGB hexadecimal `0xAARRGGBB`
- **Log Files:** `{component}-{purpose}.log`
- **Events:** `{component}_{action}` in snake_case

---

## Development Setup

### Prerequisites

1. **macOS System Requirements**
   - macOS 12 (Monterey) or later
   - Administrator access for system permissions
   - Terminal access

2. **Required Tools** (already installed in brownfield environment)
   - Homebrew package manager
   - Sketchybar status bar
   - khal calendar tool
   - curl (pre-installed on macOS)
   - Git (for version control)

3. **System Permissions**
   - Accessibility: Required for Sketchybar
   - Automation: May be needed for script execution

### Development Environment Setup

**Step 1: Verify Existing Installation**

```bash
# Check if dotfiles repository exists
cd ~/dotfiles

# Verify Sketchybar is running
ps aux | grep sketchybar

# Verify khal is installed
which khal

# Check current Sketchybar configuration
ls -la ~/.config/sketchybar
```

**Step 2: Create Development Branch**

```bash
cd ~/dotfiles
git checkout -b feature/environment-calendar-automation
```

**Step 3: Set Up Development Directories**

```bash
# Create new directories for implementation
mkdir -p config/sketchybar/helpers
mkdir -p config/sketchybar/logs

# Verify directory structure
tree config/sketchybar -L 2
```

**Step 4: Configure Development Environment**

```bash
# Create .env file for development
cp config/sketchybar/.env.example config/sketchybar/.env

# Edit .env with your settings
# Set ENV_TYPE=PERSONAL for initial development
# Add test calendar URLs

# Set file permissions
chmod 600 config/sketchybar/.env
```

**Step 5: Install VS Code Extensions (Optional)**

Recommended extensions for shell script development:
- ShellCheck: Shell script linting
- Bash IDE: IntelliSense for bash
- Shell Script Command Completion

### Development Workflow

**Local Testing Strategy:**

1. **Script Development**
   - Write scripts in `config/sketchybar/helpers/` or `plugins/`
   - Make executable: `chmod +x script-name.sh`
   - Test independently before integration

2. **Manual Testing**
   ```bash
   # Test environment loader
   bash config/sketchybar/helpers/load-env-config.sh

   # Check logs
   tail -f config/sketchybar/logs/environment-loader.log

   # Test calendar sync
   bash config/sketchybar/helpers/sync-calendars.sh
   tail -f config/sketchybar/logs/calendar-sync.log
   ```

3. **Sketchybar Reload**
   ```bash
   # Restart Sketchybar to test changes
   brew services restart sketchybar

   # Or reload configuration
   sketchybar --reload
   ```

4. **LaunchAgent Testing**
   ```bash
   # Load LaunchAgent
   launchctl load ~/Library/LaunchAgents/com.user.calendar-sync.plist

   # Check status
   launchctl list | grep calendar-sync

   # View logs
   tail -f config/sketchybar/logs/calendar-sync-stdout.log

   # Unload for modifications
   launchctl unload ~/Library/LaunchAgents/com.user.calendar-sync.plist
   ```

### Debugging Tools

**Log Monitoring:**
```bash
# Watch all logs simultaneously
tail -f config/sketchybar/logs/*.log

# Filter for errors
grep ERROR config/sketchybar/logs/*.log

# Check last 100 lines
tail -n 100 config/sketchybar/logs/calendar-sync.log
```

**Sketchybar Debugging:**
```bash
# Query Sketchybar for display info
sketchybar --query displays

# List all items
sketchybar --query bar

# Check specific item
sketchybar --query meeting
```

**Calendar Debugging:**
```bash
# List khal calendars
khal printcalendars

# Query upcoming events
khal list now 7d

# Check khal configuration
cat ~/.config/khal/config
```

**Environment Variable Debugging:**
```bash
# Check loaded environment
env | grep -E "(ENV_TYPE|PADDING|CALENDAR)"

# Test color loading
source config/sketchybar/colors-ipm.sh
echo $BAR_COLOR
```

### Testing Isolation

**Safe Testing Without Affecting Production:**

1. **Backup Current Configuration**
   ```bash
   cp ~/.config/sketchybar/sketchybarrc ~/.config/sketchybar/sketchybarrc.backup
   ```

2. **Test with Alternative Config**
   ```bash
   # Create test variant
   cp config/sketchybar/sketchybarrc config/sketchybar/sketchybarrc-test

   # Modify and test separately
   ```

3. **Restore if Needed**
   ```bash
   cp ~/.config/sketchybar/sketchybarrc.backup ~/.config/sketchybar/sketchybarrc
   brew services restart sketchybar
   ```

### Common Development Issues

**Issue: Scripts not executable**
```bash
# Solution
chmod +x config/sketchybar/helpers/*.sh
chmod +x config/sketchybar/plugins/*.sh
```

**Issue: .env not loaded**
```bash
# Check file exists
ls -la config/sketchybar/.env

# Check permissions
ls -l config/sketchybar/.env

# Test sourcing manually
source config/sketchybar/.env
echo $ENV_TYPE
```

**Issue: Sketchybar doesn't update**
```bash
# Force restart
brew services restart sketchybar

# Check if running
ps aux | grep sketchybar

# Check logs
tail -f ~/Library/Logs/sketchybar/sketchybar.log
```

**Issue: Calendar sync fails**
```bash
# Verify khal is installed
which khal

# Test calendar URL manually
curl -L "YOUR_CALENDAR_URL" -o /tmp/test.ics

# Check khal import
khal import /tmp/test.ics
```

### Code Quality Tools

**ShellCheck Integration:**
```bash
# Install ShellCheck
brew install shellcheck

# Check all helper scripts
shellcheck config/sketchybar/helpers/*.sh

# Check all plugins
shellcheck config/sketchybar/plugins/*.sh
```

**Style Conventions:**
- Use bash shebang: `#!/bin/bash`
- 4-space indentation
- Quote variables: `"$VAR"`
- Use `[[` for conditionals, not `[`
- Add comments for complex logic

---

## Implementation Guide

### Implementation Sequence

This guide follows the story sequence from `docs/epics.md`. Each epic should be implemented sequentially, with stories completed in order within each epic.

### Epic 1: Environment Configuration

**Recommended Implementation Order:**

**Story 1.1: Create .env Configuration Structure**
1. Create `.env.example` file with full documentation
2. Add `.env` to `.gitignore`
3. Create initial `.env` file from example
4. Test variable sourcing manually

**Story 1.2: Create Environment-Specific Color Files**
1. Create `colors-ipm.sh` with Brazil color values
2. Copy existing `colors.sh` to `colors-personal.sh`
3. Make all color files executable
4. Test sourcing each color file and verify variables

**Story 1.3: Implement Display Mode Detection Helper**
1. Create `helpers/detect-display-mode.sh`
2. Implement Sketchybar display query logic
3. Test on laptop with/without external monitor
4. Verify logging to `display-detection.log`

**Story 1.4: Create Environment Configuration Loader**
1. Create `helpers/load-env-config.sh`
2. Implement .env loading with fallback defaults
3. Integrate display mode detection
4. Implement color scheme selection logic
5. Test with both IPM and PERSONAL environments

**Story 1.5: Modify Sketchybar Variants for Dynamic Padding**
1. Backup existing `sketchybarrc-laptop` and `sketchybarrc-desktop`
2. Add environment loader sourcing at top of files
3. Replace hardcoded padding with `${PADDING:-10}` syntax
4. Test Sketchybar restart with new configuration

**Story 1.6: Integrate Environment Loader at Startup**
1. Update `scripts/install.sh` to create `.env` from example
2. Ensure environment loader runs before Sketchybar starts
3. Test full installation flow on clean system (if possible)
4. Verify visual changes (Brazil colors in IPM mode)

**Story 1.7: Implement Display Change Event Subscription**
1. Create `plugins/handle-display-change.sh`
2. Add display_change event subscription to Sketchybar configs
3. Test monitor connect/disconnect scenarios
4. Verify smooth transitions without flicker

### Epic 2: Calendar Automation

**Recommended Implementation Order:**

**Story 2.1: Consolidate Calendar Scripts**
1. Move existing `sync_calendars.sh` to `helpers/`
2. Update all path references in Sketchybar configs
3. Ensure meeting.sh plugin uses correct path
4. Test existing calendar functionality still works

**Story 2.2: Enhance Sync Script with Stale Event Cleanup**
1. Add stale event detection logic to sync script
2. Implement cleanup based on CALENDAR_HISTORY_DAYS
3. Add logging for cleanup operations
4. Test with known stale events

**Story 2.3: Read Calendar URLs from .env**
1. Add CALENDAR_URL_* variables to `.env` structure
2. Update sync script to read from .env
3. Support multiple calendar URLs (loop through CALENDAR_URL_* pattern)
4. Test sync with URLs from .env

**Story 2.4: Implement LaunchAgent**
1. Create LaunchAgent plist file
2. Replace YOUR_USERNAME with actual username
3. Load LaunchAgent with launchctl
4. Verify LaunchAgent runs on schedule
5. Check logs for successful execution

**Story 2.5: Add Comprehensive Error Handling**
1. Add try/catch equivalent error handling to sync script
2. Implement log rotation logic
3. Test network failure scenarios
4. Verify widget displays fallback messages

**Story 2.6: Update Meeting Widget**
1. Add calendar_synced event subscription to meeting.sh
2. Implement countdown timer logic
3. Test widget updates after sync
4. Verify graceful handling of no meetings

**Story 2.7: End-to-End Testing**
1. Run full test suite (see Testing Approach section)
2. Update documentation (CLAUDE.md)
3. Create troubleshooting guide
4. Document manual sync command

### Implementation Tips

**Per-Story Workflow:**

1. **Read the story** in `docs/epics.md` completely
2. **Review acceptance criteria** to understand definition of done
3. **Implement the code** following Technical Details section
4. **Test manually** using Development Setup commands
5. **Verify acceptance criteria** are met
6. **Commit with clear message** referencing story number
7. **Move to next story**

**Code Review Checklist (Self-Review):**

- [ ] Script has proper shebang (`#!/bin/bash`)
- [ ] Script is executable (`chmod +x`)
- [ ] Variables are quoted (`"$VAR"` not `$VAR`)
- [ ] Error handling implemented (check return codes)
- [ ] Logging added for key operations
- [ ] File paths use absolute or script-relative paths
- [ ] No hardcoded usernames or personal data
- [ ] Comments explain non-obvious logic
- [ ] Follows naming conventions from architecture
- [ ] ShellCheck passes with no warnings

**Git Commit Strategy:**

```bash
# Per-story commits
git add config/sketchybar/.env.example
git commit -m "Epic 1 Story 1.1: Create .env configuration structure

- Add .env.example with full documentation
- Add .env to .gitignore
- Include example values for IPM and PERSONAL environments"

# Or per-file commits for large stories
git add config/sketchybar/helpers/load-env-config.sh
git commit -m "Epic 1 Story 1.4: Implement environment configuration loader"
```

### Integration Points

**Sketchybar Integration:**

When modifying Sketchybar configs, always test reload:
```bash
sketchybar --reload
# Or full restart
brew services restart sketchybar
```

**LaunchAgent Integration:**

After modifying LaunchAgent plist:
```bash
# Unload old version
launchctl unload ~/Library/LaunchAgents/com.user.calendar-sync.plist

# Load new version
launchctl load ~/Library/LaunchAgents/com.user.calendar-sync.plist

# Verify loaded
launchctl list | grep calendar-sync
```

**khal Integration:**

After modifying calendar sync logic:
```bash
# Manually trigger sync
bash ~/.config/sketchybar/helpers/sync-calendars.sh

# Verify events imported
khal list now 7d

# Check khal database
khal printcalendars
```

### Troubleshooting Implementation Issues

**Scripts don't execute:**
- Check shebang is correct: `#!/bin/bash`
- Verify executable permission: `ls -l script.sh`
- Check for Windows line endings: `file script.sh`

**Environment variables not loading:**
- Verify .env exists: `ls -la config/sketchybar/.env`
- Test sourcing: `source config/sketchybar/.env && echo $ENV_TYPE`
- Check for syntax errors in .env

**Colors not applying:**
- Verify color file exists and is executable
- Check ARGB format: `0xAARRGGBB`
- Test sourcing color file directly
- Restart Sketchybar completely

**Calendar sync not working:**
- Check calendar URLs are accessible: `curl -L "URL"`
- Verify khal is installed: `which khal`
- Check LaunchAgent is loaded: `launchctl list`
- Review sync logs for errors

### Performance Considerations

**Optimization Guidelines:**

- Keep helper scripts lightweight (no external dependencies if possible)
- Cache display mode detection results when appropriate
- Use Sketchybar events instead of polling
- Minimize log file sizes with rotation
- Use timeout for network operations (curl -m 60)

**Resource Usage:**

- LaunchAgent sync runs every 15 minutes: minimal CPU impact
- Log files capped at 1MB each: minimal disk impact
- Environment detection: <100ms per call
- Calendar sync: <60 seconds per interval (NFR001)

---

## Testing Approach

### Testing Strategy

Testing is organized into four levels: Unit Testing (per-script), Integration Testing (per-epic), System Testing (full installation), and Acceptance Testing (user journeys from PRD).

### Unit Testing (Per Story)

**Epic 1: Environment Configuration**

**Test Story 1.1: .env Configuration**
```bash
# Test .env file creation
test -f config/sketchybar/.env && echo "✓ .env exists" || echo "✗ .env missing"

# Test .gitignore entry
grep -q "config/sketchybar/.env" .gitignore && echo "✓ gitignored" || echo "✗ not gitignored"

# Test variable loading
source config/sketchybar/.env
[[ -n "$ENV_TYPE" ]] && echo "✓ ENV_TYPE loaded: $ENV_TYPE" || echo "✗ ENV_TYPE not set"
[[ -n "$PADDING_LAPTOP" ]] && echo "✓ PADDING_LAPTOP: $PADDING_LAPTOP" || echo "✗ PADDING_LAPTOP not set"
```

**Test Story 1.2: Color Files**
```bash
# Test IPM colors exist
test -f config/sketchybar/colors-ipm.sh && echo "✓ colors-ipm.sh exists" || echo "✗ missing"

# Test color values
source config/sketchybar/colors-ipm.sh
[[ "$BAR_COLOR" == "0xff009B3A" ]] && echo "✓ Brazil green loaded" || echo "✗ wrong color"
[[ "$ACCENT_COLOR" == "0xffFEDD00" ]] && echo "✓ Brazil yellow loaded" || echo "✗ wrong color"
```

**Test Story 1.3: Display Detection**
```bash
# Test script exists and is executable
test -x config/sketchybar/helpers/detect-display-mode.sh && echo "✓ executable" || echo "✗ not executable"

# Test display detection output
MODE=$(bash config/sketchybar/helpers/detect-display-mode.sh)
[[ "$MODE" =~ ^(laptop|external)$ ]] && echo "✓ Valid mode: $MODE" || echo "✗ Invalid mode: $MODE"

# Test logging
tail -n 1 config/sketchybar/logs/display-detection.log | grep -q "Display mode" && echo "✓ Logging works"
```

**Test Story 1.4: Environment Loader**
```bash
# Test environment loader execution
bash config/sketchybar/helpers/load-env-config.sh && echo "✓ Loader executed" || echo "✗ Loader failed"

# Test log output
grep -q "Environment configuration complete" config/sketchybar/logs/environment-loader.log && echo "✓ Complete"

# Test environment variables exported
source config/sketchybar/helpers/load-env-config.sh
[[ -n "$PADDING" ]] && echo "✓ PADDING exported: $PADDING" || echo "✗ PADDING not exported"
```

**Epic 2: Calendar Automation**

**Test Story 2.1: Calendar Script Relocation**
```bash
# Test script moved to helpers
test -x config/sketchybar/helpers/sync-calendars.sh && echo "✓ Script relocated" || echo "✗ missing"

# Test old location removed
! test -f config/sketchybar/plugins/sync_calendars.sh && echo "✓ Old location removed" || echo "✗ still exists"
```

**Test Story 2.3: Calendar URL Configuration**
```bash
# Test calendar URLs in .env
source config/sketchybar/.env
env | grep -q "CALENDAR_URL_" && echo "✓ Calendar URLs configured" || echo "✗ No calendar URLs"

# Count calendar URLs
URL_COUNT=$(env | grep "^CALENDAR_URL_" | wc -l)
echo "Calendar URLs configured: $URL_COUNT"
```

**Test Story 2.4: LaunchAgent**
```bash
# Test LaunchAgent file exists
test -f ~/Library/LaunchAgents/com.user.calendar-sync.plist && echo "✓ LaunchAgent exists" || echo "✗ missing"

# Test LaunchAgent is loaded
launchctl list | grep -q "calendar-sync" && echo "✓ LaunchAgent loaded" || echo "✗ not loaded"

# Test LaunchAgent configuration
plutil -lint ~/Library/LaunchAgents/com.user.calendar-sync.plist && echo "✓ Valid plist" || echo "✗ Invalid plist"
```

### Integration Testing (Per Epic)

**Epic 1 Integration Tests:**

**Test: Environment Switching (IPM ↔ Personal)**
```bash
# Test IPM environment
echo "ENV_TYPE=IPM" > config/sketchybar/.env.test
source config/sketchybar/.env.test
bash config/sketchybar/helpers/load-env-config.sh
source config/sketchybar/colors-ipm.sh
[[ "$BAR_COLOR" == "0xff009B3A" ]] && echo "✓ IPM colors applied" || echo "✗ Failed"

# Test Personal environment
echo "ENV_TYPE=PERSONAL" > config/sketchybar/.env.test
bash config/sketchybar/helpers/load-env-config.sh
# Verify personal colors loaded

# Cleanup
rm config/sketchybar/.env.test
```

**Test: Display Mode Changes**
```bash
# Simulate laptop mode (requires actual display disconnection)
echo "Manual test: Disconnect external monitor"
MODE=$(bash config/sketchybar/helpers/detect-display-mode.sh)
[[ "$MODE" == "laptop" ]] && echo "✓ Laptop mode detected" || echo "✗ Wrong mode: $MODE"

# Reconnect monitor and test
echo "Manual test: Reconnect external monitor"
MODE=$(bash config/sketchybar/helpers/detect-display-mode.sh)
[[ "$MODE" == "external" ]] && echo "✓ External mode detected" || echo "✗ Wrong mode: $MODE"
```

**Epic 2 Integration Tests:**

**Test: End-to-End Calendar Sync**
```bash
# Trigger manual sync
bash config/sketchybar/helpers/sync-calendars.sh

# Check sync success in logs
grep -q "Calendar sync complete" config/sketchybar/logs/calendar-sync.log && echo "✓ Sync completed" || echo "✗ Sync failed"

# Verify events imported to khal
EVENT_COUNT=$(khal list now 7d | wc -l)
[[ $EVENT_COUNT -gt 0 ]] && echo "✓ Events imported: $EVENT_COUNT" || echo "✗ No events"

# Check widget update
sketchybar --query meeting | grep -q "label" && echo "✓ Widget updated" || echo "✗ Widget not updated"
```

**Test: LaunchAgent Scheduled Execution**
```bash
# Verify LaunchAgent triggers sync
launchctl start com.user.calendar-sync

# Wait and check logs
sleep 5
tail -n 10 config/sketchybar/logs/calendar-sync.log | grep -q "Calendar sync complete" && echo "✓ Scheduled sync works"
```

### System Testing

**Full Installation Test:**
```bash
# Simulate clean installation (use caution - backs up existing config)
cd ~/dotfiles

# Run installation script
./scripts/install.sh

# Verify symlinks created
test -L ~/.config/sketchybar && echo "✓ Sketchybar symlinked" || echo "✗ Symlink failed"

# Verify environment loader runs
grep -q "Environment configuration complete" config/sketchybar/logs/environment-loader.log && echo "✓ Env loaded"

# Verify Sketchybar starts
ps aux | grep -q "[s]ketchybar" && echo "✓ Sketchybar running" || echo "✗ Not running"

# Verify calendar sync LaunchAgent loaded
launchctl list | grep -q "calendar-sync" && echo "✓ LaunchAgent loaded" || echo "✗ Not loaded"
```

**Permission Verification:**
```bash
# Check script permissions
find config/sketchybar/helpers -name "*.sh" -perm -u+x | wc -l
find config/sketchybar/plugins -name "*.sh" -perm -u+x | wc -l

# Check .env permissions
ls -l config/sketchybar/.env | grep -q "rw-------" && echo "✓ Secure permissions" || echo "⚠ Check permissions"
```

### Acceptance Testing (User Journeys)

**Journey 1: Automatic Calendar Update**
```bash
# Prerequisites: Add a test event to calendar
echo "1. Add a new test meeting to your calendar (Google Calendar, Outlook, etc.)"
echo "2. Wait up to 15 minutes for next sync cycle"
echo "3. Check Sketchybar widget displays new meeting"

# Verification
khal list now 1d | grep -i "test" && echo "✓ Test event found in khal"
sketchybar --query meeting | grep -q "test" && echo "✓ Widget shows test event"
```

**Journey 2: Display Mode Adjustment**
```bash
echo "Test procedure:"
echo "1. On IPM laptop, disconnect external monitor"
echo "2. Observe Sketchybar padding adjustment (should accommodate notch)"
echo "3. Reconnect external monitor"
echo "4. Observe padding adjustment (should reduce padding)"

# Automated checks
echo "Current display mode:"
bash config/sketchybar/helpers/detect-display-mode.sh

echo "Current padding (from logs):"
grep "Using.*padding" config/sketchybar/logs/environment-loader.log | tail -n 1
```

**Journey 3: New Computer Setup**
```bash
# Simulated new computer setup flow
echo "Setup flow simulation:"
echo "1. Clone dotfiles repository"
echo "2. Create .env file from example: cp config/sketchybar/.env.example config/sketchybar/.env"
echo "3. Edit .env with environment settings and calendar URLs"
echo "4. Run: ./scripts/install.sh"
echo "5. Grant accessibility permissions"
echo "6. Start services: brew services start sketchybar"

# Verification
source config/sketchybar/.env
[[ -n "$ENV_TYPE" ]] && echo "✓ ENV_TYPE configured"
[[ -n "$CALENDAR_URL_PRIMARY" ]] && echo "✓ Calendar URL configured"
ps aux | grep -q "[s]ketchybar" && echo "✓ Sketchybar running"
launchctl list | grep -q "calendar-sync" && echo "✓ Calendar sync active"
```

### Non-Functional Requirements Testing

**NFR001: Calendar Sync Timeout**
```bash
# Test sync completes within 60 seconds
echo "Testing sync timeout..."
START=$(date +%s)
bash config/sketchybar/helpers/sync-calendars.sh
END=$(date +%s)
DURATION=$((END - START))

[[ $DURATION -le 60 ]] && echo "✓ Sync completed in ${DURATION}s (within 60s limit)" || echo "✗ Sync too slow: ${DURATION}s"
```

**NFR002: Display Mode Change Response**
```bash
# Manual test - measure time from display change to padding update
echo "Manual test procedure:"
echo "1. Note current time"
echo "2. Connect/disconnect external monitor"
echo "3. Observe Sketchybar padding change"
echo "4. Calculate elapsed time - should be < 100ms"
echo "5. Check logs for timing:"
tail -n 20 config/sketchybar/logs/environment-loader.log
```

### Regression Testing

**Verify Existing Functionality:**
```bash
# Test: Existing Sketchybar plugins still work
sketchybar --query bar | grep -q "bar" && echo "✓ Sketchybar responsive"

# Test: Existing AeroSpace integration works
# (Manual: Switch workspaces, verify Sketchybar updates)

# Test: Existing calendar widget displays
sketchybar --query meeting && echo "✓ Meeting widget exists"

# Test: Other plugins unaffected
# (Manual: Verify volume, network, battery plugins still function)
```

### Test Reporting

**Generate Test Report:**
```bash
# Create test results file
cat > test-results.md << 'EOF'
# Test Results - Environment Configuration & Calendar Automation

## Test Date: $(date '+%Y-%m-%d %H:%M:%S')

### Unit Tests
- [ ] Story 1.1: .env Configuration
- [ ] Story 1.2: Color Files
- [ ] Story 1.3: Display Detection
- [ ] Story 1.4: Environment Loader
- [ ] Story 2.1: Calendar Script Relocation
- [ ] Story 2.3: Calendar URL Configuration
- [ ] Story 2.4: LaunchAgent

### Integration Tests
- [ ] Environment Switching
- [ ] Display Mode Changes
- [ ] End-to-End Calendar Sync
- [ ] LaunchAgent Scheduled Execution

### System Tests
- [ ] Full Installation
- [ ] Permission Verification

### Acceptance Tests
- [ ] Journey 1: Automatic Calendar Update
- [ ] Journey 2: Display Mode Adjustment
- [ ] Journey 3: New Computer Setup

### NFR Tests
- [ ] NFR001: Calendar Sync Timeout (< 60s)
- [ ] NFR002: Display Mode Change (< 100ms)

### Regression Tests
- [ ] Existing Sketchybar functionality
- [ ] Existing AeroSpace integration

## Notes:
[Add any test failures, issues, or observations here]
EOF

echo "Test report template created: test-results.md"
```

---

## Deployment Strategy

### Deployment Overview

The dotfiles system uses a **symlink-based deployment** strategy where the central Git repository (`~/dotfiles`) contains all configurations, and symlinks point from system locations to repository files. This tech-spec adds new files and modifies existing ones within this deployment model.

### Pre-Deployment Checklist

**Before deploying to production:**

1. **Backup Current Configuration**
   ```bash
   # Create timestamped backup
   BACKUP_DIR="$HOME/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
   mkdir -p "$BACKUP_DIR"
   cp -r ~/.config/sketchybar "$BACKUP_DIR/"
   cp ~/Library/LaunchAgents/com.user.* "$BACKUP_DIR/" 2>/dev/null || true
   echo "Backup created at: $BACKUP_DIR"
   ```

2. **Verify Branch and Commits**
   ```bash
   cd ~/dotfiles
   git status
   git log --oneline -10
   # Ensure all work is committed
   ```

3. **Run Pre-Deployment Tests**
   ```bash
   # Verify scripts are executable
   find config/sketchybar/helpers -name "*.sh" ! -perm -u+x -ls
   find config/sketchybar/plugins -name "*.sh" ! -perm -u+x -ls

   # Check .env configuration
   test -f config/sketchybar/.env && echo "✓ .env configured" || echo "⚠ .env missing"

   # Validate LaunchAgent plist
   plutil -lint ~/Library/LaunchAgents/com.user.calendar-sync.plist
   ```

4. **Communication (if shared system)**
   - Notify other users if dotfiles are shared
   - Schedule deployment during low-usage period
   - Document rollback procedure

### Deployment Steps

**Phase 1: Update Repository Files**

```bash
cd ~/dotfiles

# Merge feature branch to main (or deploy from feature branch)
git checkout main
git merge feature/environment-calendar-automation

# Verify repository state
git status
git log --oneline -5
```

**Phase 2: Install New Files**

```bash
# Create new directories
mkdir -p config/sketchybar/helpers
mkdir -p config/sketchybar/logs

# Set up .env configuration
if [ ! -f config/sketchybar/.env ]; then
    cp config/sketchybar/.env.example config/sketchybar/.env
    echo "⚠ Edit config/sketchybar/.env with your settings"
    echo "  - Set ENV_TYPE (IPM or PERSONAL)"
    echo "  - Add calendar URLs"
    echo "  - Configure padding values"
    # Pause for user to edit
    read -p "Press Enter after editing .env file..."
fi

# Set file permissions
chmod +x config/sketchybar/helpers/*.sh
chmod +x config/sketchybar/plugins/*.sh
chmod 600 config/sketchybar/.env

# Update .gitignore
if ! grep -q "config/sketchybar/.env" .gitignore; then
    echo "config/sketchybar/.env" >> .gitignore
    git add .gitignore
    git commit -m "Add .env to gitignore"
fi
```

**Phase 3: Deploy LaunchAgent**

```bash
# Install LaunchAgent (update username first!)
USERNAME=$(whoami)
sed "s/YOUR_USERNAME/$USERNAME/g" \
    config/sketchybar/helpers/com.user.calendar-sync.plist.template \
    > ~/Library/LaunchAgents/com.user.calendar-sync.plist

# Load LaunchAgent
launchctl load ~/Library/LaunchAgents/com.user.calendar-sync.plist

# Verify loaded
launchctl list | grep calendar-sync && echo "✓ LaunchAgent loaded"
```

**Phase 4: Update Existing Configurations**

```bash
# Sketchybar configs are already symlinked, so repository changes apply immediately
# Restart Sketchybar to apply changes
brew services restart sketchybar

# Verify Sketchybar started successfully
sleep 2
ps aux | grep -q "[s]ketchybar" && echo "✓ Sketchybar running" || echo "✗ Sketchybar failed to start"
```

**Phase 5: Verification**

```bash
# Test environment loader
bash config/sketchybar/helpers/load-env-config.sh
grep -q "Environment configuration complete" config/sketchybar/logs/environment-loader.log && echo "✓ Env loader works"

# Test calendar sync
bash config/sketchybar/helpers/sync-calendars.sh
grep -q "Calendar sync complete" config/sketchybar/logs/calendar-sync.log && echo "✓ Calendar sync works"

# Check Sketchybar widget
sketchybar --query meeting && echo "✓ Meeting widget active"

# Verify LaunchAgent scheduled
launchctl list | grep calendar-sync && echo "✓ LaunchAgent scheduled"
```

### Rollback Procedure

**If deployment fails or issues arise:**

**Quick Rollback:**
```bash
# Stop LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.user.calendar-sync.plist

# Revert to previous commit
cd ~/dotfiles
git log --oneline -10  # Find previous good commit
git checkout <previous-commit-hash>

# Restart Sketchybar
brew services restart sketchybar

# Verify system works
ps aux | grep sketchybar
```

**Full Rollback from Backup:**
```bash
# Restore from backup
BACKUP_DIR="$HOME/dotfiles-backup-YYYYMMDD-HHMMSS"  # Use your backup timestamp
rm -rf ~/.config/sketchybar
cp -r "$BACKUP_DIR/sketchybar" ~/.config/

# Remove LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.user.calendar-sync.plist
rm ~/Library/LaunchAgents/com.user.calendar-sync.plist

# Restart services
brew services restart sketchybar
```

### Post-Deployment Validation

**Verify All Features:**

```bash
# Environment Configuration
source config/sketchybar/.env
[[ -n "$ENV_TYPE" ]] && echo "✓ ENV_TYPE: $ENV_TYPE"
bash config/sketchybar/helpers/detect-display-mode.sh && echo "✓ Display detection works"

# Calendar Automation
khal list now 7d && echo "✓ khal has events"
tail -f config/sketchybar/logs/calendar-sync.log  # Monitor for next sync

# Visual Verification
echo "Check Sketchybar widget displays correctly"
echo "Verify colors match environment (Brazil colors for IPM)"
echo "Check padding adjusts when connecting/disconnecting monitor"
```

### Monitoring Post-Deployment

**First 24 Hours:**

```bash
# Monitor logs
tail -f config/sketchybar/logs/*.log

# Check LaunchAgent execution
launchctl list | grep calendar-sync

# Verify calendar sync runs every 15 minutes
watch -n 60 'tail -n 5 config/sketchybar/logs/calendar-sync.log'

# Check for errors
grep ERROR config/sketchybar/logs/*.log
```

**Week 1:**
- Monitor log file sizes (should stay under 1MB with rotation)
- Verify calendar widget updates reliably
- Test display mode changes manually
- Confirm no performance degradation

### Deployment to Additional Machines

**When deploying to IPM laptop or other machines:**

```bash
# Clone repository (if new machine)
git clone https://github.com/jahm2u/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Run standard installation
./scripts/install.sh

# Configure environment for this machine
cp config/sketchybar/.env.example config/sketchybar/.env

# Edit .env for this machine's environment
# For IPM laptop:
echo "ENV_TYPE=IPM" >> config/sketchybar/.env
echo "PADDING_LAPTOP=40" >> config/sketchybar/.env
echo "PADDING_EXTERNAL=10" >> config/sketchybar/.env
# Add calendar URLs...

chmod 600 config/sketchybar/.env

# Deploy LaunchAgent
USERNAME=$(whoami)
# ... follow Phase 3 steps above

# Restart services
brew services restart sketchybar

# Verify Brazil colors appear on IPM machine
```

### Continuous Deployment Considerations

**For future updates:**

1. **Feature Branch Workflow**
   - Create feature branch for changes
   - Test thoroughly on feature branch
   - Merge to main after validation
   - Deploy from main branch

2. **Incremental Updates**
   - Make small, testable changes
   - Deploy during low-activity periods
   - Monitor logs after each deployment
   - Keep previous commit accessible for quick rollback

3. **Configuration Changes**
   - `.env` changes don't require code deployment
   - Color scheme changes require Sketchybar restart
   - LaunchAgent changes require unload/reload
   - Helper script changes apply immediately (symlinked)

### Deployment Checklist

**Complete Deployment Checklist:**

- [ ] Backup current configuration
- [ ] Verify all commits are pushed to repository
- [ ] Run pre-deployment tests
- [ ] Create/configure .env file
- [ ] Set file permissions (scripts executable, .env secure)
- [ ] Update .gitignore
- [ ] Deploy LaunchAgent
- [ ] Restart Sketchybar
- [ ] Verify environment loader works
- [ ] Verify calendar sync works
- [ ] Test display mode detection
- [ ] Check Sketchybar widget displays correctly
- [ ] Monitor logs for first hour
- [ ] Document any issues or unexpected behavior
- [ ] Keep backup accessible for 7 days

### Support and Troubleshooting Post-Deployment

**Common Post-Deployment Issues:**

**Issue: Calendar sync not running**
```bash
# Check LaunchAgent status
launchctl list | grep calendar-sync

# Manually trigger sync
bash ~/.config/sketchybar/helpers/sync-calendars.sh

# Check logs
tail -n 50 ~/.config/sketchybar/logs/calendar-sync.log
```

**Issue: Colors not changing**
```bash
# Verify ENV_TYPE in .env
source ~/.config/sketchybar/.env && echo $ENV_TYPE

# Check color file exists
ls -la ~/.config/sketchybar/colors-$ENV_TYPE.sh

# Force Sketchybar restart
killall sketchybar && open -a Sketchybar
```

**Issue: Display mode not detecting**
```bash
# Test detection manually
bash ~/.config/sketchybar/helpers/detect-display-mode.sh

# Check Sketchybar query works
sketchybar --query displays
```

### Maintenance Schedule

**Weekly:**
- Review log files for errors
- Verify calendar sync completing successfully
- Check log rotation is working

**Monthly:**
- Review and clean old backup directories
- Update dependencies if needed (brew upgrade)
- Verify .env configuration still accurate

**Quarterly:**
- Full system test on all machines
- Review and optimize LaunchAgent frequency
- Update documentation based on learnings
