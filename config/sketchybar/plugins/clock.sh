#!/usr/bin/env zsh

# Format date with 12-hour time (more readable than 24h)
FORMATTED_DATE=$(date '+%a, %b %-d')
TIME=$(date '+%-I:%M%p' | tr '[:upper:]' '[:lower:]')

sketchybar --set $NAME label="${FORMATTED_DATE} ${TIME}"

