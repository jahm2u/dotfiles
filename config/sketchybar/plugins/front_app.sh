#!/usr/bin/env zsh

# Try to get Simple Icons icon first
SIMPLE_ICON=$(~/.config/sketchybar/helpers/get_app_icon.sh "$INFO")

if [ -n "$SIMPLE_ICON" ]; then
    # Use Simple Icons font
    ICON="$SIMPLE_ICON"
    ICON_FONT="SimpleIcons:Regular:16.0"
else
    # Fall back to Nerd Font icons
    ICON_FONT="sketchybar-app-font:Regular:16.0"
    case $INFO in
"Arc")
    ICON_PADDING_RIGHT=5
    ICON=󰞍
    ;;
"Code")
    ICON_PADDING_RIGHT=4
    ICON=󰨞
    ;;
"Calendar")
    ICON_PADDING_RIGHT=3
    ICON=
    ;;
"Discord")
    ICON=
    ;;
"FaceTime")
    ICON_PADDING_RIGHT=5
    ICON=
    ;;
"Finder")
    ICON=󰀶
    ;;
"Google Chrome")
    ICON_PADDING_RIGHT=7
    ICON=
    ;;
"IINA")
    ICON_PADDING_RIGHT=4
    ICON=󰕼
    ;;
"kitty")
    ICON=󰄛
    ;;
"Messages")
    ICON=
    ;;
"Notion")
    ICON_PADDING_RIGHT=6
    ICON=󰎚
    ;;
"Preview")
    ICON_PADDING_RIGHT=3
    ICON=
    ;;
"PS Remote Play")
    ICON_PADDING_RIGHT=3
    ICON=
    ;;
"Spotify")
    ICON_PADDING_RIGHT=2
    ICON=
    ;;
"TextEdit")
    ICON_PADDING_RIGHT=4
    ICON=
    ;;
"Transmission")
    ICON_PADDING_RIGHT=3
    ICON=󰶘
    ;;
"Slack")
    ICON_PADDING_RIGHT=3
    ICON=󰒱
    ;;
"Todoist")
    ICON_PADDING_RIGHT=3
    ICON=󰃯
    ;;
"Obsidian")
    ICON_PADDING_RIGHT=3
    ICON=󱉽
    ;;
"Safari")
    ICON_PADDING_RIGHT=3
    ICON=󰀹
    ;;
"Terminal")
    ICON_PADDING_RIGHT=3
    ICON=
    ;;
"Zoom")
    ICON_PADDING_RIGHT=3
    ICON=󰍫
    ;;
"Microsoft Teams")
    ICON_PADDING_RIGHT=3
    ICON=󰊻
    ;;
"WhatsApp")
    ICON_PADDING_RIGHT=3
    ICON=
    ;;
"Telegram")
    ICON_PADDING_RIGHT=3
    ICON=
    ;;
"Signal")
    ICON_PADDING_RIGHT=3
    ICON=󰭹
    ;;
"Firefox")
    ICON_PADDING_RIGHT=3
    ICON=󰈹
    ;;
"iTerm2")
    ICON_PADDING_RIGHT=3
    ICON=
    ;;
"Music")
    ICON_PADDING_RIGHT=3
    ICON=
    ;;
"Notes")
    ICON_PADDING_RIGHT=3
    ICON=󰎞
    ;;
"Reminders")
    ICON_PADDING_RIGHT=3
    ICON=󰄲
    ;;
"Mail")
    ICON_PADDING_RIGHT=3
    ICON=󰇰
    ;;
"System Preferences"|"System Settings")
    ICON_PADDING_RIGHT=3
    ICON=󰒓
    ;;
"Activity Monitor")
    ICON_PADDING_RIGHT=3
    ICON=󰍛
    ;;
"Raycast")
    ICON_PADDING_RIGHT=3
    ICON=󰜬
    ;;
"Warp")
    ICON_PADDING_RIGHT=3
    ICON=󰄛
    ;;
"Docker Desktop")
    ICON_PADDING_RIGHT=3
    ICON=󰡨
    ;;
"Postman")
    ICON_PADDING_RIGHT=3
    ICON=󰖟
    ;;
"Visual Studio Code")
    ICON_PADDING_RIGHT=3
    ICON=󰨞
    ;;
"Mailspring")
    ICON_PADDING_RIGHT=3
    ICON=󰇰
    ;;
"ChatGPT")
    ICON_PADDING_RIGHT=3
    ICON=󰭹
    ;;
"Comet")
    ICON_PADDING_RIGHT=3
    ICON=
    ;;
"Jump Desktop")
    ICON_PADDING_RIGHT=3
    ICON=󰢹
    ;;
"OrbStack")
    ICON_PADDING_RIGHT=3
    ICON=󰡨
    ;;
"Pritunl")
    ICON_PADDING_RIGHT=3
    ICON=󰒃
    ;;
"TablePlus")
    ICON_PADDING_RIGHT=3
    ICON=󰆼
    ;;
"Wispr Flow")
    ICON_PADDING_RIGHT=3
    ICON=󰔊
    ;;
"krisp")
    ICON_PADDING_RIGHT=3
    ICON=󰕿
    ;;
"stable")
    ICON_PADDING_RIGHT=3
    ICON=󰐃
    ;;
*)
    ICON_PADDING_RIGHT=2
    ICON=
    ;;
    esac
fi

sketchybar --set $NAME \
    icon="$ICON" \
    icon.font="$ICON_FONT" \
    icon.padding_left=7 \
    icon.padding_right=7

sketchybar --set $NAME.name label="$INFO"