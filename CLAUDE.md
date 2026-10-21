# Claude Code Context for Dotfiles Repository

This document provides essential context for Claude Code instances working with this dotfiles repository.

## Repository Overview

This is a comprehensive macOS dotfiles management system containing configurations for productivity tools, window managers, and development utilities. All configurations are managed via symlinks created by the installation script.

## Installation Script Architecture

The installation script (`scripts/install.sh`) uses a **four-phase declarative architecture** designed for minimal user interruption and maximum clarity.

### Core Principles & Phases

**Principles:** Separation of concerns | Upfront questions | Smart defaults | Clean progress | Idempotent

1. **System State Detection**: Silent scan - detects Homebrew, khal, sketchybar, aerospace, .env, LaunchAgents, symlinks (~1 sec)
2. **Configuration Gathering**: Batches ALL questions upfront - dependencies, env variables, features
3. **Plan Generation**: Builds structured plan, displays summary, single approval gate
4. **Execution**: Clean progress `[1/6] Action... ✓`, logs to `~/.config/dotfiles-install.log`
5. **Summary Report**: Final counts, next steps, log location

### Command-Line Flags
```bash
./scripts/install.sh            # Standard installation (recommended)
./scripts/install.sh --verbose  # Show detailed output during execution
./scripts/install.sh --dry-run  # Preview without executing
./scripts/install.sh --help     # Show usage information
```

### Key Features
- **Smart defaults**: Skips redundant questions if .env already configured
- **Idempotent**: Safe to run multiple times
- **Graceful degradation**: Non-critical failures don't stop installation
- **Automatic backups**: Timestamped backups before changes
- **Python venv setup**: Auto-creates venv for meeting-prep automation
- **Cache clearing**: Clears stale caches for fresh sync on new machines

## Core Tools & Configurations

### 1. AeroSpace (Tiling Window Manager)
- **Config**: `config/aerospace/aerospace.toml`
- **Key Bindings**: Uses Ctrl+Alt+Shift for most commands, adds Cmd as modifier for some actions
- **Workspace Layout**: Spatial navigation with arrows
- **Important**: User has custom Hyper key bindings that must not conflict:
  - Hyper+W = Screenshot
  - Hyper+S = Translation
  - Hyper+Space = Raycast

### 2. Karabiner-Elements (Keyboard Remapping)
- **Config**: `config/karabiner/karabiner.json`
- **Primary Function**: Map Caps Lock to Hyper key
- **Device-specific**: Contains rules for external keyboard (vendor_id: 12136)

### 3. Sketchybar (Status Bar)
- **Config**: `config/sketchybar/`
- **Integration**: Updates workspace indicators via AeroSpace hooks
- **Path References**: Uses hardcoded paths to user home directory

### 4. Hammerspoon (Automation)
- **Config**: `config/hammerspoon/`
- **Symlink**: Goes to `~/.hammerspoon` (not ~/.config/)
- **Audio Switching**: Two-phase device/volume picker with visual preview (see Audio Architecture below)
- **Reload**: `open -g hammerspoon://reload` or auto-reloads on `init.lua` save

### 5. Claude AI Assistant
- **Config**: `config/claude/`
- **Hooks**: Custom notification and audio scripts
- **Settings**: Contains tool hooks for PreToolUse notifications

### 6. Other Configurations
- **Raycast**: `config/raycast/`
- **Obsidian**: `config/obsidian/` (syncs to iCloud)

## Automation Architecture

All automation features follow this standard pattern:

**Data Flow Pattern:**
```
.env → LaunchAgent (interval) → main script →
components → cache/API → event trigger → widget update
```

### Automation Components Summary

| Automation | Interval | Main Script | Purpose | Key Files |
|------------|----------|-------------|---------|-----------|
| **Calendar** | 15 min | `sync-calendars.sh` | Sync iCal → khal → meeting widget | `meeting.sh`, LaunchAgent: `calendar-sync` |
| **Todoist** | 30 sec | `todoist-precache.sh` | Precache tasks → instant popup | `todoist_popup.sh`, `todoist.sh`, LaunchAgent: `todoist-precache` |
| **Meeting Prep** | On-click | `meeting-prep.sh` | AI-powered meeting note generation | `classify-meeting.py`, `analyze-meeting-history.py`, `generate-meeting-note.py` |
| **TM Snapshot Cleanup** | 1 hour | `cleanup-tm-snapshots.sh` | Thin Time Machine local snapshots; "Disk low" notification under 40 GB | LaunchAgent: `tm-snapshot-cleanup`, log `tm-cleanup.log` |

