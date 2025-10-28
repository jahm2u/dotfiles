# Padding Configuration Documentation

This document describes the padding configuration variables that should be added to `.env.example`.

## Variables to Add to .env.example

Add the following section to `config/sketchybar/.env.example`:

```bash
# ============================================================================
# PADDING CONFIGURATION (Story 1.5)
# ============================================================================
#
# Sketchybar bar padding adjusts based on display mode (laptop vs external monitor).
# The load-env-config.sh script (Story 1.4) automatically detects your display mode
# and exports the appropriate PADDING value.
#
# How it works:
# 1. Script detects if you're using laptop screen or external monitor
# 2. Reads PADDING_LAPTOP or PADDING_EXTERNAL from this .env file
# 3. Exports PADDING variable with the appropriate value
# 4. Sketchybar variants consume $PADDING to set padding_left and padding_right
#
# Fallback behavior:
# - If .env is missing or variables unset, variants use sensible defaults
# - Laptop variants default to 23px
# - Desktop/external variants default to 10px
#
# ============================================================================

# Laptop mode padding (MacBook built-in display, with notch)
# Recommended range: 20-40px
# Default: 23px
PADDING_LAPTOP=23

# External monitor padding (desktop mode, no notch)
# Recommended range: 5-15px
# Default: 10px
PADDING_EXTERNAL=10

# Notch width configuration (laptop mode only)
# Controls the width of the notch area in pixels
# Recommended range: 200-250px
# Default: 230px
NOTCH_WIDTH=230

# ============================================================================
# END PADDING CONFIGURATION
# ============================================================================
```

## Implementation Details

### Modified Files
All Sketchybar variant files now use dynamic padding with fallbacks:

1. **sketchybarrc-laptop**
   - Uses: `PADDING=${PADDING:-23}`
   - Fallback: 23px (laptop mode default)

2. **sketchybarrc-desktop**
   - Uses: `PADDING=${PADDING:-10}`
   - Fallback: 10px (external mode default)

3. **sketchybarrc-laptop-privacy**
   - Uses: `PADDING=${PADDING:-23}`
   - Fallback: 23px (laptop mode default)

4. **sketchybarrc-desktop-privacy**
   - Uses: `PADDING=${PADDING:-10}`
   - Fallback: 10px (external mode default)

5. **sketchybarrc-laptop-minimal**
   - Uses: `PADDING=${PADDING:-23}`
   - Fallback: 23px (laptop mode default)

### Usage Pattern

```bash
# In all variant files:
NOTCH_WIDTH=${NOTCH_WIDTH:-230}
PADDING=${PADDING:-XX}  # XX = 23 for laptop, 10 for desktop

sketchybar --bar \
    padding_left=$PADDING \
    padding_right=$PADDING \
    notch_width=$NOTCH_WIDTH \
    ...
```

### Testing

All variants tested and verified:
- ✅ Dynamic $PADDING variable usage
- ✅ Correct fallback defaults (23px laptop, 10px desktop)
- ✅ Configurable NOTCH_WIDTH with 230px fallback
- ✅ Valid shell syntax (bash -n passed)

### Integration

This story integrates with:
- **Story 1.1**: Creates .env file structure
- **Story 1.3**: Provides display mode detection
- **Story 1.4**: Exports PADDING based on detected mode
- **Story 1.6**: Will integrate loader at startup
- **Story 1.7**: Will handle dynamic display mode changes

### Backward Compatibility

All variants remain backward compatible:
- Work without Story 1.4 loader (use fallback defaults)
- Work without .env file (use fallback defaults)
- Existing functionality unchanged (plugins, widgets, workspace indicators)

## Manual Testing Steps

To manually test padding configuration:

```bash
# Test 1: With custom padding
export PADDING=40
source ~/.config/sketchybar/sketchybarrc-laptop
# Verify: Bar should have 40px padding on both sides

# Test 2: With fallback (unset PADDING)
unset PADDING
source ~/.config/sketchybar/sketchybarrc-laptop
# Verify: Bar should use 23px default padding

# Test 3: With Story 1.4 loader
bash ~/.config/sketchybar/helpers/load-env-config.sh
# Verify: PADDING exported based on display mode
echo $PADDING
source ~/.config/sketchybar/sketchybarrc-laptop

# Test 4: Custom notch width
export NOTCH_WIDTH=250
source ~/.config/sketchybar/sketchybarrc-laptop
# Verify: Notch area is 250px wide

# Test 5: Restart Sketchybar to see changes
brew services restart sketchybar
```

## Notes for .env.example Maintenance

When updating .env.example, ensure:
1. All three variables documented (PADDING_LAPTOP, PADDING_EXTERNAL, NOTCH_WIDTH)
2. Clear explanations of how load-env-config.sh (Story 1.4) uses them
3. Sensible example values provided
4. Recommended ranges documented
5. Fallback behavior explained
6. Cross-references to related stories (1.1, 1.3, 1.4, 1.6, 1.7)
