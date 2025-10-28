# dotfiles Product Requirements Document (PRD)

**Author:** Jeff
**Date:** 2025-10-27
**Project Level:** 2
**Target Scale:** Focused MVP - Environment Detection & Calendar Automation

---

## Goals and Background Context

### Goals

- **Automated Calendar Synchronization**: Calendar data automatically refreshes and stays current with event updates, eliminating manual sync operations
- **Environment-Aware Configuration**: System automatically detects computer identity and display mode, applying appropriate visual styling and layout adjustments
- **Centralized Script Management**: All automation scripts consolidated within dotfiles repository for maintainability and version control

### Background Context

The current dotfiles configuration suffers from two critical pain points impacting daily productivity. First, the khal-based calendar integration requires manual execution of sync scripts, resulting in stale event data that's frequently out of sync with actual calendar state. An earlier attempt to automate this via Hammerspoon hourly triggers proved unsuccessful and was abandoned. Second, the same dotfiles configuration runs on multiple machines (IPM work laptop and personal Mac) with different requirements—the IPM laptop features a notch requiring context-aware top padding adjustments when switching between laptop and external monitor modes, and should display a distinct Brazil-inspired color scheme. Currently, scripts are scattered outside the repository structure, creating maintenance challenges and preventing proper version control of automation logic.

---

## Requirements

### Functional Requirements

**Calendar Synchronization**

- **FR001**: System shall automatically synchronize khal calendar database at regular intervals without manual intervention
- **FR002**: System shall remove stale/outdated events from the khal database during synchronization
- **FR003**: System shall read calendar URLs from `.env` configuration file within the dotfiles repository
- **FR004**: Sketchybar widget shall display the next upcoming meeting with countdown timer based on current khal data
- **FR005**: Calendar sync failures shall be logged and shall not prevent Sketchybar from displaying
- **FR006**: All calendar synchronization scripts shall be located within the dotfiles repository structure

**Environment-Based Configuration**

- **FR007**: System shall read all environment-specific settings from a `.env` configuration file in the dotfiles repository
- **FR008**: `.env` file shall define environment type (e.g., IPM or PERSONAL)
- **FR009**: `.env` file shall define color scheme settings for the current environment
- **FR010**: `.env` file shall define top padding settings for laptop vs external monitor modes
- **FR011**: System shall detect current display mode (laptop screen vs external monitor) and apply corresponding padding from `.env`
- **FR012**: IPM environment shall use Brazil-inspired color scheme (green, yellow, blue tones) as defined in `.env`
- **FR013**: System shall support easy environment switching by modifying `.env` file values

### Non-Functional Requirements

- **NFR001**: Calendar synchronization shall complete within 60 seconds under normal network conditions
- **NFR002**: Display mode changes shall trigger automatic padding adjustments without requiring manual intervention

---

## User Journeys

**Journey 1: Automatic Calendar Update**

1. User adds a new meeting to their calendar (via Google Calendar, Outlook, etc.)
2. System automatically syncs khal database within sync interval (no manual action required)
3. Sketchybar widget updates to display the new meeting with countdown timer
4. User glances at menu bar and sees accurate upcoming meeting information

**Journey 2: Display Mode Adjustment**

1. User disconnects external monitor from IPM laptop and switches to laptop-only mode
2. System detects display configuration change
3. System reads IPM laptop padding settings from `.env` file
4. Sketchybar adjusts top padding to accommodate notch
5. User sees properly positioned status bar without overlap

**Journey 3: New Computer Setup**

1. User clones dotfiles repository to a new computer
2. User creates/modifies `.env` file with environment-specific settings (ENV_TYPE, colors, padding, calendar URLs)
3. User runs installation script
4. System reads `.env` configuration and applies environment-specific settings
5. Sketchybar displays with correct colors and padding for the environment
6. Calendar widget begins syncing automatically

---

## UX Design Principles

- **Zero-Touch Automation**: System operates transparently without requiring user intervention or manual triggers
- **Visual Feedback**: Status bar provides clear, at-a-glance information about upcoming meetings
- **Environment Awareness**: Visual presentation adapts automatically to hardware context (display mode, computer identity)
- **Fail-Safe Operation**: Calendar sync failures degrade gracefully without breaking the UI

---

## User Interface Design Goals

**Platform & Screens**
- Target: macOS menu bar (Sketchybar)
- Primary view: Calendar widget showing next meeting with countdown
- Display modes: Laptop screen and external monitor configurations

**Visual Design**
- IPM Environment: Brazil-inspired color palette (green #009B3A, yellow #FEDD00, blue #002776)
- Personal Environment: Current color scheme (maintained)
- Dynamic padding adjustments for notch vs standard displays

**Design Constraints**
- Must work within Sketchybar framework and plugin architecture
- Color and padding values defined in `.env` for easy modification
- No external dependencies beyond existing khal/Sketchybar setup

---

## Epic List

**Epic 1: Environment Configuration**
- **Goal**: Enable environment-aware dotfiles that automatically detect and apply computer-specific settings for colors, padding, and other visual configurations
- **Estimated Stories**: 6-8 stories
- **Value**: Establishes foundation for multi-environment support, enabling single dotfiles repo to serve multiple computers with different visual requirements

**Epic 2: Calendar Automation**
- **Goal**: Implement reliable, automatic calendar synchronization that keeps Sketchybar widget current without manual intervention
- **Estimated Stories**: 5-7 stories
- **Value**: Eliminates manual sync operations and ensures calendar widget always displays accurate, up-to-date meeting information

**Total Estimated Stories**: 11-15 stories

> **Note:** Detailed epic breakdown with full story specifications is available in [epics.md](./epics.md)

---

## Out of Scope

**Features explicitly excluded from this project:**

- **Cloud-based calendar services**: Integration remains local via khal; no direct API integration with Google Calendar, Outlook, or other cloud providers
- **Calendar event creation/editing**: System remains read-only for calendar data; event management happens through native calendar applications
- **Multi-user configuration**: Environment detection supports single-user dotfiles deployment; shared/team configuration management not included
- **Automated environment detection**: User must manually configure `.env` file; no automatic detection of which computer/environment is running
- **Historical calendar data archival**: System syncs current/upcoming events only; no long-term calendar data storage or analytics
- **Mobile or tablet support**: Sketchybar is macOS-only; no iOS, iPadOS, or other platform support
- **Theme/color scheme builder UI**: Color schemes defined directly in `.env` file; no graphical configuration interface
- **Notification/alert system**: Calendar widget displays information only; no popup notifications or alerts for upcoming meetings

**Future considerations** (deferred to later phases):

- Additional environment profiles beyond IPM and Personal
- Automated backup/restore of calendar sync state
- Integration with other productivity tools (Raycast, Obsidian, etc.)