### Component Details

#### Calendar Automation
- **Components**: `sync-calendars.sh` (60s timeout, curl → khal import) | `meeting.sh` (widget with countdown)
- **Config**: `.env`: `ICAL_URLS="https://url1,https://url2"` | History: `CALENDAR_HISTORY_DAYS=7`
- **Events**: `calendar_synced` triggered on success | Widget subscribes for reactive updates
- **Manual**: `bash ~/.config/sketchybar/helpers/sync-calendars.sh`

#### Todoist Automation
- **Components**: `todoist-precache.sh` (30s interval, API fetch) | `todoist_popup.sh` (instant cache read) | `todoist.sh` (focus widget)
- **Config**: `.env`: `TODOIST_API_TOKEN="token"` | Cache: `~/.cache/sketchybar/todoist_tasks_cache`
- **Events**: `todoist_focus_changed` when task clicked | Widget updates reactively
- **Performance**: <100ms popup open, <1s sync

#### Meeting Prep Automation (Jonas API)
- **Workflow**: Icon click → POST to Jonas API (`/prep`) → wait for note file on disk → ensure Obsidian running → open note via URI
- **API**: `https://jonas.ilovejeff.co/prep` — returns `note_path` (Docker path) and `obsidian_uri`
- **File sync**: Docker creates note at `/vault/...` which maps to host vault at `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/kb/`
- **URI construction**: Script builds URI from `note_path` (preferred) or `obsidian_uri` `file=` param, always using `vault=kb`
- **Safeguards**: Polls for file existence (0.5s intervals, 10s max), launches Obsidian if not running, exits with error if file never appears
- **Config**: `.env`: `JONAS_API_URL` (optional, defaults to production)
- **Performance**: 7-90s total (API call dominates)

### LaunchAgent Operations

**Service Names:** `calendar-sync` | `todoist-precache` | `tm-snapshot-cleanup`

**Disk filling up:** run `/disk-cleanup` (skill in `config/claude/skills/disk-cleanup/`). Its
`scan.sh` triages every git worktree under `~/repos` and `~/work` as SAFE / ASK / KEEP (merged
PR at HEAD, uncommitted work, unpushed commits, live processes) and lists regenerable caches;
`remove.sh` removes only what you approve. Time Machine local snapshots pin every deleted file
for up to a day (87 GB on 2026-10-17). They can't be disabled while Time Machine is on, so the
hourly agent thins them whenever the external backup is under 24 h old. Its old trigger watched
`/var/db/.TimeMachine.Results.plist`, which macOS 26 no longer writes, so it never ran.

**Loading agents from Claude Code:** Claude's shell can run in launchd's *Background* session
(`launchctl managername`), where `launchctl load` lands outside your login session and
`bootstrap gui/$UID` fails with error 125. Load agents from Terminal.app instead, or log in again.

```bash
# Check status (replace {SERVICE} with service name)
launchctl list | grep {SERVICE}

# Reload service
launchctl unload ~/Library/LaunchAgents/com.user.{SERVICE}.plist
launchctl load -w ~/Library/LaunchAgents/com.user.{SERVICE}.plist

# View logs
tail -f ~/.config/sketchybar/logs/{SERVICE}.log
tail -f ~/.config/sketchybar/logs/{SERVICE}-stdout.log
tail -f ~/.config/sketchybar/logs/{SERVICE}-stderr.log

# Trigger manually
launchctl start com.user.{SERVICE}
```

## macOS LaunchAgent Best Practices

**Critical PATH Configuration:**

LaunchAgents run with a minimal environment that does NOT include Homebrew paths. If your LaunchAgent calls Homebrew-installed tools (like khal, jq, etc.), you MUST configure the PATH explicitly.

**Required EnvironmentVariables in plist:**

```xml
<key>EnvironmentVariables</key>
<dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
</dict>
```

**Why This Matters:**
- Without explicit PATH, commands like `khal` will fail with "command not found" (exit code 127)
- LaunchAgent runs silently in background - failures may go unnoticed
- This was discovered as a critical bug during Story 2.7 E2E testing

**LaunchAgent Template Pattern:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.your-service-name</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/full/path/to/script.sh</string>
    </array>

    <key>StartInterval</key>
    <integer>900</integer> <!-- 15 minutes -->

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>

    <key>StandardOutPath</key>
    <string>/path/to/logs/service-stdout.log</string>

    <key>StandardErrorPath</key>
    <string>/path/to/logs/service-stderr.log</string>

    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```

**Testing LaunchAgents:**

```bash
# Always test with launchctl before assuming it works
launchctl load -w ~/Library/LaunchAgents/com.user.your-service.plist

