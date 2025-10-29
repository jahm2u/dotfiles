# dotfiles - Epic Breakdown

**Author:** Jeff
**Date:** 2025-10-27
**Project Level:** 2
**Target Scale:** Focused MVP - Environment Detection & Calendar Automation

---

## Overview

This document provides the detailed epic breakdown for dotfiles, expanding on the high-level epic list in the [PRD](./PRD.md).

Each epic includes:

- Expanded goal and value proposition
- Complete story breakdown with user stories
- Acceptance criteria for each story
- Story sequencing and dependencies

**Epic Sequencing Principles:**

- Epic 1 establishes foundational infrastructure and initial functionality
- Subsequent epics build progressively, each delivering significant end-to-end value
- Stories within epics are vertically sliced and sequentially ordered
- No forward dependencies - each story builds only on previous work

---

## Epic 1: Environment Configuration

### Expanded Goal

This epic establishes environment-aware dotfiles by implementing a `.env`-based configuration system. The system will automatically detect display modes (laptop vs external monitor) and apply appropriate visual settings. It leverages Sketchybar's config loader pattern where the main `sketchybarrc` sources environment-specific variant files and color schemes. This enables a single dotfiles repository to serve multiple computers with different visual requirements (IPM work laptop with Brazil colors and notch-aware padding vs personal Mac with current styling).

### Story Breakdown

**Story 1.1: Create .env Configuration Structure**

As a dotfiles user,
I want a `.env` file that defines my environment type and settings,
So that I can configure environment-specific behavior in one central location.

**Acceptance Criteria:**
1. `.env` file created in `config/sketchybar/` directory
2. File defines `ENV_TYPE` variable (values: IPM or PERSONAL)
3. File defines padding variables: `PADDING_LAPTOP` and `PADDING_EXTERNAL`
4. File defines calendar URL variables for khal sync
5. File is git-ignored (`.env` in `.gitignore`)
6. `.env.example` file created with full documentation for all variables
7. `.env.example` includes example values for both IPM and PERSONAL environments

**Prerequisites:** None

---

**Story 1.2: Create Environment-Specific Color Files**

As a dotfiles user,
I want separate color scheme files for each environment,
So that IPM displays Brazil colors and Personal maintains current styling.

**Acceptance Criteria:**
1. Create `config/sketchybar/colors-ipm.sh` with Brazil color palette
   - Green: `0xff009B3A`, Yellow: `0xffFEDD00`, Blue: `0xff002776`
   - Map to appropriate Sketchybar color variables (BAR_COLOR, ACCENT_COLOR, etc.)
2. Create `config/sketchybar/colors-personal.sh` by copying current `colors.sh`
3. Keep existing `colors.sh` as default/fallback
4. Document color mapping strategy in `.env.example`
5. All color files use ARGB hex format (`0xAARRGGBB`)
6. Color files are executable shell scripts that export variables

**Prerequisites:** Story 1.1

---

**Story 1.3: Implement Display Mode Detection Helper**

As a dotfiles user,
I want a helper script that detects current display mode,
So that appropriate padding can be applied automatically.

**Acceptance Criteria:**
1. Create `config/sketchybar/helpers/detect-display-mode.sh`
2. Script uses `sketchybar --query displays` to detect configuration
3. Returns "laptop" when only built-in display active
4. Returns "external" when any external monitor connected
5. Script is executable and can be called independently
6. Script exits with appropriate status codes for error handling
7. Script logs output for debugging purposes

**Prerequisites:** Story 1.1

---

**Story 1.4: Create Environment Configuration Loader**

As a dotfiles user,
I want a loader script that reads my .env and generates the appropriate sketchybarrc,
So that Sketchybar automatically loads my environment-specific configuration.

**Acceptance Criteria:**
1. Create `config/sketchybar/helpers/load-env-config.sh`
2. Script sources `.env` file and reads `ENV_TYPE`
3. Script detects display mode using helper from Story 1.3
4. Script selects appropriate padding value based on display mode
5. Script generates `sketchybarrc` that sources correct variant file
6. Script sources environment-specific color file (colors-$ENV_TYPE.sh)
7. Falls back to default colors.sh if environment-specific file missing
8. Logs which configuration is being loaded

**Prerequisites:** Story 1.1, Story 1.2, Story 1.3

---

**Story 1.5: Modify Sketchybar Variants for Dynamic Padding**

As a dotfiles user,
I want Sketchybar variants to read padding from environment variables,
So that notch padding adjusts based on display mode.

**Acceptance Criteria:**
1. Modify `sketchybarrc-laptop` to read padding from `$PADDING` environment variable
2. Update `padding_left` and `padding_right` in bar configuration
3. Modify `notch_width` to be configurable via environment variable (optional)
4. Test that existing functionality remains unchanged with default values
5. Verify variants work with both hardcoded and dynamic padding values
6. Document padding configuration in `.env.example`

**Prerequisites:** Story 1.4

---

**Story 1.6: Integrate Environment Loader at Startup**

