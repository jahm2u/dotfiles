#!/bin/bash

# Color Scheme for SketchyBar - IPM Environment
# Based on Brazil flag colors (Green, Yellow, Blue)
# Official colors: Green #009B3A (Vert), Yellow #FEDD00 (Jaune), Blue #002776 (Bleu)

# Base colors - maintaining Catppuccin neutrals for consistency
export BLACK=0xff181926          # crust
export SURFACE0=0xff363a4f       # surface0
export SURFACE1=0xff494d64       # surface1
export SURFACE2=0xff5b6078       # surface2
export OVERLAY0=0xff6e738d       # overlay0
export OVERLAY1=0xff8087a2       # overlay1
export OVERLAY2=0xff939ab7       # overlay2
export WHITE=0xffcad3f5          # text
export LAVENDER=0xffb7bdf8       # lavender

# Brazil flag colors (official)
export BLUE=0xff002776           # Brazil Blue (official flag color)
export GREEN=0xff009B3A          # Brazil Green (official flag color)
export YELLOW=0xffFEDD00         # Brazil Yellow (official flag color)

# Catppuccin color names mapped to Brazil colors for compatibility
export TEAL=0xff009B3A           # → Brazil Green (used in front_app)
export PEACH=0xffFEDD00          # → Brazil Yellow (used as warm accent)
export SAPPHIRE=0xff3399FF       # → Lighter Brazil Blue
export SKY=0xff4DA6FF            # → Light blue (between blue and cyan)
export PINK=0xffFFE680           # → Light Brazil Yellow
export MAUVE=0xff004BA8          # → Medium Brazil Blue
export MAROON=0xff006B2D         # → Dark Brazil Green
export RED=0xffed8796            # Keep original red for errors
export FLAMINGO=0xfff0c6c6       # flamingo
export ROSEWATER=0xfff4dbd6      # rosewater
export TRANSPARENT=0x00000000

# Bar colors
export BAR_COLOR=$TRANSPARENT
export BAR_BORDER_COLOR=$TRANSPARENT

# Item defaults - using Brazil Yellow as accent
export BACKGROUND_COLOR=$SURFACE1
export BACKGROUND_OPACITY=0x66494d64   # Surface1 with 40% opacity
export BACKGROUND_LESS_TRANSPARENT=0xBB494d64   # Surface1 with 73% opacity
export ICON_COLOR=$WHITE
export LABEL_COLOR=$WHITE
export ACCENT_COLOR=$YELLOW          # Brazil Yellow for prominence

# Solid backgrounds for widgets
export WIDGET_BACKGROUND=$SURFACE1

# Specific item colors - Brazil Blue for active states
export WORKSPACE_ACTIVE=$BLUE        # Brazil Blue for active workspace (legacy)
export WORKSPACE_ACTIVE_BG=$GREEN    # Green background for active workspace
export WORKSPACE_ACTIVE_TEXT=$WHITE  # White text on active workspace
export WORKSPACE_INACTIVE=$WHITE
export FRONT_APP_COLOR=$GREEN        # Brazil Green for active app
export BATTERY_LOW=$RED
export BATTERY_MEDIUM=$YELLOW        # Brazil Yellow
export BATTERY_HIGH=$GREEN           # Brazil Green
export NETWORK_ACTIVE=$SAPPHIRE
export NETWORK_INACTIVE=$OVERLAY0

# Widget color groups - Professional palette
# System monitoring (CPU, Memory) - Brazil Blue
export SYSTEM_COLOR=$BLUE            # Brazil Blue

# Media/Audio (Volume) - Dark gray
export MEDIA_COLOR=$SURFACE2

# Network/Connectivity - Teal
export NETWORK_COLOR=$TEAL

# Time/Weather - Subtle gray
export TIME_COLOR=$OVERLAY2

# Battery - Dynamic (changes with level)
export BATTERY_COLOR=$YELLOW         # Brazil Yellow

# Apps - Brazil Green
export APP_COLOR=$GREEN              # Brazil Green

# Additional pastel variations for future widgets
export LIGHT_PEACH=0xfff7d4b5        # Lighter peach
export LIGHT_GREEN=0xffcae8d5        # Lighter green
export LIGHT_BLUE=0xffc4d3f7         # Lighter blue
export LIGHT_YELLOW=0xfff5f0c4       # Lighter yellow
export LIGHT_PINK=0xfff8e1ed         # Lighter pink
export LIGHT_TEAL=0xffc9e7e0         # Lighter teal
export LIGHT_LAVENDER=0xffe0e3f9     # Lighter lavender
export LIGHT_MAROON=0xfff4e4e6       # Lighter maroon
export LIGHT_MAUVE=0xffe5d9f5        # Lighter mauve

# Medium intensity variants
export MID_ORANGE=0xfff2b888         # Medium orange
export MID_CORAL=0xfff0a4a8          # Medium coral
export MID_MINT=0xffa8d8c8           # Medium mint
export MID_PERIWINKLE=0xffb8c5f2     # Medium periwinkle
export MID_ROSE=0xfff2c4d1           # Medium rose