# Check if running
launchctl list | grep your-service

# Check logs immediately
tail -f /path/to/logs/service-stderr.log
```

## Installation & Management

### Quick Setup
```bash
git clone https://github.com/jahm2u/dotfiles.git ~/dotfiles && cd ~/dotfiles && ./scripts/install.sh
```

### Symlink Structure
The `scripts/install.sh` script creates these symlinks:
- `~/dotfiles/config/aerospace/aerospace.toml` → `~/.config/aerospace/aerospace.toml`
- `~/dotfiles/config/sketchybar` → `~/.config/sketchybar`
- `~/dotfiles/config/karabiner` → `~/.config/karabiner`
- `~/dotfiles/config/hammerspoon` → `~/.hammerspoon`
- `~/dotfiles/config/raycast` → `~/.config/raycast`
- `~/dotfiles/config/obsidian` → `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/T/.obsidian`
- `~/dotfiles/config/khal` → `~/.config/khal`

### Environment Variables

**Required Environment Variables (.env file at repository root):**

```bash
# Obsidian Integration (required for meeting prep)
OBSIDIAN_VAULT_PATH="/Users/username/Library/Mobile Documents/iCloud~md~obsidian/Documents/VaultName"

# OpenAI API (required for AI features: meeting prep)
OPENAI_API_KEY="sk-proj-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Calendar Sync (required for calendar widget)
ICAL_URLS="https://calendar-url-1.ics,https://calendar-url-2.ics"

# Todoist Integration (required for task widget)
TODOIST_API_TOKEN="your-todoist-api-token-here"
```

**Setup:** `cp ~/dotfiles/.env.example ~/dotfiles/.env` then edit with your values

**Getting API Keys:**
- **OpenAI**: https://platform.openai.com/api-keys
- **Todoist**: Settings → Integrations → API token
- **Calendar URLs**: Google Calendar → Settings → Secret iCal address | iCloud → Right-click → Share → Public Calendar
- **Telegram**: @BotFather → /newbot | @userinfobot for Chat ID

### OpenAI API Convention

**Every OpenAI API call in this repo MUST pass a `safety_identifier`.** This is a stable, non-PII string that lets OpenAI attribute and rate-limit abuse per-feature instead of blocking the whole account (the shared `OPENAI_API_KEY` is used by 5 call sites). Use `safety_identifier="dotfiles-translate"` for the translation feature and `safety_identifier="dotfiles-meeting-prep"` for meeting-prep scripts. Add the same identifier to any new call site.

- **Python SDK** (`client.chat.completions.create(...)`): pass `safety_identifier="dotfiles-meeting-prep"` as a kwarg.
- **Raw HTTP** (Lua `hs.http.asyncPost` / shell `curl`): add `"safety_identifier": "..."` to the JSON body.

**Current call sites** (all set the identifier):
- Translation: `config/hammerspoon/init.lua` (`translateText`, `gpt-4.1-nano`) → `dotfiles-translate`
- `config/sketchybar/helpers/analyze-meeting-history.py` → `dotfiles-meeting-prep`
- `config/sketchybar/helpers/generate-meeting-note.py` → `dotfiles-meeting-prep`
- `config/sketchybar/helpers/identify-participant-from-transcript.py` → `dotfiles-meeting-prep`
- `config/sketchybar/helpers/generate-meeting-message.sh` (curl) → `dotfiles-meeting-prep`

**Key rotation:** `OPENAI_API_KEY` lives only in `~/dotfiles/.env` (gitignored, unquoted). All 5 call sites resolve to it — Python scripts load it via `load_dotenv` (`~/dotfiles/.env` first), `init.lua` reads it at `init.lua:33`. Rotate by editing that one line, then `open -g hammerspoon://reload`. Requires: `safety_identifier` needs `openai` SDK ≥ ~1.55 (repo venv has 2.6.1).

### Translation Shortcut & Log

**Shortcut:** `Ctrl+Alt+D` or `Alt+D` — copies the selection, translates EN↔PT, pastes over it.
Implemented in `config/hammerspoon/init.lua` (`translateText`, `replaceWithTranslatedText`).

**Prompt rules exist for a reason — do not "simplify" them.** They come from direct
team feedback that machine-translated tech writing was unreadable in pt-br:

