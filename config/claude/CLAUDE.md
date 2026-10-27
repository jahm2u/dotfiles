@RTK.md

# cmux worktree builders (any repo)

Three machine-wide skills in `~/.claude/skills/` let the session Jeff is talking to farm out a
single-goal change to a fresh Claude in its own git worktree and cmux workspace, and stay in
control over cmux:

- `/cmux-orchestrator` -- write a bmad-build plan (Intent + Boundaries only, from `plan-template.md`), `scripts/spawn.sh`
  it (`--model 'opus[1m]'`, Opus 5 with the 1M window; `--dangerously-skip-permissions` by default (Jeff 2026-10-25: "all builders should be launched with the yolo dangerous permissions thing"; `--mode auto` opts back); branch off `origin/main`, worktree at
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
**Orca too:** run the orchestrator from an Orca.app terminal (`TERM_PROGRAM=Orca`) and builders
become `🔨 <slug>` Orca terminal tabs in the orchestrator's Orca worktree (`BF_MUX=orca`); phases
show in the tab title. lib.sh's `bf_orca` calls the app's bundled CLI, since `/usr/local/bin/orca` is broken.

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

On the mini the same key is at `~/.config/gemini/api-key` (hyphen, chmod 600). Source is the
moderation bot's dev key in SSM (`/ipmedia-approvalbot-dev/gemini-api-key`, profile `ipmedia-ai`,
us-east-2); if the file is missing, re-pull it from there without echoing it. To watch or
summarize a video (YouTube URL or local file) use the `gemini-video` skill
(`~/.claude/skills/gemini-video/scripts/gemini.py`); it is a good fit for a subagent when the
notes are long. Keep outputs outside project repos unless asked.

# OpenAI API key (machine-wide)

An OpenAI API key lives at `~/.config/openai/api-key` (mode 600, one line; copied from mini-mp on
2026-10-18, and mini-mp has it at the same path). Use it for image generation and editing
(`gpt-image-1`), a second-opinion model, or anything else OpenAI-shaped. Codex doesn't need it,
because Codex logs in through ChatGPT. Read it as `$(tr -d '[:space:]' < ~/.config/openai/api-key)`,
and send it as `Authorization: Bearer`.

For mascot/widget art (consistent character poses as transparent cutouts, status-coloured previews) use
the `mascot-art` skill, which wraps both keys. For other images use the `openai-image` skill
(`~/.claude/skills/openai-image/scripts/gen_image.py`). Never print or commit either key. If the
file is missing, ask Jeff to copy the key and run
`! pbpaste > ~/.config/openai/api-key && chmod 600 ~/.config/openai/api-key`.

# Video and motion skills (third-party, in `~/.claude/skills`)

To make a promo, ad, reel, explainer or any video from code, start with `motion-graphics` (HTML
scenes rendered in headless Chrome, with an original score) or the `remotion-*` family
(`remotion-best-practices` routes to the rest: create, captions, render, studio, maps...). For
animation inside a web app use `animation-design` (LottieFiles / Rive search and embed) and
`motion-design` (timing, easing, choreography). They were copied from upstream GitHub repos; the
source commit of each is in `~/.claude/skills/.third-party-motion-skills.txt`. To update one,
re-copy it from upstream rather than editing it in place.

# Commit messages in meupatrocinio code repos

In any `meupatrocinio` org code repo (services-monorepo etc.): commit messages are a single line, max 100 characters, no body, no trailers (no Co-Authored-By). PRs are squash-merged, so the squash message must also be one line. Inline code comments only when the why is truly non-obvious — the team strips explanatory comments in review.

# Refer to PRs and issues by full URL, never by number

In anything a person reads (Slack messages, PR and ticket comments, docs, emails, and replies to Jeff), a pull request or issue is written as its full URL, e.g. `https://github.com/meupatrocinio/front/pull/4824`. Never write `#4824`, `PR #4824`, `front#4824` or any other bare-number form: the number means nothing outside the repo it belongs to, and readers cannot click it. Commit messages are the only exception, where GitHub's own squash suffix adds the number.

# Worktree and cmux sessions report to the orchestrator

This is how parallel work always runs here, not a per-task instruction. A long task is split
across several sessions: one **orchestrator** holds the plan and the gates, and one or more
**worker** sessions run in their own git worktree, usually in their own cmux workspace.

## If you are a worker session

You were launched into a worktree by an orchestrator. Your plain output reaches nobody: the
human is not watching your pane, and the orchestrator cannot see it. `SendMessage` is the only
channel that reaches anyone.

**Find the orchestrator** with `ListAgents`. It is the peer session named after the repository's
main checkout rather than a ticket slug — a worker is named for its worktree (`ai-709-…`,
`fix-ai-687-…`), the orchestrator is not. If the prompt that launched you named a session, that
name wins over the heuristic. If two candidates are plausible, ask one rather than guessing
silently.

**Message it, with `SendMessage`, at each of these moments:**

- **You are blocked.** Never end a run holding an unanswered question. Send the question, say what
  you already ruled out and why, and give your own recommended answer so a decision is one word.
