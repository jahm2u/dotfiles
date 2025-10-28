# SketchyBar Configuration Reference

**Documentation Source:** https://felixkratz.github.io/SketchyBar/
**Last Updated:** 2025-10-27

This document provides a comprehensive reference for SketchyBar configuration, extracted from the official documentation.

---

## Table of Contents

1. [Bar Configuration](#bar-configuration)
2. [Items](#items)
3. [Components](#components)
4. [Popup Menus](#popup-menus)
5. [Events System](#events-system)
6. [Querying](#querying)
7. [Animations](#animations)
8. [Data Types](#data-types)
9. [Reloading](#reloading)
10. [Tips & Tricks](#tips--tricks)

---

## Bar Configuration

### Overview
SketchyBar's configuration file is located at `~/.config/sketchybar/sketchybarrc` and executes when the application launches. You can test settings on-the-fly via command line before making them permanent.

### Configuration Syntax
```bash
sketchybar --bar <setting>=<value>
```

### Key Configuration Properties

| Property | Type | Default | Purpose |
|----------|------|---------|---------|
| `color` | ARGB hex | `0x44000000` | Bar background color |
| `border_color` | ARGB hex | `0xffff0000` | Border color |
| `position` | top/bottom | `top` | Bar placement on screen |
| `height` | integer | `25` | Bar dimensions in pixels |
| `margin` | integer | `0` | Spacing around bar perimeter |
| `y_offset` | integer | `0` | Vertical positioning adjustment |
| `corner_radius` | positive integer | `0` | Rounded corner size |
| `border_width` | positive integer | `0` | Border thickness |
| `blur_radius` | positive integer | `0` | Background blur effect |
| `padding_left/right` | positive integer | `0` | Internal spacing |
| `display` | main/all/list | `all` | Target display(s) |
| `topmost` | boolean/window | `off` | Layering behavior |
| `sticky` | boolean | `on` | Persistence during space changes |
| `shadow` | boolean | `off` | Shadow rendering |

### Notch Display Settings
- `notch_display_height`: Override bar height on notched displays
- `notch_width`: Account for notch dimensions (default `200`)
- `notch_offset`: Additional vertical adjustment for notched screens

### Workflow Tips
Run SketchyBar directly from terminal to view error messages, enabling easier configuration refinement before committing to your configuration file.

---

## Items

### Core Item Structure
Items are the fundamental building blocks of SketchyBar. They can be positioned in the bar (`left`, `right`, `center`, `q` for left of notch, or `e` for right of notch) and configured through various property categories.

### Adding Items
```bash
sketchybar --add item <name> <position>
```

The name identifies the item for later configuration and shouldn't contain spaces unless quoted.

### Primary Property Categories

**Geometry Properties**: Control visual placement and sizing including `drawing`, `position`, `space`, `display`, `y_offset`, `padding_left`, `padding_right`, `width`, `scroll_texts`, `blur_radius`, and `background` properties.

**Text Properties**: Manage rendering appearance with options for `drawing`, `highlight`, `color`, `highlight_color`, padding, `font` (family/style/size), `string` content, `scroll_duration`, `max_chars`, `width`, and `align` (center/left/right).

**Icon and Label Properties**: Both support dedicated `<string>` values and inherit all text properties for customization.

**Scripting Properties**: Enable interactivity through `script`, `click_script`, `update_freq`, `updates`, and `mach_helper` for event handling.

**Visual Enhancement Properties**: Include background styling with borders, corner radius, and clipping; image handling with scaling and borders; and shadow effects with angle and distance controls.

### Item Management Operations

- **Reordering**: `sketchybar --reorder <name> ... <name>`
- **Moving**: `sketchybar --move <name> before/after <reference>`
- **Cloning**: `sketchybar --clone <parent> <name>`
- **Renaming**: `sketchybar --rename <old> <new>`
- **Removing**: `sketchybar --remove <name>`

Default values can be modified globally to apply to subsequently created items.

---

## Components

SketchyBar offers five special component types, each extending standard item functionality:

### 1. Data Graph
**Purpose:** Visualize arbitrary data as a line graph within the bar.

**Command:**
```bash
sketchybar --add graph <name> <position> <width in points>
```

**Key Properties:**
- `graph.color`: Line color (default: `0xffcccccc`)
- `graph.fill_color`: Fill beneath line (default: `0xffcccccc`)
- `graph.line_width`: Line thickness in points (default: `0.5`)

**Usage:** Push data points (0-1 range) using `sketchybar --push <name> <values>`. Graphs expand to bar height unless constrained by background dimensions and `y_offset`.

### 2. Space Component
**Purpose:** Link Mission Control spaces to bar items for workspace management.

**Command:**
```bash
sketchybar --add space <name> <position>
```

**Key Variables in Scripts:**
- `$SELECTED`: Boolean indicating active space status
- `$SID`: Space identifier
- `$DID`: Display identifier

**Default Behavior:** Highlights icon when space is active. Customize via script property.

### 3. Item Bracket
**Purpose:** Group items together with a unified background styling.

**Command:**
```bash
sketchybar --add bracket <name> <member names>
```

**Features:**
- Accepts individual item names or regex patterns (`/pattern/`)
- Supports all background properties (color, corner_radius, height)
- Flexible spanning across different bar positions

### 4. Item Alias
**Purpose:** Mirror macOS menu bar items into SketchyBar.

**Command:**
```bash
sketchybar --add alias <application_name> <position>
```

**Advanced Syntax:**
```bash
sketchybar --add alias "<window_owner>,<window_name>" <position>
```

**Customization:**
- `alias.color`: Override item color
- `alias.scale`: Adjust display size
- `alias.update_freq`: Refresh interval in seconds

**Discovery:** Use `sketchybar --query default_menu_items` to list available aliases.

### 5. Slider
**Purpose:** Create draggable progression indicators for value adjustment.

**Command:**
```bash
sketchybar --add slider <name> <position> <width>
```

**Properties:**
- `slider.percentage`: Current progress (0-100)
- `slider.highlight_color`: Active progression color (default: `0xff0000ff`)
- `slider.knob`: Custom knob element with text properties
- `slider.background`: All standard background styling

**Interaction:** Responds to `mouse.clicked` events, providing `$PERCENTAGE` variable matching click position. Dragging triggers single event on release.

---

## Popup Menus

### Core Concept
Popup menus enable items to appear in a small popup window below any bar item.

### Configuration Properties

```bash
sketchybar --set <name> popup.<property>=<value>
```

| Property | Type | Default | Purpose |
|----------|------|---------|---------|
| `drawing` | boolean | off | Controls popup visibility |
| `horizontal` | boolean | off | Enables horizontal rendering |
| `topmost` | boolean | on | Keeps popup above other windows |
| `height` | positive integer | bar height | Vertical spacing between popup items |
| `blur_radius` | positive integer | 0 | Background blur effect |
| `y_offset` | integer | 0 | Vertical positioning adjustment |
| `align` | left/right/center | left | Popup alignment relative to parent |
| `background` | properties | — | Full background styling support |

### Adding Items to Popups

Items are added to popups by setting their `position` property to `popup.<parent_name>`, where `<parent_name>` is the item containing the popup.

---

## Events System

### Core Concept
SketchyBar uses an event-driven architecture where items subscribe to events and execute scripts reactively.

### Subscription Syntax
```bash
sketchybar --subscribe <name> <event> ... <event>
```

### Built-in Event Types

**System Events:**
- `front_app_switched` - Application focus changes
- `space_change` - Active Mission Control space switches
- `space_windows_change` - Windows created/destroyed on a space
- `display_change` - Active display changes
- `power_source_change` - Power source toggles (AC/BATTERY)
- `system_will_sleep` / `system_woke` - Sleep state changes

**Hardware Events:**
- `volume_change` - Audio volume adjustment
- `brightness_change` - Display brightness adjustment
- `wifi_change` - WiFi connection status (not functional on Sonoma)
- `media_change` - Media playback changes (experimental)

**Mouse Events:**
- `mouse.entered` / `mouse.exited` - Item hover states
- `mouse.clicked` - Click interaction with button/modifier info
- `mouse.scrolled` - Scroll wheel interaction
- Global variants available for bar-wide detection

### Environment Variables in Scripts

Scripts receive automatic access to:
- `$NAME` - Item name
- `$SENDER` - Event trigger reason
- `$CONFIG_DIR` - Configuration directory path

Click events additionally provide `$BUTTON` and `$MODIFIER`. Scroll events include `$SCROLL_DELTA`.

### Custom Events

Create application-specific events:
```bash
sketchybar --add event <name> [NSDistributedNotificationName]
```

Trigger them with optional variables:
```bash
sketchybar --trigger <event> VAR=value
```

Custom events can subscribe to macOS system notifications like `com.spotify.client.PlaybackStateChanged`.

### Force Refresh
```bash
sketchybar --update
```
Forces all scripts to execute and events to emit (never use within item scripts to avoid infinite loops).

---

## Querying

SketchyBar allows users to retrieve configuration and system information through command-line queries that return JSON-formatted responses.

### Query Types

**Bar Configuration**
```bash
sketchybar --query bar
```

**Individual Items**
```bash
sketchybar --query <name>
```

**Current Defaults**
```bash
sketchybar --query defaults
```

**Event Information**
```bash
sketchybar --query events
```

**Menu Bar Items**
```bash
sketchybar --query default_menu_items
```

**Display Settings**
```bash
sketchybar --query displays
```

All queries return structured JSON data.

---

## Animations

### Animation Command Structure

```bash
sketchybar --animate <curve> <duration> \
  --bar <property>=<value> ... \
  --set <name> <property>=<value> ...
```

### Available Animation Curves
- linear
- quadratic
- tanh
- sin
- exp
- circ

### Duration Parameter
Duration is measured in frames on a 60Hz display. 60 frames = ~1 second.

### Chaining Animations
Multiple animations can be sequenced by specifying the same property multiple times in one command.

### Animation Interruption
- New non-animated commands cancel the queue and immediately apply values
- New animated commands cancel the current queue and restart from present state

---

## Data Types

### Core Data Types

| Type | Accepted Values |
|------|---|
| **Boolean** | `on`, `off`, `yes`, `no`, `true`, `false`, `1`, `0`, `toggle` |
| **ARGB Hex Color** | 8-digit hexadecimal with alpha, red, green, and blue channels |
| **Path** | Absolute file paths |
| **String** | UTF-8 text or symbols |
| **Float** | Floating point numbers |
| **Integer** | Whole numbers |
| **Positive Integer** | Non-negative whole numbers |
| **Positive Integer List** | Comma-separated positive integers |

### Special Operations

**Boolean Negation**: Prefix with `!` to invert (e.g., `!on`)

**Color Channel Access**: ARGB hex colors support granular channel modification:
- `alpha` (0 to 1, default 1.0)
- `red` (0 to 1, default 1.0)
- `green` (0 to 1, default 1.0)
- `blue` (0 to 1, default 1.0)

Example: `sketchybar --bar color.alpha=0.5`

---

## Reloading

### Manual Reload
```bash
sketchybar --reload [Optional: <path>]
```

Refreshes configuration without restarting. Optionally specify path to different `sketchybarrc`.

### Hotloading Feature
```bash
sketchybar --hotload <boolean>
```

Monitors configuration directory and automatically refreshes when changes detected. Eliminates need for manual reloads during development.

---

## Tips & Tricks

### Command Batching
Combine multiple configuration calls into a single command to reduce startup time and improve readability. Use backslashes to continue lines, ensuring no trailing whitespace after the escape character.

### Bash Arrays for Cleaner Code
Replace line-continuation backslashes with bash arrays:
```bash
bar=(height=32 blur_radius=30...)
sketchybar --bar "${bar[@]}"
```

### Debugging Workflow
1. Run sketchybar from command line to view verbose messages
2. Check for trailing whitespace after backslash escapes
3. Verify scripts are executable: `chmod +x script.sh`
4. Isolate issues with minimal configuration
5. Test problematic scripts directly in terminal
6. Query SketchyBar properties to diagnose root causes
7. Report issues on GitHub if needed

### Color Specification
SketchyBar uses ARGB hex format: `0xAARRGGBB` where AA = alpha (transparency), RR = red, GG = green, BB = blue.

### Icon Resources
- Default font: Hack Nerd Font (supports all Nerdfont icons)
- Reference: Nerdfont cheat-sheet at nerdfonts.com
- Alternative: SF Symbols from Apple (`brew install --cask sf-symbols`)
- Community option: app-icon-font for stylized application icons

### Multiple Independent Bars
Create additional bars by symlinking the binary with a different name (e.g., `bottom_bar`). Configuration lives in `$HOME/.config/[name]/`. Use the `$BAR_NAME` environment variable in scripts for bar-agnostic configuration.

### Performance Optimization Strategies
- Batch configuration commands
- Use `updates=when_shown` for items that don't need background execution
- Reduce update frequency; prefer event-driven scripting
- Avoid aliases for non-persistent applications
- Consider compiled `mach_helper` programs for demanding tasks (v2.9.0+)

---

## Key Insights for Our Environment Configuration

Based on this documentation, here's how we should approach environment-aware configuration:

### 1. Display Change Detection
- Use `display_change` event to trigger padding adjustments
- Query `sketchybar --query displays` to detect laptop vs external monitor

### 2. Configuration Reloading
- Use `sketchybar --reload` to apply new configurations
- Consider enabling `hotload` during development

### 3. Multiple Config Files
- Main `sketchybarrc` sources different variant files (already implemented)
- Each variant can source different color files
- `.env` file determines which variant to load

### 4. Event-Driven Approach
- Subscribe calendar widget to custom events for sync triggers
- Use `display_change` event for automatic padding adjustment
- Custom events for environment switching

### 5. Color Management
- Continue using separate color files (e.g., `colors-ipm.sh`, `colors-personal.sh`)
- Source appropriate color file based on `.env` configuration
- ARGB hex format: `0xAARRGGBB`