As a dotfiles user,
I want Sketchybar to automatically load environment configuration on startup,
So that correct settings apply without manual intervention.

**Acceptance Criteria:**
1. Modify installation script (`scripts/install.sh`) to run environment loader
2. Environment loader executes before Sketchybar starts
3. Generated `sketchybarrc` persists until next environment change
4. Sketchybar restarts/reloads cleanly with new configuration
5. Error handling if `.env` is missing (fallback to defaults with warning message)
6. Logs written to indicate which environment loaded successfully
7. Visual verification of Brazil colors in IPM environment
8. Visual verification of current colors in Personal environment

**Prerequisites:** Story 1.5

---

**Story 1.7: Implement Display Change Event Subscription**

As a dotfiles user,
I want Sketchybar to automatically adjust padding when I connect/disconnect monitors,
So that the bar repositions correctly without manual reload.

**Acceptance Criteria:**
1. Create `config/sketchybar/plugins/handle-display-change.sh`
2. Plugin script re-runs environment loader when display changes
3. Subscribe Sketchybar to `display_change` event in variant configs
4. Event triggers padding recalculation and Sketchybar reload
5. Smooth transition when switching between laptop and external display
6. No flickering or visual glitches during transition
7. Test: Disconnect monitor → verify notch padding applies on IPM laptop
8. Test: Connect monitor → verify standard padding applies

**Prerequisites:** Story 1.6

---

## Epic 2: Calendar Automation

### Expanded Goal

This epic implements reliable, automatic calendar synchronization that eliminates manual intervention and ensures the Sketchybar calendar widget displays accurate, up-to-date meeting information. The system consolidates scattered scripts into the dotfiles repository structure, implements robust sync logic that removes stale events, reads configuration from `.env`, and establishes automatic periodic syncing. It transforms the calendar widget from a manually-maintained feature into a zero-touch automation that users can trust.

### Story Breakdown

**Story 2.1: Consolidate Calendar Scripts into Repository**

As a dotfiles user,
I want all calendar-related scripts located within the dotfiles repository,
So that they are version-controlled and properly maintained.

**Acceptance Criteria:**
1. Move `sync_calendars.sh` to `config/sketchybar/helpers/sync-calendars.sh`
2. Move `meeting.sh` plugin to `config/sketchybar/plugins/meeting.sh` (if not already there)
3. Update all script references/paths in Sketchybar configs
4. Remove old Hammerspoon calendar sync code (if exists)
5. Ensure all calendar scripts are executable (`chmod +x`)
6. Update symlinks in installation script if needed
7. Test that scripts still function after relocation
8. Document script locations in README or CLAUDE.md

**Prerequisites:** None

---

**Story 2.2: Enhance Sync Script with Stale Event Cleanup**

As a dotfiles user,
I want the sync script to remove old/stale events from khal database,
So that only current and upcoming events are displayed.

**Acceptance Criteria:**
1. Modify `sync-calendars.sh` to identify events older than current date/time
2. Script removes past events from khal database after sync
3. Script preserves configurable history window (e.g., keep last 7 days)
4. Add logging to indicate how many stale events were removed
5. Error handling prevents data loss if cleanup fails
6. Test with known stale events to verify removal
7. Verify upcoming events are not affected by cleanup

**Prerequisites:** Story 2.1

---

**Story 2.3: Read Calendar URLs from .env Configuration**

As a dotfiles user,
I want calendar URLs stored in my `.env` file,
So that I can easily manage calendar sources without editing scripts.

**Acceptance Criteria:**
1. Update `.env` file structure to include calendar URL variables
2. Modify `sync-calendars.sh` to source `.env` and read calendar URLs
3. Support multiple calendar URLs (comma-separated or array format)
4. Update `.env.example` with calendar URL documentation
5. Script validates that URLs are defined before attempting sync
6. Error message if calendar URLs missing from `.env`
7. Test sync with URLs from `.env` instead of hardcoded values

**Prerequisites:** Story 2.2, Epic 1 Story 1.1

---

**Story 2.4: Implement Automatic Periodic Sync via LaunchAgent**

As a dotfiles user,
I want calendar sync to run automatically at regular intervals,
So that meeting information stays current without manual intervention.

**Acceptance Criteria:**
1. Create macOS LaunchAgent plist: `~/Library/LaunchAgents/com.user.calendar-sync.plist`
2. LaunchAgent runs `sync-calendars.sh` every 15 minutes
3. LaunchAgent configured to log stdout/stderr for debugging
4. Installation script installs and loads LaunchAgent (`launchctl load`)
5. Script to manually trigger sync outside of schedule (for testing)
6. LaunchAgent persists across system restarts
7. Test: Wait for scheduled sync, verify widget updates automatically
8. Document manual trigger command for troubleshooting

**Prerequisites:** Story 2.3

---

**Story 2.5: Add Comprehensive Error Handling and Logging**

