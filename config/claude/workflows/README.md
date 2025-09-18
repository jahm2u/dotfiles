# Claude Workflows

## Meeting to Jira Workflow

Automatically extracts action items from your daily meeting notes and creates Jira tickets.

### Setup

1. **Install dependencies:**
   ```bash
   brew install jq khal curl
   ```

2. **Configure Jira credentials:**
   ```bash
   cd ~/.claude/workflows
   cp .meeting-jira-config.template .meeting-jira-config
   # Edit .meeting-jira-config with your Jira details
   ```

3. **Get your Jira API token:**
   - Go to https://id.atlassian.com/manage-profile/security/api-tokens
   - Create a new token
   - Add it to `.meeting-jira-config`

4. **Set up meeting notes directory:**
   - Create a directory for your meeting notes (default: `~/Documents/MeetingNotes`)
   - Name your notes files using one of these patterns:
     - `YYYY-MM-DD_Meeting-Title.md`
     - `YYYY-MM-DD-Meeting-Title.md`
     - `Meeting-Title_YYYY-MM-DD.md`
     - `Meeting-Title.md`

### Usage

#### Manual run:
```bash
~/.claude/workflows/meeting-to-jira.sh
```

#### Dry run (test without creating tickets):
```bash
~/.claude/workflows/meeting-to-jira.sh --dry-run
```

#### Automated daily run:
Add to your crontab:
```bash
crontab -e
# Add this line to run at 5 PM every weekday
0 17 * * 1-5 ~/.claude/workflows/meeting-to-jira.sh
```

Or use launchd (macOS):
```bash
# Create ~/Library/LaunchAgents/com.user.meeting-to-jira.plist
# See example below
```

### Meeting Notes Format

The workflow looks for action items in your meeting notes using these patterns:

```markdown
# Meeting Title

## Action Items
- [ ] ACTION: Update the documentation
- TODO: Review pull request #123
- TASK: Deploy to staging environment
- Fix the bug in login @john
- [ ] @sarah: Prepare presentation slides
```

### Features

- **Automatic detection**: Finds today's meetings from khal calendar
- **Smart parsing**: Extracts action items using multiple patterns
- **Duplicate prevention**: Tracks processed files to avoid duplicates
- **Ticket linking**: Optionally adds created ticket links back to notes
- **Logging**: Maintains detailed logs in `meeting-to-jira.log`

### Configuration Options

Edit `.meeting-jira-config` to customize:

- `JIRA_URL`: Your Atlassian instance URL
- `JIRA_PROJECT_KEY`: Default project for new tickets
- `JIRA_ISSUE_TYPE`: Type of issues to create (Task, Story, Bug, etc.)
- `MEETING_NOTES_DIR`: Where your meeting notes are stored
- `APPEND_TICKETS_TO_NOTES`: Add ticket links back to meeting notes

### Troubleshooting

1. **No meetings found:**
   - Check that khal is configured and synced
   - Verify calendar URLs in `~/.config/sketchybar/.env`
   - Run `khal list today today` to test

2. **Notes not found:**
   - Check file naming convention matches expected patterns
   - Verify `MEETING_NOTES_DIR` in config

3. **Tickets not created:**
   - Verify Jira credentials and API token
   - Check `meeting-to-jira.log` for errors
   - Test API access: `curl -u email:token https://your-company.atlassian.net/rest/api/2/myself`

### LaunchD Example

Create `~/Library/LaunchAgents/com.user.meeting-to-jira.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.meeting-to-jira</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/t/.claude/workflows/meeting-to-jira.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>17</integer>
        <key>Minute</key>
        <integer>0</integer>
        <key>Weekday</key>
        <integer>1</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/meeting-to-jira.out</string>
    <key>StandardErrorPath</key>
    <string>/tmp/meeting-to-jira.err</string>
</dict>
</plist>
```

Then load it:
```bash
launchctl load ~/Library/LaunchAgents/com.user.meeting-to-jira.plist
```