1. **Technical vocabulary stays in English.** Our docs, tooling, error messages and
   library references are all English, and most tech terms have no real pt-br
   equivalent. Translating them forces the reader to translate back in their head.
   Real failures that motivated this: `skill` → `habilidade` (it means an AI skill),
   `the split control` → `o control do split` was rendered `o braço de controle`.
2. **Translate meaning, not words.** Literal idioms produce nonsense —
   `both bite when tested` → `as duas mordem quando um teste`.
3. **Rule 1 is narrow.** The first version of Rule 1 said "when unsure, keep it in
   English", and the log (Sep 2026) showed the model applying that to every word:
   `sua conta é um paid account? a subscription está active?`, `os men open como
   reaction from a view`. The prompt now carries an explicit list of ordinary words
   that must be translated (response, message, users, changes, access...) and a
   test: would a Brazilian dev say the English word in a stand-up? Verbs are always
   conjugated in Portuguese (`fazer o merge`, never `está paying`).
4. **The direction is decided in Lua, not by the model.** `detectTranslationTarget`
   counts stopwords that exist in only one language and the prompt then states the
   source and target explicitly. Left to itself, nano judged a Portuguese message
   dense with English jargon (skill, AWS, ArgoCD, deploy...) to be "already in
   English" and returned it unchanged, one run in three. The chosen target is
   recorded in each log line as `target` (`auto` when the detector abstained).
5. **Genuinely mixed input is left to the model.** When both languages are
   substantially present (minority ≥ 3 stopwords and majority < 4× minority) the
   detector abstains and the prompt's mixed-input rule applies: majority language
   is the source, parts already in the target language are copied through.
   Known limitation: nano still garbles this case about half the time. It is rare
   (2 of 166 logged, both caused by retrying a half-translated output, which the
   narrow Rule 1 now prevents). Translate the quote and the reply separately.

The text is sent between `<text>` tags rather than in quotes — quoting made the
model echo quotes back, and the Lua side also strips stray quotes and tags.
API keys (`sk-...`) are redacted before the line is written to the log.

**Translation log:** `~/.config/sketchybar/logs/translations.log`

One JSON object per line: `{ts, model, input, output}`. Written by `logTranslation()`
on every successful translation. Gitignored via `config/sketchybar/logs/` — it contains
raw message text (including client and personal messages) and must never be committed.

**Review it periodically to improve the prompt.** The point of this log is that the
term list in Rule 1 should grow from real data, not guesses. To find English terms
that got translated when they should have been preserved:

```bash
scripts/review-translations.py              # terms that leaked (were translated)
scripts/review-translations.py --term skill # inspect the cases for one term
scripts/review-translations.py --list       # recent translations, both sides
```

The report has two sections. The first lists jargon present in `input` but absent
from `output` — those words got translated and belong in the RULE 1 list in
`init.lua`. The second lists plain English words (from `PLAIN_WORDS`) that survived
into Portuguese output — those are over-Englishing and belong in the "RULE 1 is
narrow" examples. Add them, then `open -g hammerspoon://reload`. Keep `TERMS` and
`PLAIN_WORDS` in the script in sync with the prompt. A term can also go missing
because the sentence was legitimately restructured, so check `--term <word>` before
adding.

To judge a prompt change on real output instead of by eye, replay failed log cases
through the API with `scripts/replay-translations.py`. It extracts the prompt from
`init.lua` itself (`--old` adds the git HEAD version, `--model` adds models) and
runs the real `detectTranslationTarget` through `hs -c`, so Hammerspoon must be
running with the current config. A replay of 10 cases costs well under a cent.
Run a flaky case three times: nano is nondeterministic even at temperature 0.2,
and a single green run proved nothing for the PT→EN passthrough bug.

**Model:** `TRANSLATE_MODEL` in `init.lua` (currently `gpt-4.1-nano`). In the Sep 2026
replay `gpt-4.1-mini` wrote slightly more natural Portuguese but kept translating
mixed-language input in both directions, so nano stayed. Recorded in each
log line so outputs stay attributable after a model change. If quality is still poor
after prompt tuning, the model is a bigger lever than the prompt.

**Open question (raised by Estrella, Sep 2026):** the team may standardize on English
for all tech writing, which would make the EN→PT direction unnecessary — the shortcut
would become PT→EN only. Pending a dev-headquarter discussion.

### Python Virtual Environment

**Location:** `~/.config/sketchybar/venv`

**Dependencies:** `openai==2.6.1`, `python-dotenv==1.0.0`, `pyyaml==6.0.1`, `requests`, `python-dateutil`