As a dotfiles user,
I want calendar sync errors logged without breaking Sketchybar,
So that I can troubleshoot issues while maintaining widget functionality.

**Acceptance Criteria:**
1. Create log directory: `config/sketchybar/logs/`
2. Sync script writes timestamped logs to `logs/calendar-sync.log`
3. Log rotation implemented (keep last 10 logs or 1MB max)
4. Network errors logged but don't crash script
5. Calendar parse errors logged with event details
6. Meeting widget displays fallback message if sync fails
7. Widget continues showing last successful sync data on error
8. Test: Disconnect network, verify graceful degradation

**Prerequisites:** Story 2.4

---

**Story 2.6: Update Meeting Widget for Reliable Display**

As a dotfiles user,
I want the meeting widget to reliably display next meeting with countdown,
So that I always have accurate information at a glance.

**Acceptance Criteria:**
1. Update `plugins/meeting.sh` to read from current khal database
2. Widget displays next upcoming meeting title and time
3. Countdown timer updates every minute
4. Widget handles no upcoming meetings gracefully ("No meetings")
5. Widget subscribes to custom `calendar_synced` event for immediate updates
6. Sync script triggers `calendar_synced` event after successful sync
7. Visual indicator if last sync failed or is stale
8. Test: Add new meeting, verify it appears within sync interval

**Prerequisites:** Story 2.5

---

**Story 2.7: End-to-End Testing and Documentation**

As a dotfiles user,
I want comprehensive testing and documentation for calendar automation,
So that I can troubleshoot issues and understand the system.

**Acceptance Criteria:**
1. Document calendar automation architecture in CLAUDE.md
2. Add troubleshooting section for common sync issues
3. Test full workflow: new computer setup → calendar sync working
4. Test: Add event to calendar → verify appears in widget within 15 min
5. Test: Delete event → verify removes from widget after sync
6. Test: Network failure → verify graceful degradation
7. Test: Invalid calendar URL → verify error logging and fallback
8. Create manual sync command for immediate refresh
9. Document how to check sync logs and LaunchAgent status

**Prerequisites:** Story 2.6

---

## Epic 3: Widget Experience Enhancement

### Expanded Goal

This epic enhances widget user experience by adding engaging visual feedback, color-coded system alerts, improved time accuracy, and delightful randomized messages. The meeting widget icon will provide urgency cues through animated blinking (breathing when far, heartbeat when close). RAM/CPU widgets will use color thresholds (yellow at 75%, red at 90%) with environment-specific color palettes. Meeting countdown updates will increase to 15-second intervals for better accuracy. Both meeting and Todoist widgets will display randomized encouraging messages when empty, adding personality and reducing monitoring fatigue. These enhancements build on Epic 2's calendar automation to create a more informative and delightful status bar experience.

### Story Breakdown

**Story 3.1: Widget Enhancements and User Experience Improvements**

As a macOS user with Sketchybar widgets,
I want engaging visual feedback and delightful messages from my widgets,
So that my status bar is more informative, less monotonous, and provides better urgency cues.

**Acceptance Criteria:**
1. Meeting widget icon blinks/breathes using yellow color (slow fade >15min, fast heartbeat ≤15min)
2. RAM widget uses color thresholds: default <75%, yellow 75-89%, red ≥90%
3. CPU widget uses color thresholds: default <75%, yellow 75-89%, red ≥90%
4. Threshold colors are environment-specific (Personal: pastel, IPM: Brazil colors)
5. Meeting widget updates countdown every 15 seconds instead of only on calendar_synced
6. Meeting widget displays random messages when no meetings (15+ variations for "end of day" and "free day" scenarios)
7. Todoist widget displays random completion messages when tasks are done (15+ variations)
8. Messages are concise (max 25 characters) and rotate randomly to avoid repetition
9. Completion messages only show when API is successful (not on errors)
10. Test: Verify blinking transitions at 15-minute threshold
11. Test: Simulate high RAM/CPU and verify color changes in both environments
12. Test: Monitor countdown updates every 15 seconds for accuracy
13. Test: Verify message variety over 10+ restarts
14. Test: No performance degradation with increased update frequency

**Prerequisites:** Epic 1 (Environment Configuration), Epic 2 (Calendar Automation)

---

## Story Guidelines Reference

**Story Format:**

```
**Story [EPIC.N]: [Story Title]**

As a [user type],
I want [goal/desire],
So that [benefit/value].

**Acceptance Criteria:**
1. [Specific testable criterion]
2. [Another specific criterion]
3. [etc.]

**Prerequisites:** [Dependencies on previous stories, if any]
```

**Story Requirements:**

- **Vertical slices** - Complete, testable functionality delivery
- **Sequential ordering** - Logical progression within epic
- **No forward dependencies** - Only depend on previous work
- **AI-agent sized** - Completable in 2-4 hour focused session
- **Value-focused** - Integrate technical enablers into value-delivering stories

---

**For implementation:** Use the `create-story` workflow to generate individual story implementation plans from this epic breakdown.
