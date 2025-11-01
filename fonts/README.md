# Fonts Directory

This directory contains JetBrains Mono Nerd Font files required for Sketchybar icons and terminal applications.

## What's Included

Essential font weights for **JetBrains Mono Nerd Font (No Ligatures)**:
- Regular
- Medium
- Bold
- SemiBold
- Italic
- BoldItalic

**Total size:** ~14MB (6 font files)

## Auto-Installation

When running `scripts/install.sh`, the script will:

1. Check if JetBrains Mono Nerd Font is installed in `~/Library/Fonts/`
2. If missing, install from this directory (offline, instant)
3. If fonts not in repo, download from [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts) as fallback

**Benefits of including fonts in repo:**
- ✅ Offline installation (no internet required)
- ✅ Version controlled (exact font version)
- ✅ Fast installation (no download wait)
- ✅ Reliable (no external dependency)

## Manual Installation

To manually install fonts from this directory:

```bash
cp fonts/*.ttf ~/Library/Fonts/
```

## Why No Ligatures (NL) Version?

Sketchybar and status bars work better with the NL (No Ligatures) variant, which prevents character combinations from merging into single glyphs.

## Used By

- Sketchybar (status bar icons and text)
- Warp terminal
- VS Code
- Any terminal or editor configured to use JetBrains Mono

## Source

Downloaded from: https://github.com/ryanoasis/nerd-fonts/releases