```bash
# Verify dependencies
~/.config/sketchybar/venv/bin/pip list

# All scripts use absolute path
~/.config/sketchybar/venv/bin/python3 script.py
```

## Critical Context & Known Issues

### 1. Hyper Key Configuration
- **Definition**: Hyper = Cmd+Alt+Ctrl+Shift (all modifiers)
- **Important**: Cannot combine Hyper with any other modifier (e.g., "Hyper+Cmd" is impossible)
- **User's Custom Bindings**: Must preserve existing Hyper key uses

### 2. AeroSpace Window Management
- **Default Modifier**: Alt (Option) key
- **Conflict**: Alt+Shift+2 produces € symbol (user needs this)
- **Solution**: Spatial navigation with arrows instead of numbers

### 3. Claude Hooks System
- **Location**: `config/claude/hooks/`
- **macOS Notifications**: Use simple `display notification` (no System Events)
- **Audio Notifications**: Play sound files for different events
- **Settings**: Configured in `config/claude/settings.json`

### 4. Path Configuration
- Most configs use relative paths or environment variables
- Sketchybar may contain some hardcoded home directory references
- Use `~` or `$HOME` variables when possible for portability

## User Preferences & Workflows

### Window Management Philosophy
- Prefers spatial navigation (arrows) over numbered workspaces
- Uses mode-based commands to reduce modifier complexity
- Values mnemonic shortcuts (M=Move, F=Fling, Z=siZe)

### Workspace Layout
- Workspace 1: Secondary monitor (left)
- Workspaces 2-7: Main monitor
- Mental model: Left arrow = secondary, other arrows = main

### Key Binding Patterns
- Ctrl + Alt + Shift + Arrows: Window focus
- Ctrl + Alt + Shift + Numbers: Workspace navigation
- Cmd + Ctrl + Alt + Shift + Arrows: Window movement
- Cmd + Ctrl + Alt + Shift + Numbers: Move to workspace

## Audio Architecture (Hammerspoon)

### Overview
Dual LG UltraFine display audio management with visual preview picker, volume control, and automatic mic pinning. Managed in `config/hammerspoon/init.lua`.

### Hardware Setup
- **LG Left**: Secondary monitor (physically left)
- **LG Right**: Main monitor (physically right) — mic always pinned here
- **LG Dual**: Aggregate device playing through both monitors simultaneously
- **Mac mini Speakers**: Built-in fallback

### Device Identification
Two identical "LG UltraFine Display Audio" devices are distinguished by UID serial numbers. The main (current default) output at init time is labeled "LG Left" (physically left). The `SwitchAudioSource` CLI (`/opt/homebrew/bin/SwitchAudioSource`) is used for reliable device switching between identical-model displays.

