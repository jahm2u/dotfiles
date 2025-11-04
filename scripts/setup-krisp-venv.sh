#!/usr/bin/env bash
#
# Setup Python Virtual Environment for Krisp Automation
# Creates venv and installs all required dependencies
#
# Usage: bash scripts/setup-krisp-venv.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="$HOME/.config/sketchybar/venv"
REQUIREMENTS_FILE="$DOTFILES_ROOT/config/sketchybar/requirements.txt"

echo "=== Krisp Automation - Python Virtual Environment Setup ==="
echo ""

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: python3 not found"
    echo "Install via: brew install python3"
    exit 1
fi

PYTHON_VERSION=$(python3 --version)
echo "✓ Found: $PYTHON_VERSION"
echo ""

# Create venv directory if it doesn't exist
mkdir -p "$(dirname "$VENV_DIR")"

# Create virtual environment
if [ -d "$VENV_DIR" ]; then
    echo "⚠️  Virtual environment already exists at: $VENV_DIR"
    read -p "Remove and recreate? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing existing venv..."
        rm -rf "$VENV_DIR"
    else
        echo "Keeping existing venv, will upgrade packages instead"
    fi
fi

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment at: $VENV_DIR"
    python3 -m venv "$VENV_DIR"
    echo "✓ Virtual environment created"
else
    echo "✓ Using existing virtual environment"
fi
echo ""

# Activate venv
source "$VENV_DIR/bin/activate"

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip --quiet
echo "✓ pip upgraded"
echo ""

# Install/upgrade requirements
if [ -f "$REQUIREMENTS_FILE" ]; then
    echo "Installing requirements from: $REQUIREMENTS_FILE"
    echo ""
    pip install -r "$REQUIREMENTS_FILE"
    echo ""
    echo "✓ All requirements installed"
else
    echo "❌ Error: requirements.txt not found at: $REQUIREMENTS_FILE"
    exit 1
fi

# Install Playwright browsers (required for Krisp automation)
echo ""
echo "Installing Playwright browsers (Chromium)..."
playwright install chromium
echo "✓ Playwright browsers installed"

# Verify installation
echo ""
echo "=== Verification ==="
echo ""
echo "Python: $("$VENV_DIR/bin/python3" --version)"
echo "pip: $("$VENV_DIR/bin/pip" --version)"
echo ""
echo "Installed packages:"
"$VENV_DIR/bin/pip" list | grep -E "(openai|playwright|python-dotenv|pyyaml|requests)"
echo ""

echo "=== Setup Complete! ==="
echo ""
echo "Virtual environment location: $VENV_DIR"
echo ""
echo "To activate manually:"
echo "  source $VENV_DIR/bin/activate"
echo ""
echo "Scripts will automatically use: $VENV_DIR/bin/python3"
echo ""
echo "Next steps:"
echo "  1. Configure .env file with TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID"
echo "  2. Run: bash ~/.config/sketchybar/helpers/krisp-refresh-auth.sh"
echo "  3. Test: ~/.config/sketchybar/venv/bin/python3 ~/.config/sketchybar/helpers/krisp-download-transcripts.py --test-auth"
echo ""
