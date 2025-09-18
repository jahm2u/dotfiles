#!/usr/bin/env bash

# Get current week number
WEEK=$(date +%V)

# Get current date and time
DATETIME=$(date "+%b %d %H:%M")

# Update the week items - W30 inside colored box, date/time outside
sketchybar --set "$NAME" icon="W$WEEK" \
           --set "${NAME}.name" label="$DATETIME"