### Key Bindings
- **Ctrl+Option+Cmd+]**: Next device / increase volume
- **Ctrl+Option+Cmd+[**: Previous device / decrease volume
- **System volume keys**: Intercepted when on LG Dual (aggregate devices block native volume control)

### Two-Phase Interaction
1. **Device mode** (default): `]`/`[` browse devices with visual overlay (`▶` = selection, `●` = current active). Auto-applies after 2 seconds of no input.
2. **Volume mode** (after device applies): Same keys cycle volume levels (0%, 25%, 50%, 75%, 100%) with overlay. Auto-applies after 2 seconds. Resets to device mode after 8 seconds of inactivity.

### System Volume Key Interception
When on LG Dual, native macOS volume keys are disabled (aggregate device limitation). Hammerspoon intercepts `SOUND_UP`, `SOUND_DOWN`, and `MUTE` system key events and applies volume changes to both LG sub-devices in sync (~6.25% per step).

### Key Behaviors
- **Volume matching**: When switching devices, volume is copied from current device to target to prevent blaring
- **Volume set before AND after switch**: LG displays may ignore volume changes when not the active output (firmware-controlled)
- **Mic pinning**: Input mic always stays on LG Right (main monitor) regardless of output selection
- **System alert sounds**: Follow the active output device via `setDefaultSystemDevice()`
- **Multi-Output recreation**: If the LG Dual aggregate device is destroyed by a display change, `scripts/create-multi-output.swift` auto-recreates it

### Display Change Handling
Single debounced screen watcher (3-second delay) handles monitor plug/unplug:
1. Rebuilds audio device list (includes Multi-Output recreation if needed)
2. Re-detects current output device
3. Pins mic to right monitor
4. Restarts sketchybar

### Device Filtering
The following devices are excluded from the picker: Microsoft Teams Audio, Jump Desktop Audio, krisp speaker, and any Multi-Output/Aggregate/LG Dual system devices (the manual "LG Dual" entry is constructed separately).

## Machines, Tailscale & herdr

### Machines (one tailnet: `jeff.hamersly@gmail.com`, `*.taild9b9f0.ts.net`)

| Tailscale name | What it is |
|----------------|------------|
| `mini-2024` | This Mac mini (desk machine, wired Ethernet). Runs the herdr *client* |
| `ts-macbook-pro` | MacBook Pro (`ssh mbp`). Hosts the herdr sessions below |
| `mini-mp`, `mox` | Other Mac mini / Linux box (`mox` = staging) |
| `claude-gateway` | Linux box on the LAN (192.168.0.224), `tag:claude-gw` |
| `db-gateway` | Linux DB gateway |

Everything is in one tailnet. There are no separate org tailnets: "mbp orgs", "dev hive"
and "mkt crew" are **herdr sessions**, not Tailscale devices. On the mini, Tailscale is
the Homebrew `tailscaled` running as root (state in `/Library/Tailscale`, log
`/opt/homebrew/var/log/tailscaled.log`), not the App Store app.

### herdr remote sessions

herdr (0.9.3, must match on both Macs) on the mini lists three saved SSH machines in its
**machines** sidebar. All three go through ssh host `mbp` (`~/.ssh/config`: HostName
`ts-macbook-pro`, user `v`, port 22, i.e. over Tailscale):

| Sidebar label | herdr session on the MBP | Repo on the MBP (live checkout) | Brought up by |
|---------------|--------------------------|----------------------------------|---------------|
| mbp orgs | `orgs` | `~/repos/01_business/tp/baba-brain` (+ `repos/baba-fleet`) | `org-seat/scripts/up.sh`, LaunchAgent `com.babafleet.orgs-keeper` (every 60 s) |
| dev hive | `dev-crew` | `~/repos/01_business/mp/hive-dev-crew` (`github.com/jeffheartmp/hive-dev-crew`) | `bin/crew up --window`, LaunchAgent `com.jeffheartmp.dev-crew.login` (at login) |
| mkt crew | `mkt-crew` | `~/repos/01_business/mp/hive-paid-traffic` (`github.com/jeffheartmp/hive-paid-traffic`) | `bin/hive up --janela`, LaunchAgent `com.ipmedia.hive-paid-traffic.login` (at login) |

What each crew is:

- **orgs** (TP business, workspace "Baba"): `seat` is Jeff's single point of contact, `baba` the
  chief of staff, `tp` `pd` `ex` `mt` `oh` each babysit one partner's Telegram channel from a
  BabaFlow liaison checkout, `gardener` tends the brain, and workspace "builders" holds
  `b-<slug>` cmux-style builders.
- **dev-crew** (MeuPatrocínio): Jeff's dev-leadership crew. It watches how the dev team works,
  keeps the record, and prepares 1:1s, reviews, incidents, RFCs and hiring. Fixed seats
  `observer`, `chief-of-staff`, `tech-lead`, `shepherd`, plus bench seats (`qa-lead`,
  `crew-dev`...) leased by order (`crew.toml [layout]`, `[bench]`). Holds 1:1 notes and DMs,
  so the repo is private. About 35 `com.jeffheartmp.dev-crew.*` launchd jobs (memory
  reviews, reports, watchdog, nightly housekeeping), generated from `crew.toml` by
  `bin/crew install-schedule`.
- **mkt-crew** (MeuPatrocínio paid traffic, Meta ads): seven *seats* (pm, strategist,
  operator, web-dev, web-design, finance, martech), each filled by an agent persona (Rivo,
  Hopkins, Ogilvy, Angela, Wanamaker, Nightingale...) or a person; also front-desk,
  gardener and ops-manager. The `operator` seats run Codex, the rest Claude. Seat table in
  `docs/seats.md`, desk manuals in `seats/<seat>/DESK.md`. Launchd jobs
  `com.ipmedia.hive-paid-traffic.*` (operator slots 05:00/12:30/16:30/21:00, Slack, queues,
  nightly `faxina`).

Rules shared by both MeuPatrocínio crews (see each repo's `CLAUDE.md`): the MBP checkout is
the live one, so an edit takes effect on the next boot or run, and there is no copy on the
mini. Commit as **jeffheartmp** (`~/.gitconfig-mp`), not jahm2u, and push. To change them from
the mini, commit and push there, then `git pull --ff-only` on the MBP. Their human docs live in
the brain repo `jeffheartmp/hive` (`dev-crew/`, `paid-traffic/`). Agents talk across sessions
and Macs with `fleet-tell` (`~/.local/bin/fleet-tell` → `baba-fleet/bin/fleet-tell`;
`fleet-tell --list`).

Known stale bits (2026-10-17): both crew `CLAUDE.md` files place the brain at
`/Volumes/Workspace/repos/01_business/mp/hive` on the mini, a path on the failed external
drive, and the mini has no `01_business/mp/` at all. `hive-paid-traffic/CLAUDE.md` names the
session `hive-paid-traffic`, but `bin/hive` uses `mkt-crew`. A leftover `hive-paid-traffic`
herdr session (one idle Claude in `~`) still runs. Also on the MBP and down: `dev-crew-drill`,
`cw-test`, `cwq`, `dcrp-probe`.

Session sockets live on the MBP at `~/.config/herdr/sessions/<session>/herdr.sock`.
The `orgs` session is started and kept alive by
`baba-fleet/liaisons/org-seat/scripts/up.sh` (idempotent; starts only what is missing),
run every 60 s by the `com.babafleet.orgs-keeper` LaunchAgent. It only runs on
`ORGS_HOST` (default `ts-MacBook-Pro`). The same agent is installed on the mini, where it
refuses by design, so **never expect `orgs` to run on the mini**.

### The MBP must not sleep

All three sessions die whenever the MBP sleeps. Amphetamine (5.3.2, session at launch,
"Allow Closed-Display Sleep" off) only blocks *idle* sleep. Closing the lid still sleeps the
Mac (`pmset -g log`: `Entering Sleep state due to 'Clamshell Sleep'`) unless an external
display is attached or closed-display mode is active, and that needs the separate **Amphetamine
Enhancer** helper, which was not installed on 2026-10-17. Check: `ssh mbp 'pmset -g | grep
-E "SleepDisabled|sleep "; pmset -g log | grep Clamshell | tail -3'`. `SleepDisabled 1` means
lid-closed sleep is off.

**Fixed 2026-10-17 with `sudo pmset -a disablesleep 1`** (verified: lid closed, still reachable
over SSH). This disables sleep everywhere, battery included, so don't carry it closed in a
bag; undo with `sudo pmset -a disablesleep 0`. A macOS update can reset it, so re-check
`SleepDisabled` after one.

### When the sidebar says "reconnecting"

Work down the chain. Each step only makes sense once the one before it passes:

```bash
tailscale status | grep ts-macbook-pro     # 1. MBP online in the tailnet? "offline, last seen" = fix it ON the MBP (menu bar icon)
tailscale ping -c1 ts-macbook-pro          # 2. reachable?
nc -z -G 4 ts-macbook-pro 22               # 3. SSH port open? (times out for a minute or so while the MBP wakes)
herdr machine status                       # 4. per-session: reachable / error
herdr machine reconnect "mbp orgs"         #    re-auth one machine interactively if needed
ssh mbp 'export PATH=/opt/homebrew/bin:$PATH; bash ~/repos/01_business/tp/baba-brain/repos/baba-fleet/liaisons/org-seat/scripts/up.sh --no-attach'
                                           # 5. orgs server down: start what's missing
```

`herdr machine status` reporting `orgs` as "remote Herdr server is stopped or
incompatible" right after `up.sh` is normal: the server restarts its panes and comes
back by itself within a few minutes. Check the session directly instead of restarting
again: `ssh mbp 'HERDR_SOCKET_PATH=~/.config/herdr/sessions/orgs/herdr.sock /opt/homebrew/bin/herdr agent list'`.

**Incident 2026-10-17:** the mini reset unexpectedly at 09:22 (no panic report; firmware held panic telemetry). Afterwards the MBP stayed
offline in Tailscale for about 35 minutes until it was reconnected on the MBP itself.
Port 22 then timed out briefly, dev hive and mkt crew came back on their own, and `orgs`
needed one `up.sh` and a few minutes. Nothing on the mini was broken: when all three
sessions say "reconnecting" at once, look at the MBP first.

## Development & Troubleshooting

### Common Commands
```bash
# Reload configs
aerospace reload-config
brew services restart sketchybar
open -g hammerspoon://reload   # Reload Hammerspoon

# Check symlinks
ls -la ~/.config/* | grep "^l"

# Quick health check
launchctl list | grep "com.user"
ls -lh ~/.config/sketchybar/logs/
tail -f ~/.config/sketchybar/logs/*.log

# Audio debugging
/opt/homebrew/bin/SwitchAudioSource -a -t output -f json  # List all output devices
/opt/homebrew/bin/SwitchAudioSource -c -t output -f json  # Current output device
```

### Testing Components

```bash
# Calendar: bash ~/.config/sketchybar/helpers/sync-calendars.sh
# Todoist: bash ~/.config/sketchybar/helpers/todoist-precache.sh
# Meeting: bash ~/.config/sketchybar/helpers/meeting-prep.sh

# Check caches
ls -lh ~/.cache/sketchybar/

# Verify .env
cat ~/dotfiles/.env | grep -v "^#" | grep -v "^$"

# Test APIs
source ~/dotfiles/.env
curl -H "Authorization: Bearer $OPENAI_API_KEY" https://api.openai.com/v1/models | jq '.data[0].id'
curl -H "Authorization: Bearer $TODOIST_API_TOKEN" https://api.todoist.com/rest/v2/projects | jq '.[0].name'
```

### Troubleshooting Quick Reference

**Common Issues & Solutions:**

| Issue | Symptom | Solution |
|-------|---------|----------|
| **LaunchAgent not running** | `launchctl list \| grep {SERVICE}` empty | `launchctl load -w ~/Library/LaunchAgents/com.user.{SERVICE}.plist` |
| **Empty logs** | No log output | `mkdir -p ~/.config/sketchybar/logs && chmod 755 ~/.config/sketchybar/logs` |
| **API auth fails** | 401/403 errors | Check token in `.env`, test with curl |
| **Network errors** | Curl exit codes 6/7/28 | DNS=6, refused=7, timeout=28 - check connectivity |
| **Widget stale** | Shows old data | Trigger manual sync for service |
| **Python fails** | ModuleNotFoundError | Reinstall venv: `python3 -m venv ~/.config/sketchybar/venv && ~/.config/sketchybar/venv/bin/pip install -r ~/.config/sketchybar/requirements.txt` |
| **khal not found** | Exit code 127 | Check LaunchAgent PATH configuration (see above) |
| **Permissions denied** | Can't write logs | Check directory permissions |
| **Audio blaring on switch** | Volume spike when changing output | Verify `setVolume()` runs before AND after `setDefaultOutputDevice()` in `applyAudioSelection()` |
| **LG Dual missing** | Only individual LG devices show | Check `scripts/create-multi-output.swift` runs; verify with `SwitchAudioSource -a -t output -f json` |
| **Duplicate LG Dual** | Two dual entries in picker | Ensure "LG Dual" name is filtered in `buildAudioDeviceList()` device enumeration |
| **Volume keys disabled** | No-volume icon on LG Dual | `dualVolumeTap` eventtap must be running; check Hammerspoon console for errors |
| **Meeting prep no file** | "File not found after 10s" in log | Jonas API not writing to Docker volume; check Docker mount and Jonas logs |
| **Meeting prep wrong vault** | Obsidian "file not found" error | Verify `VAULT_NAME="kb"` in `meeting-prep.sh` matches actual vault folder name |
| **Disk full but `diskutil` shows far more free** | `df` free ≪ "Container Free Space" | TM local snapshots pin deleted files: `tmutil thinlocalsnapshots / 999999999999 4`, then check `tm-cleanup.log` |

**Force Complete Resync (Calendar Example):**
```bash
launchctl unload ~/Library/LaunchAgents/com.user.calendar-sync.plist
rm -rf ~/.cache/sketchybar/ ~/.local/share/khal/calendars/google
launchctl load -w ~/Library/LaunchAgents/com.user.calendar-sync.plist
bash ~/.config/sketchybar/helpers/sync-calendars.sh
brew services restart sketchybar
```

### Log & Cache Locations

**Logs:** `~/.config/sketchybar/logs/`
- `{SERVICE}.log` - Main service logs
- `{SERVICE}-stdout.log` - Standard output
- `{SERVICE}-stderr.log` - Error output
- `meeting-prep.log` - Meeting prep workflow
- `translations.log` - Every EN↔PT translation (JSON lines: ts, model, input, output); review to improve the translation prompt
- `~/.config/dotfiles-install.log` - Installation log

**Caches:** `~/.cache/sketchybar/`
- `last_sync_status` - Calendar sync status
- `todoist_tasks_cache` - Todoist tasks
- `todoist_working_task` - Current focus
- `last_meeting_prep_result.json` - Meeting prep result

## Contact & Support
Repository: https://github.com/jahm2u/dotfiles
For Claude-specific issues: Check `.claude/hooks/` for custom scripts