---
name: code-mode-usage
description: Check how Claude Code's Code Mode (CLAUDE_CODE_EXPERIMENTAL_CODE_MODE) is doing against ordinary sessions on this Mac, from real session transcripts, and add an entry to the living log. Use when the user asks "how is code mode doing", "compare code mode", "check the code mode log", "code mode token usage", "is code mode worth it", or wants the usage log updated.
---

# Code Mode usage

Code Mode is on for every session through `env` in `~/.claude/settings.json` (since 2026-11-17).
This skill answers one question from real work, not from synthetic tests: do Code Mode sessions
use fewer tokens, fewer model requests or less time than ordinary ones?

## 1. Run the check

```bash
~/.claude/skills/code-mode-usage/scripts/usage.py --sessions --log
```

It scans transcripts changed in the last 72 hours, updates one row per session in
`~/.claude/code-mode-usage/sessions.jsonl`, prints the comparison and appends it to
`~/.claude/code-mode-usage/LOG.md` under a dated heading that ends with an empty `**Notes:**`.

Transcripts are deleted after about 30 days and the store is the only lasting record, so if the
last log entry is more than three days old, pass `--hours` large enough to cover the gap
(`--hours 720` covers everything still on disk). `--no-scan` reports from the store alone.

The first line of output says how many transcripts were scanned. If that number is zero, the
check examined nothing: say so and find out why before reporting anything.

## 2. Read the table

One row per model and mode. Compare **only within the same model**: Opus builders and Fable
sessions do different work and start from different context sizes.

- `start ctx` is the fixed cost of a session before any work. Code Mode hides most tool
  definitions, so this should be lower.
- `ctx @N` is the context size at the Nth model request. This is the fair way to compare input
  cost, because total input grows with session length and a short session always looks cheap.
- `out/req` runs higher in Code Mode: the model writes a script where it used to write one call.
- `tools/req` counts tool calls made from inside scripts too. Far above 1 means the model is
  batching work into one request, which is the point of the mode.
- `req/prompt` is how many model requests one user prompt takes.
- `$/req` exists only for sessions that recorded a cost when they exited.

Every cell shows the number of sessions behind it. Under about ten sessions in a cell, report
the number as an early reading, not a result.

## 3. Write the notes

Read the previous entries in `LOG.md`, then fill in `**Notes:**` under the entry just added:
two to five bullets on what changed since the last entry, what is now supported by enough
sessions, and what is still too thin to call. Record setup changes that affect the numbers
(a Claude Code upgrade, MCP servers added or removed, the setting turned off somewhere).
Never rewrite earlier entries.

Then give the user the short version: the verdict so far, the two or three numbers behind it,
and how many sessions they rest on.

## What the numbers leave out

- Only this Mac. Sessions on the MBP (orgs, dev-crew, mkt-crew) keep their transcripts there.
- Code Mode does not start in headless `claude -p` runs, background jobs, teammates' panes,
  Remote Control, or when OpenTelemetry is on. Those sessions land in the ordinary rows.
- A Code Mode session has no Claude in Chrome or computer use, so browser work is always in the
  ordinary rows.
- The eight synthetic A/B sessions from 2026-11-17 are excluded by id in `usage.py`.
- The store and the log name private projects. They stay in `~/.claude/code-mode-usage/` and
  must not be copied into the dotfiles repo, which is public.
