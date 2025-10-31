#!/usr/bin/env zsh

# Get Simple Icons glyph for an app
# Usage: get_app_icon.sh "App Name"
# Returns: Unicode character for the icon or empty if not found

APP_NAME="$1"

# Convert app name to Simple Icons slug (lowercase, no spaces/special chars)
SLUG=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/ //g' | sed 's/-//g' | sed 's/\.//g')

# Special case mappings for apps with different slugs
case "$SLUG" in
    "code") SLUG="visualstudiocode" ;;
    "visualstudiocode") SLUG="vscode" ;;
    "chatgpt") SLUG="openai" ;;
    "microsoftteams") SLUG="teams" ;;
    "microsoftexcel") SLUG="excel" ;;
    "microsoftword") SLUG="word" ;;
    "microsoftpowerpoint") SLUG="powerpoint" ;;
    "microsoftoutlook") SLUG="outlook" ;;
    "googlechrome") SLUG="googlechrome" ;;
    "jumpdesktop") SLUG="github" ;;  # Fallback example
esac

# Icon codepoints (generated from SimpleIcons.json)
# Format: decimal unicode codepoint
case "$SLUG" in
    "warp") echo -n "$(printf '\uF101')" ;;
    "tresorit") echo -n "$(printf '\uF102')" ;;
    "todoist") echo -n "$(printf '\uF103')" ;;
    "telegram") echo -n "$(printf '\uF104')" ;;
    "spotify") echo -n "$(printf '\uF105')" ;;
    "slack") echo -n "$(printf '\uF106')" ;;
    "signal") echo -n "$(printf '\uF107')" ;;
    "safari") echo -n "$(printf '\uF108')" ;;
    "roblox") echo -n "$(printf '\uF109')" ;;
    "raycast") echo -n "$(printf '\uF10A')" ;;
    "postman") echo -n "$(printf '\uF10B')" ;;
    "openai") echo -n "$(printf '\uF10C')" ;;
    "obsidian") echo -n "$(printf '\uF10D')" ;;
    "notion") echo -n "$(printf '\uF10E')" ;;
    "linear") echo -n "$(printf '\uF10F')" ;;
    "iterm2") echo -n "$(printf '\uF110')" ;;
    "googleslides") echo -n "$(printf '\uF111')" ;;
    "googlesheets") echo -n "$(printf '\uF112')" ;;
    "googledrive") echo -n "$(printf '\uF113')" ;;
    "googledocs") echo -n "$(printf '\uF114')" ;;
    "googlechrome") echo -n "$(printf '\uF115')" ;;
    "github") echo -n "$(printf '\uF116')" ;;
    "firefox") echo -n "$(printf '\uF117')" ;;
    "figma") echo -n "$(printf '\uF118')" ;;
    "discord") echo -n "$(printf '\uF119')" ;;
    "arc") echo -n "$(printf '\uF11A')" ;;
    *) echo -n "" ;;  # Return empty if not found
esac
