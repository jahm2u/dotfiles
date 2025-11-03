# Krisp Authentication Setup Guide

This guide explains how to set up authentication for the Krisp transcript downloader.

## Overview

The `krisp-download-transcripts.py` script uses **browser cookies + localStorage** for authentication with Krisp.ai. This requires a one-time manual export of your authenticated browser session.

## Prerequisites

- Active Krisp.ai account
- Browser with Cookie Editor extension (recommended: Chrome or Firefox)
- Access to macOS Terminal

## Setup Steps

### Step 1: Install Cookie Editor Browser Extension

**Chrome:**
1. Install [Cookie-Editor](https://chrome.google.com/webstore/detail/cookie-editor/hlkenndednhfkekhgcdicdfddnkalmdm)

**Firefox:**
1. Install [Cookie-Editor](https://addons.mozilla.org/en-US/firefox/addon/cookie-editor/)

### Step 2: Log into Krisp.ai

1. Open your browser
2. Navigate to https://app.krisp.ai/
3. Log in with your Krisp account
4. Verify you can see the meetings dashboard at https://app.krisp.ai/meeting-notes

### Step 3: Export Cookies

1. While on `https://app.krisp.ai/meeting-notes`, click the Cookie-Editor extension icon
2. Click "Export" button
3. Click "Export as JSON" (this copies to clipboard)
4. Save the JSON to a temporary file

### Step 4: Export localStorage

1. Open Browser Dev Tools (F12 or Cmd+Option+I on Mac)
2. Go to "Application" tab (Chrome) or "Storage" tab (Firefox)
3. Click "Local Storage" → "https://app.krisp.ai"
4. Right-click in the table → "Copy All" or manually copy each key-value pair
5. Format as JSON object:

```json
{
  "key1": "value1",
  "key2": "value2",
  ...
}
```

### Step 5: Create Auth File

Create the auth file at: `~/.config/sketchybar/krisp-auth.json`

```json
{
  "cookies": [
    /* Paste cookie JSON array here */
  ],
  "localStorage": {
    /* Paste localStorage JSON object here */
  },
  "updated_at": "2025-11-02T10:30:00"
}
```

**Example structure:**

```json
{
  "cookies": [
    {
      "name": "__Secure-next-auth.session-token",
      "value": "eyJhb...",
      "domain": ".krisp.ai",
      "path": "/",
      "expires": 1735689600,
      "httpOnly": true,
      "secure": true,
      "sameSite": "Lax"
    }
  ],
  "localStorage": {
    "theme": "light",
    "userId": "user_abc123",
    "sessionData": "{...}"
  },
  "updated_at": "2025-11-02T10:30:00"
}
```

### Step 6: Test Authentication

Run the auth test:

```bash
source ~/.config/sketchybar/venv/bin/activate
python3 ~/.config/sketchybar/helpers/krisp-download-transcripts.py --test-auth
```

**Expected output:**
```
[2025-11-02 10:30:00] [INFO] Testing Krisp authentication...
[2025-11-02 10:30:00] [INFO] Loaded auth from file (updated: 2025-11-02T10:30:00)
[2025-11-02 10:30:00] [INFO] Loaded 5 cookies
[2025-11-02 10:30:00] [INFO] Navigating to Krisp domain to set localStorage...
[2025-11-02 10:30:00] [INFO] Injecting localStorage items...
[2025-11-02 10:30:00] [INFO] Navigating to meeting-notes page...
[2025-11-02 10:30:00] [INFO] Page URL: https://app.krisp.ai/meeting-notes
[2025-11-02 10:30:00] [INFO] Page title: Meeting Notes - Krisp
[2025-11-02 10:30:00] [INFO] ✓ Authentication successful
```

### Step 7: Configure Telegram Alerts (Optional)

For auth failure notifications, add to your `.env` file:

```bash
# Telegram Bot Configuration
TELEGRAM_BOT_TOKEN="123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
TELEGRAM_CHAT_ID="123456789"
```

**How to get these values:**

1. **Bot Token:**
   - Message @BotFather on Telegram
   - Send `/newbot` and follow prompts
   - Save the token provided

2. **Chat ID:**
   - Message @userinfobot on Telegram
   - It will reply with your chat ID

## Maintenance

### Cookie Expiration

Krisp cookies typically expire after 30 days. When authentication fails:

1. You'll receive a Telegram alert (if configured)
2. Check logs: `tail -50 ~/.config/sketchybar/logs/krisp-download.log`
3. Re-export cookies following Step 3-5 above
4. Test with `--test-auth` flag

### Manual Refresh Script (Future Enhancement)

For easier cookie refresh, a helper script `krisp-refresh-auth.sh` can be created to automate parts of this process.

## Troubleshooting

### Auth test fails immediately

**Error:** `Auth file not found: /Users/v/.config/sketchybar/krisp-auth.json`

**Solution:** Complete Steps 3-5 to create the auth file.

### Auth test shows "redirected to login page"

**Error:** `Authentication failed - redirected to login page`

**Solution:** Cookies have expired. Re-export following Steps 3-5.

### Telegram alerts not sending

**Check:**
```bash
env | grep TELEGRAM
```

**Expected:**
```
TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
TELEGRAM_CHAT_ID=123456789
```

**Solution:** Add tokens to `.env` file (Step 7).

### Downloads failing silently

**Check logs:**
```bash
tail -f ~/.config/sketchybar/logs/krisp-download.log
```

Common issues:
- Auth failure (re-export cookies)
- Network timeout (check internet connection)
- Krisp UI changes (selectors may need updating)

## Security Notes

- **Never commit** `krisp-auth.json` to version control
- Store in `~/.config/sketchybar/` (not synced to git)
- Rotate cookies regularly (every 30 days recommended)
- Telegram bot tokens should be in `.env` (git-ignored)

## Next Steps

After authentication is working:

1. Download new transcripts:
   ```bash
   python3 krisp-download-transcripts.py --download-new --limit 5
   ```

2. Check transcript directory:
   ```bash
   ls -la ~/.config/sketchybar/krisp-transcripts/
   ```

3. View cache:
   ```bash
   cat ~/.cache/sketchybar/processed-krisp-meetings.json | jq
   ```

For more details, see:
- Story 4-2: Browser Automation & Transcript Download
- Story 4-3: Calendar Matching & Obsidian Integration (coming next)
