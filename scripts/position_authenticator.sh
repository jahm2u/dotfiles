#!/bin/bash

# Position Authenticator app window on the right side of the main display

osascript <<EOF
tell application "System Events"
    tell process "Authenticator"
        set frontmost to true
        delay 0.2
        
        -- Get the main display bounds
        tell application "Finder"
            set displayBounds to bounds of window of desktop
        end tell
        
        -- Calculate right-aligned position
        -- displayBounds format: {left, top, right, bottom}
        set displayWidth to item 3 of displayBounds
        set displayHeight to item 4 of displayBounds
        
        -- Set window size and position (adjust these values as needed)
        set windowWidth to 400
        set windowHeight to 600
        set rightMargin to 20
        
        -- Position window on the right side
        set windowX to displayWidth - windowWidth - rightMargin
        set windowY to 100
        
        -- Apply position to the first window
        if (count of windows) > 0 then
            set position of window 1 to {windowX, windowY}
            set size of window 1 to {windowWidth, windowHeight}
        end if
    end tell
end tell
EOF