#!/bin/bash

# Color Scheme for SketchyBar
# Based on Catppuccin Macchiato theme

# Base colors
export BLACK=0xff181926          # crust
export SURFACE0=0xff363a4f       # surface0
export SURFACE1=0xff494d64       # surface1
export SURFACE2=0xff5b6078       # surface2
export OVERLAY0=0xff6e738d       # overlay0
export OVERLAY1=0xff8087a2       # overlay1
export OVERLAY2=0xff939ab7       # overlay2
export WHITE=0xffcad3f5          # text
export LAVENDER=0xffb7bdf8       # lavender
export BLUE=0xff8aadf4           # blue
export SAPPHIRE=0xff7dc4e4       # sapphire
export SKY=0xff91d7e3            # sky
export TEAL=0xff8bd5ca           # teal
export GREEN=0xffa6da95          # green
export YELLOW=0xffeed49f         # yellow
export PEACH=0xfff5a97f          # peach
export MAROON=0xffee99a0         # maroon
export RED=0xffed8796            # red
export MAUVE=0xffc6a0f6          # mauve
export PINK=0xfff5bde6           # pink
export FLAMINGO=0xfff0c6c6       # flamingo
export ROSEWATER=0xfff4dbd6      # rosewater
export TRANSPARENT=0x00000000

# Bar colors
export BAR_COLOR=$TRANSPARENT
export BAR_BORDER_COLOR=$TRANSPARENT

# Item defaults
export BACKGROUND_COLOR=$SURFACE1
export BACKGROUND_OPACITY=0x66494d64   # Surface1 with 40% opacity
export BACKGROUND_LESS_TRANSPARENT=0xBB494d64   # Surface1 with 73% opacity
export ICON_COLOR=$WHITE
export LABEL_COLOR=$WHITE
export ACCENT_COLOR=$PEACH

# Solid backgrounds for widgets
export WIDGET_BACKGROUND=$SURFACE1

# Specific item colors
export WORKSPACE_ACTIVE=$BLUE
export WORKSPACE_INACTIVE=$WHITE
export FRONT_APP_COLOR=$GREEN
export BATTERY_LOW=$RED
export BATTERY_MEDIUM=$YELLOW
export BATTERY_HIGH=$GREEN
export NETWORK_ACTIVE=$SAPPHIRE
export NETWORK_INACTIVE=$OVERLAY0

# Widget color groups - Professional palette
# System monitoring (CPU, Memory) - Muted blue
export SYSTEM_COLOR=$BLUE

# Media/Audio (Volume) - Dark gray  
export MEDIA_COLOR=$SURFACE2

# Network/Connectivity - Teal
export NETWORK_COLOR=$TEAL

# Time/Weather - Subtle gray
export TIME_COLOR=$OVERLAY2

# Battery - Dynamic (changes with level)
export BATTERY_COLOR=$YELLOW

# Apps - Muted green
export APP_COLOR=$TEAL

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