- **You finished.** Report what changed, the gate numbers you actually saw, and every decision you
  took unattended.
- **You found something that changes the plan.** A premise in the ticket that is false, a hazard
  nobody costed, work already done elsewhere. Send it when you find it, not at the end.
- **You are about to do something outward-facing** that the brief did not clearly authorise:
  pushing, opening or merging a PR, writing to a tracker, touching a live environment.

**Do not put a question to the human directly.** Not with `AskUserQuestion`, not by stopping and
hoping. Route it through the orchestrator, which is holding the context needed to answer most of
them without spending the human's attention. Batch what you send: one message, numbered, each
item carrying your recommendation.

**A report is evidence, not a claim.** "Tests pass" is worth nothing; the suite and test counts
you read are worth everything. Say which gates you did not run and why. If a gate was skipped by
a hook or a path filter, say "skipped", never "green".

## If you are the orchestrator

Name yourself in every launch prompt so no worker has to guess the address. Tell each worker the
exact files it owns when several share one worktree, and tell them not to run full gates in a
shared tree, because another worker's half-finished edit makes them red for reasons that are not
theirs. Run the authoritative gate pass yourself.

Answer what you can from the context you hold. Escalate to the human only what genuinely needs
them, batched, numbered, with your recommendation on each. A worker's "done" is a claim until
`git status`, `git ls-remote`, `gh pr view` and a test run you watched agree with it.

**Arm a watch for anything you are waiting on. Never wait blind and never poll.** The moment you
dispatch a worker, start a long-running job, or push a branch whose CI you care about, start a
`Monitor` with a script that emits one line per event you would act on. Polling in a loop burns
context and misses things between checks; sitting idle means you learn nothing until someone asks.

Write the watch script so it can only report the truth:

- **Cover every terminal state, not just success.** A filter that matches only the happy path is
  silent through a crash, a hang and a queue that never starts, and silence is indistinguishable
  from "still running". Before arming, ask: if this failed right now, would my script print
  anything? If not, widen it.
- **An empty field is not a verdict.** A check with no conclusion yet is pending, not green.
  Treating a blank as settled will tell you a run passed when it has not started. Match on the
  values that mean finished, never on "not obviously bad".
- **Read counts, never exit codes.** A suite that never loaded exits the same way as one that
  passed, and a wrong path filter reports "no tests found" as a failure rather than as the
  misconfiguration it is.
- Every pipe stage must flush per line (`grep --line-buffered`, `awk` with `fflush()`), and never
  pipe through `head`, which delivers nothing until its count is reached.

When a watch fires with something the human would act on now, tell them. When it fires with
routine progress, stay quiet and keep working.

# A gate must prove it examined the thing

The most common defect in this codebase is not a broken check. It is a check that passes without
ever looking at what it claims to guard, and then stays green for months while everyone trusts it.
Four independent instances were found in a single day: a test script whose path filter matched
nothing and exited 0 while 61 spec files sat there; a jest config whose `rootDir` excluded a whole
tree, so sixteen tests were never collected in CI; a pre-push hook running `prettier --write`,
rewriting the very files it was judging; and an integration fixture that built its table definition
from the same constant the query used, so renaming the column renamed both sides and the check
could not fail on its own predicate.

All four were green. None had ever been watched failing.

## The rules that follow from it

**Read counts, never exit codes.** A suite that never loaded exits exactly like one that passed.
"No tests found" is a misconfiguration reporting itself as a result. Quote the number of suites and
tests you saw, and if that number is zero, the gate did not run.

**A selector that matches nothing must fail, not pass.** Any glob, path filter, `--testPathPattern`
or changed-files list is itself a thing that can be wrong. Assert its cardinality: if the filter
selects zero files, that is an error, not an empty success.

**A gate must not write.** A check that runs `--fix` or `--write` reports on the state it just
created, not the state that was committed. Keep the fixing command out of every gate path and the
checking command out of every fixing path. Watch especially for a gate that writes AFTER the
artifact under test is built, because then even a correct-looking result describes something that
was never committed.

**Point the check at the artifact that fails in production, not at a faithful stand-in.** If the
fixture and the code under test both derive from the same constant, they agree by construction and
the check is decorative. Hand-transcribe the thing being verified from its real source, and say in
a comment that the duplication is deliberate so nobody later tidies it back.

**"Skipped" is never "green".** A hook that prints "no source files changed, skipping tests", a
suite gated behind an environment variable nobody set, a job that ran but loaded no spec covering
your change: each is an absence of evidence. Say "skipped" and name what went unexercised.

**An empty field is not a verdict.** A check with no conclusion yet is pending. Treating a blank as
settled reports a run as passed before it has started.

## The standard that makes all of it real

**A new or tightened gate ships with a demonstrated failure.** Seed the violation, watch the named
check go red, revert the seed, watch it go green, and record both counts. Writing a guard and
watching a guard work are different acts, and only the second is evidence. If you cannot make it
fail, you have not built a gate, and you should say so rather than claim one.
