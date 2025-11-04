# Krisp Automation Daemon Setup

## Problem
The Krisp automation wasn't sending Telegram notifications because:
1. No LaunchAgent existed for hourly automation
2. Telegram credentials weren't configured

## Solution
Created hourly daemon with health beat notifications at start/end.

---

## Setup Steps

### 1. Get Telegram Bot Credentials

**Create a bot:**
1. Open Telegram and message [@BotFather](https://t.me/botfather)
2. Send `/newbot`
3. Follow prompts to name your bot (e.g., "Krisp Automation Bot")
4. Copy the **bot token** (looks like `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`)

**Get your chat ID:**
1. Message [@userinfobot](https://t.me/userinfobot)
2. Copy your **chat ID** (looks like `123456789`)

### 2. Add Credentials to .env

Edit `~/repos/02_personal/dotfiles/.env` and add:

```bash
# Telegram notifications for Krisp daemon
TELEGRAM_BOT_TOKEN="your-bot-token-here"
TELEGRAM_CHAT_ID="your-chat-id-here"
```

### 3. Install LaunchAgent

```bash
# Copy LaunchAgent to system location
cp ~/repos/02_personal/dotfiles/Library/LaunchAgents/com.user.krisp-automation.plist \
   ~/Library/LaunchAgents/

# Load and start the daemon
launchctl load -w ~/Library/LaunchAgents/com.user.krisp-automation.plist

# Verify it's running
launchctl list | grep krisp-automation
```

### 4. Test Immediately (Don't Wait for Hourly)

```bash
# Trigger a manual run to test Telegram notifications
bash ~/.config/sketchybar/helpers/krisp-hourly-daemon.sh
```

You should receive 2 Telegram messages:
1. **Start:** "🤖 Krisp Daemon Started - Checking for new transcripts..."
2. **End:** "✅ Krisp Daemon Complete - Downloaded X transcripts..."

---

## How It Works

**Hourly Schedule:**
- LaunchAgent runs every hour automatically
- Discovers new meetings (scans last 5 pages ~100 meetings)
- Downloads up to 10 transcripts per hour
- Sends health beat notifications

**Health Beat Messages:**

**Start message:**
```
🤖 Krisp Daemon Started
Time: 03:15 PM
Status: Checking for new transcripts...
```

**End message:**
```
✅ Krisp Daemon Complete
Discovered: 5 new meetings
Downloaded: 3 transcripts
Failed: 0
Still Pending: 2
Duration: 45s
Next run: In 1 hour
```

---

## Monitoring

**View daemon logs:**
```bash
tail -f ~/.config/sketchybar/logs/krisp-daemon.log
```

**Check LaunchAgent status:**
```bash
launchctl list | grep krisp-automation
```

**View stdout/stderr:**
```bash
tail -f ~/.config/sketchybar/logs/krisp-daemon-stdout.log
tail -f ~/.config/sketchybar/logs/krisp-daemon-stderr.log
```

---

## Troubleshooting

**No Telegram notifications:**
1. Check credentials in `.env`
2. Test bot: `curl -X POST "https://api.telegram.org/bot<YOUR_TOKEN>/getMe"`
3. Check logs for "Telegram credentials not configured"

**LaunchAgent not running:**
```bash
# Unload if needed
launchctl unload ~/Library/LaunchAgents/com.user.krisp-automation.plist

# Reload
launchctl load -w ~/Library/LaunchAgents/com.user.krisp-automation.plist
```

**Auth expiration:**
If downloads start failing after a few weeks:
```bash
bash ~/.config/sketchybar/helpers/krisp-refresh-auth.sh
```

---

## Customization

**Change frequency** (edit plist):
```xml
<key>StartInterval</key>
<integer>1800</integer> <!-- 30 minutes -->
```

**Download limit per run** (edit daemon script):
```bash
--limit 10  # Change to 20, 50, etc.
```

**Discovery depth** (edit daemon script):
```bash
--max-pages 5  # Change to 10, 20 for deeper scans
```

---

## Production Ready
- ✅ Hourly automation
- ✅ Health beat notifications
- ✅ Error handling and alerts
- ✅ Progress tracking (resumes after interruption)
- ✅ Rate limiting (10 transcripts/hour)
- ✅ Comprehensive logging
