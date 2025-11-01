#!/usr/bin/env bash

# Close all popups - called when focus changes or clicking outside
sketchybar --set todoist popup.drawing=off \
           --set meeting popup.drawing=off \
           --set cpu popup.drawing=off \
           --set memory popup.drawing=off \
           --set week_num popup.drawing=off
