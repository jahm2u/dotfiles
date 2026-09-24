@RTK.md

# cmux worktree builders (any repo)

Three machine-wide skills in `~/.claude/skills/` let the session Jeff is talking to farm out a
single-goal change to a fresh Claude in its own git worktree and cmux workspace, and stay in
control over cmux:

- `/cmux-orchestrator` -- write a quick-dev spec (Intent + Boundaries only), `scripts/spawn.sh`
  it (`--model 'opus[1m]'`, Opus 5 with the 1M window; `--permission-mode auto`; branch off `origin/main`, worktree at
  `.claude/worktrees/wt-<slug>`), then supervise: builder messages arrive in YOUR prompt as
  `[builder <slug>] <phase>: ...`; answer with `scripts/tell.sh <slug> "..."`, look with
  `scripts/peek.sh`, list with `scripts/ls.sh`. You decide when it merges.
- `/cmux-builder` -- what the spawned session runs. Implements the spec through `bmad-quick-dev`,
  relays every quick-dev HALT to the orchestrator instead of answering it, runs two LOCAL reviews
  before the PR (a `/code-review` subagent, then `scripts/codex-review.sh`: Codex gpt-6-astra, low
  effort, `--yolo`, in a `🔍 review` tab, repeated until no [P0]-[P2]), opens the PR, drives
  the PR reviewer's loop (re-running Codex on each fix), merges only on `merge`. Reports through `scripts/report.sh <phase> "..."`.
- `/cmux-trash-collector` -- after `done`: verifies the PR merged and the tree is clean (refuses
  otherwise; `--force` is a human decision), archives spec/log/deferred-work under
  `_bmad/handoff/cmux/archive/<slug>/`, exits the builder, closes its workspace, removes the
  worktree and branch.

Ledger per builder: `<primary checkout>/_bmad/handoff/cmux/<slug>.env` + `.log` (gitignore it
in each repo). Requires: running inside cmux (`cmux identify`), `gh` auth, and a project that
carries the `bmad-quick-dev` skill with its `spec-template.md`. Auto mode needs an Opus-class
model; `--model haiku` falls back to whatever `--mode` you pass.
Builders start with NO MCP servers (`--strict-mcp-config`): MCP tool descriptions are their
largest fixed context cost and an Opus builder auto-compacted before its second report with
BabaFlow's loaded. `spawn.sh --mcp full` opts back in when the spec needs a browser or a project MCP.
Each repo's builders sit in one pinned, collapsible sidebar group, `🔨 <repo> builders`, with
the orchestrator's workspace as the first item under the header and builders below it; the
folder stays while the orchestrator is in it (`--group mine|none` to override).
