#!/usr/bin/env bash

# Dotfiles Bootstrap Script
# This script sets up a complete macOS development environment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where this script is located
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if running on macOS
check_macos() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        error "This script is designed for macOS only!"
        exit 1
    fi
    log "✓ Running on macOS"
}

# Install or update Homebrew
install_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        log "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Add Homebrew to PATH for Apple Silicon Macs
        if [[ -f "/opt/homebrew/bin/brew" ]]; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    else
        log "Homebrew already installed, updating..."
        brew update
    fi
    success "✓ Homebrew ready"
}

# Install packages from Brewfile with retry logic
install_packages() {
    log "Installing packages from Brewfile..."
    
    if [[ ! -f "$DOTFILES_DIR/Brewfile" ]]; then
        error "Brewfile not found at $DOTFILES_DIR/Brewfile"
        exit 1
    fi
    
    cd "$DOTFILES_DIR"
    
    # First attempt
    if brew bundle --verbose; then
        success "✓ All packages installed successfully"
    else
        warn "Some packages failed to install, attempting retry..."
        sleep 5
        
        # Second attempt for failed packages
        if brew bundle --verbose; then
            success "✓ Packages installed on retry"
        else
            warn "Some packages still failed - continuing with installation"
            log "You can manually retry failed packages later with: brew bundle"
        fi
    fi
}

# Setup symlinks
setup_symlinks() {
    log "Setting up configuration symlinks..."
    
    if [[ -x "$DOTFILES_DIR/scripts/install.sh" ]]; then
        "$DOTFILES_DIR/scripts/install.sh"
    else
        error "install.sh script not found or not executable"
        exit 1
    fi
    
    success "✓ Symlinks configured"
}

# Configure Node.js
setup_node() {
    log "Configuring Node.js..."
    
    # Link node@20 if not already linked
    if ! command -v node >/dev/null 2>&1; then
        log "Linking Node.js 20..."
        if brew link node@20 --force --overwrite; then
            success "✓ Node.js 20 linked"
        else
            warn "Failed to link Node.js 20 - it may already be linked"
        fi
    fi
    
    # Verify Node.js and npm versions
    local node_version=$(node --version 2>/dev/null || echo "not found")
    local npm_version=$(npm --version 2>/dev/null || echo "not found")
    log "Node.js version: $node_version"
    log "npm version: $npm_version"
    
    success "✓ Node.js configured"
}

# Setup GitHub CLI
setup_github() {
    log "Setting up GitHub CLI..."
    
    if command -v gh >/dev/null 2>&1; then
        if ! gh auth status >/dev/null 2>&1; then
            warn "GitHub CLI is installed but not authenticated"
            log "Run 'gh auth login' to authenticate with GitHub"
        else
            success "✓ GitHub CLI authenticated"
        fi
    else
        warn "GitHub CLI not found"
    fi
}

# Setup Claude CLI via npm
setup_claude() {
    log "Installing Claude CLI via npm..."
    
    if command -v npm >/dev/null 2>&1; then
        if npm install -g @anthropic-ai/claude-cli; then
            success "✓ Claude CLI installed successfully"
            log "Run 'claude auth login' to authenticate"
        else
            warn "Failed to install Claude CLI via npm"
            log "You can manually install with: npm install -g @anthropic-ai/claude-cli"
        fi
    else
        warn "npm not available - Claude CLI installation skipped"
        log "Ensure Node.js is properly installed and try: npm install -g @anthropic-ai/claude-cli"
    fi
}

# Verify fonts installation
verify_fonts() {
    log "Verifying font installations..."
    
    # Check if JetBrains Mono Nerd Font is installed
    if fc-list | grep -i "jetbrainsmono nerd font" >/dev/null 2>&1; then
        success "✓ JetBrains Mono Nerd Font installed"
    else
        warn "JetBrains Mono Nerd Font may not be properly installed"
        log "You may need to restart applications or run: fc-cache -f"
    fi
}

# Post-installation steps
post_install() {
    log "Post-installation setup..."
    
    # Reload shell to pick up new PATH
    log "Reloading shell environment..."
    
    log ""
    success "🎉 Bootstrap completed successfully!"
    log ""
    log "Next steps:"
    log "1. Restart your terminal or run: source ~/.zprofile"
    log "2. Authenticate CLI tools:"
    log "   - GitHub: gh auth login"
    log "   - Claude: claude auth login"
    log "3. Launch applications:"
    log "   - AeroSpace: open -a AeroSpace"
    log "   - SketchyBar: brew services start sketchybar"
    log "4. Configure applications as needed"
    log ""
    log "Optional: Run 'brew bundle --cleanup' to remove unused packages"
    log ""
}

# Main execution
main() {
    log "Starting dotfiles bootstrap from: $DOTFILES_DIR"
    log ""
    
    check_macos
    install_homebrew
    install_packages
    setup_symlinks
    setup_node
    setup_claude
    setup_github
    verify_fonts
    post_install
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi