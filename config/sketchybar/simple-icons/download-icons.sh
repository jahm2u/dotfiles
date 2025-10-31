#!/bin/bash

# Download Simple Icons for all installed apps
# This script scans /Applications and downloads available icons from Simple Icons CDN

ICONS_DIR="$HOME/.config/sketchybar/simple-icons/svgs"
mkdir -p "$ICONS_DIR"

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Scanning /Applications for apps...${NC}"

# Get all apps and convert to Simple Icons slugs
SUCCESS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

while IFS= read -r app_name; do
    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    # Convert app name to Simple Icons slug format
    # Rules: lowercase, remove spaces, remove special chars
    slug=$(echo "$app_name" | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/ //g' | \
        sed 's/-//g' | \
        sed 's/\.//g')

    # Try to download icon from Simple Icons CDN
    url="https://cdn.simpleicons.org/$slug"
    output_file="$ICONS_DIR/$slug.svg"

    # Download with curl, check HTTP status
    http_code=$(curl -s -w "%{http_code}" -o "$output_file" "$url")

    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✓${NC} $app_name → $slug.svg"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        # Remove failed download
        rm -f "$output_file"
        echo -e "${RED}✗${NC} $app_name (slug: $slug) - not found in Simple Icons"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done < <(ls -1 /Applications/ | grep "\.app$" | sed 's/\.app$//')

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Successfully downloaded: $SUCCESS_COUNT icons${NC}"
echo -e "${RED}Not found in Simple Icons: $FAIL_COUNT apps${NC}"
echo -e "${BLUE}Total apps scanned: $TOTAL_COUNT${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Icons saved to: ${BLUE}$ICONS_DIR${NC}"
