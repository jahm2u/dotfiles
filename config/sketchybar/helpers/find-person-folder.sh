#!/usr/bin/env bash
#
# Find person folder in Obsidian vault structure
# Searches in priority order and validates folder structure
#

set -euo pipefail

# Function to print usage
usage() {
    echo "Usage: $0 --person NAME --company COMPANY [--vault-path PATH]"
    echo ""
    echo "Options:"
    echo "  --person NAME        Person name to search for"
    echo "  --company COMPANY    Company context (IPMedia, TP, MT, etc.)"
    echo "  --vault-path PATH    Override vault path (default: from OBSIDIAN_VAULT_PATH env)"
    exit 1
}

# Parse arguments
PERSON=""
COMPANY=""
VAULT_PATH="${OBSIDIAN_VAULT_PATH:-}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --person)
            PERSON="$2"
            shift 2
            ;;
        --company)
            COMPANY="$2"
            shift 2
            ;;
        --vault-path)
            VAULT_PATH="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$PERSON" ]]; then
    echo "Error: --person is required" >&2
    usage
fi

if [[ -z "$VAULT_PATH" ]]; then
    echo "Error: OBSIDIAN_VAULT_PATH not set in environment and --vault-path not provided" >&2
    exit 1
fi

if [[ ! -d "$VAULT_PATH" ]]; then
    echo "Error: Vault path does not exist: $VAULT_PATH" >&2
    exit 1
fi

# Normalize Unicode to NFD (macOS filesystem uses NFD normalization)
# This handles accented characters like "Otávio" correctly
PERSON=$(python3 -c "import unicodedata, sys; print(unicodedata.normalize('NFD', sys.argv[1]))" "$PERSON")

# Name aliases mapping (handle common variations using case statement)
case "$PERSON" in
    "DBoy")
        PERSON="Danniboy"
        ;;
    "Kayla")
        PERSON="Queila"
        ;;
    "Kyle")
        PERSON="Caio"
        ;;
    "RafaelN")
        PERSON="Rafael"
        ;;
esac

# Function for case-insensitive folder search (optimized for iCloud)
find_person_folder() {
    local base_path="$1"
    local person_name="$2"

    # Case-insensitive search - loop through directories and compare lowercase
    # NOTE: We don't use [[ -d "$base_path/$person_name" ]] as an optimization
    # because on case-insensitive filesystems (macOS), it succeeds with wrong case
    # but returns the input case instead of the canonical filesystem name
    local search_lower=$(echo "$person_name" | tr '[:upper:]' '[:lower:]')

    # Loop through directories in base path
    for dir in "$base_path"/*/; do
        # Skip if no directories found (glob doesn't match)
        [[ -d "$dir" ]] || continue

        # Get directory name without trailing slash
        local dirname=$(basename "$dir")
        local dirname_lower=$(echo "$dirname" | tr '[:upper:]' '[:lower:]')

        # Case-insensitive comparison
        if [[ "$dirname_lower" == "$search_lower" ]]; then
            echo "$base_path/$dirname"
            return 0
        fi
    done

    return 1
}

# Define search paths in priority order
SEARCH_BASES=()

# 1. Active IPMedia team members
SEARCH_BASES+=("$VAULT_PATH/Business/People/IPMedia")

# 2. CO company leaders (if company specified)
if [[ -n "$COMPANY" && "$COMPANY" != "IPMedia" && "$COMPANY" != "unknown" ]]; then
    SEARCH_BASES+=("$VAULT_PATH/Business/People/CO/$COMPANY")
fi

# 3. Personal friends
SEARCH_BASES+=("$VAULT_PATH/Personal/Friends")

# 4. Personal family
SEARCH_BASES+=("$VAULT_PATH/Personal/Family")

# 5. Inactive/former employees
SEARCH_BASES+=("$VAULT_PATH/Business/People/IPMedia/Inactive")

# Search for person folder
FOUND_PATH=""
for base in "${SEARCH_BASES[@]}"; do
    if [[ -d "$base" ]]; then
        # Temporarily allow errors for the function call
        set +e
        person_path=$(find_person_folder "$base" "$PERSON")
        set -e
        if [[ -n "$person_path" ]]; then
            FOUND_PATH="$person_path"
            break
        fi
    fi
done

# If found, ensure Meetings/ subdirectory exists
if [[ -n "$FOUND_PATH" ]]; then
    MEETINGS_DIR="$FOUND_PATH/Meetings"

    # Auto-create Meetings/ if person folder exists but Meetings/ doesn't
    if [[ ! -d "$MEETINGS_DIR" ]]; then
        mkdir -p "$MEETINGS_DIR"
        echo "INFO: Created Meetings/ directory for $PERSON" >&2
    fi
fi

# Return result
if [[ -n "$FOUND_PATH" ]]; then
    # Output the found path
    echo "$FOUND_PATH"
    exit 0
else
    # Person not found
    echo "Error: Person folder not found for: $PERSON" >&2
    echo "" >&2
    echo "Searched locations:" >&2
    for base in "${SEARCH_BASES[@]}"; do
        echo "  - $base/$PERSON" >&2
    done
    echo "" >&2
    echo "Tip: You may need to run the person onboarding workflow to create this structure." >&2
    exit 1
fi
