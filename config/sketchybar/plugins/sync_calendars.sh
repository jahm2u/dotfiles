#!/bin/bash

# Source the .env file to get ICAL_URLS
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo "Error: .env file not found"
    exit 1
fi

# Create calendar directories
mkdir -p ~/.local/share/khal/calendars/{google,fm}

# Download and import calendars
IFS=',' read -ra URLS <<< "$ICAL_URLS"
for i in "${!URLS[@]}"; do
    URL="${URLS[$i]}"
    
    # Determine calendar name
    if [[ "$URL" == *"google"* ]]; then
        CAL_NAME="google"
    elif [[ "$URL" == *"user.fm"* ]]; then
        CAL_NAME="fm"
    else
        continue
    fi
    
    # Download calendar
    TEMP_FILE=$(mktemp)
    echo "Downloading $CAL_NAME calendar..."
    if curl -sL "$URL" -o "$TEMP_FILE"; then
        # Check if it's a valid ICS file
        if grep -q "BEGIN:VCALENDAR" "$TEMP_FILE"; then
            echo "Importing events to $CAL_NAME..."
            # Import to khal (batch mode, no confirmation)
            khal import -a "$CAL_NAME" --batch "$TEMP_FILE"
        else
            echo "Error: Invalid calendar file for $CAL_NAME"
            cat "$TEMP_FILE" | head -5
        fi
    else
        echo "Error: Failed to download $CAL_NAME calendar"
    fi
    rm -f "$TEMP_FILE"
done

echo "Calendar sync complete"