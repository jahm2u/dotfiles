#!/usr/bin/env bash

# Get current week number
WEEK=$(date +%V)

# Update just the icon with W30 format
sketchybar --set "$NAME" label="W$WEEK"