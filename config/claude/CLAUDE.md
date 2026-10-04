@RTK.md

# cmux worktree builders (any repo)

Three machine-wide skills in `~/.claude/skills/` let the session Jeff is talking to farm out a
single-goal change to a fresh Claude in its own git worktree and cmux workspace, and stay in
control over cmux:

- `/cmux-orchestrator` -- write a bmad-build plan (Intent + Boundaries only, from `plan-template.md`), `scripts/spawn.sh`
  it (`--model 'opus[1m]'`, Opus 5 with the 1M window; `--permission-mode auto`; branch off `origin/main`, worktree at
  `.claude/worktrees/wt-<slug>`), then supervise: builder messages arrive in YOUR prompt as
  `[builder <slug>] <phase>: ...`; answer with `scripts/tell.sh <slug> "..."`, look with
  `scripts/peek.sh`, list with `scripts/ls.sh`. You decide when it merges.
- `/cmux-builder` -- what the spawned session runs. Implements the spec through `bmad-build` (the new BMAD, rendered against the BMAD root spawn resolves),
  relays every bmad-build HALT to the orchestrator instead of answering it, runs two LOCAL reviews
  before the PR (a `/code-review` subagent, then `scripts/codex-review.sh`: Codex gpt-6-astra, low
  effort, `--yolo`, in a `🔍 review` tab, repeated until no [P0]-[P2]), opens the PR, drives
  the PR reviewer's loop (re-running Codex on each fix), merges only on `merge`. Reports through `scripts/report.sh <phase> "..."`.
- `/cmux-trash-collector` -- after `done`: verifies the PR merged and the tree is clean (refuses
  otherwise; `--force` is a human decision), archives spec/log/deferred-work under
  `_bmad/handoff/cmux/archive/<slug>/`, exits the builder, closes its workspace, removes the
  worktree and branch.

Ledger per builder: `<primary checkout>/_bmad/handoff/cmux/<slug>.env` + `.log` (gitignore it
in each repo). Requires: running inside cmux (`cmux identify`) or herdr (`HERDR_ENV=1`), `gh` auth, and a project that
has a BMAD root at or above it (`_bmad/scripts/render_skill.py` + `.agents/skills/bmad-build`, normally `tp/baba-brain`) and `uv` installed. Auto mode needs an Opus-class
model; `--model haiku` falls back to whatever `--mode` you pass.
Builders start with NO MCP servers (`--strict-mcp-config`): MCP tool descriptions are their
largest fixed context cost and an Opus builder auto-compacted before its second report with
BabaFlow's loaded. `spawn.sh --mcp full` opts back in when the spec needs a browser or a project MCP.
Each repo's builders sit in one pinned, collapsible sidebar group, `🔨 <repo> builders`, with
the orchestrator's workspace as the first item under the header and builders below it; the
folder stays while the orchestrator is in it (`--group mine|none` to override).
**herdr too:** run the orchestrator from a herdr pane (`HERDR_ENV=1`) and the same three skills
drive herdr instead: builders become `🔨 <slug>` herdr tabs in the orchestrator's workspace, started
as herdr agents `b-<slug>`, reports arrive via `herdr agent prompt`. The ledger's `BF_MUX` picks the
backend per builder (absent = cmux), so cmux builders and herdr builders coexist.

# Gemini API key (machine-wide)

A Google Gemini API key lives at `~/.config/gemini/api_key` (mode 600; also honoured as
`$GEMINI_API_KEY`). Use it for anything Gemini-shaped: YouTube transcripts/summaries (Gemini
takes a YouTube URL directly as `file_data`, so no yt-dlp or captions needed), long-document or
video/audio understanding, or a second-opinion model. Helper, stdlib only:

```bash
~/.config/gemini/gemini.py yt-transcript "<youtube-url>" --out /tmp/yt/<id>.md   # verbatim, [mm:ss] stamps
~/.config/gemini/gemini.py yt-summary    "<youtube-url>"                          # key points
~/.config/gemini/gemini.py prompt        "<text>" [--model gemini-2.5-pro]        # default gemini-2.5-flash
```

REST endpoint if calling directly: `POST https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent`
with header `x-goog-api-key`. Never print or commit the key; write transcripts to a file and summarise, don't paste them whole.
