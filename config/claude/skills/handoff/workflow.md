# Handoff — Workflow (smart compact)

The **memory arm** of the session. Capture everything this session learned
**before** the context window fills, so work can continue in a clean session
without losing knowledge. This is the **write-side** of smart handoff; the
read-side is automatic — after you `/clear` (or open a new session), the
globally-installed SessionStart hook
(`~/.claude/skills/handoff/scripts/handoff/inject_handoff.py`)
re-injects the handoff.

**Why not just `/compact`?** `/compact` keeps the same session and is lossy
compression on top of lossy compression — rationale and early constraints die
first. A curated handoff preserves far more, because you choose what survives.

## When to run

- The statusline or a Stop-hook reminder shows context ≳ 70%.
- You are about to hit a natural task boundary and want a clean slate.
- The user explicitly asks for a handoff / checkpoint / smart compact.

Run it **while you still have headroom** — generating the handoff itself costs
tokens, and you want it written from full context, not after auto-compact has
already fired.

## Per-project opt-in

The handoff state lives in `<project>/_bmad/handoff/`. The Stop-hook reminder
**only fires in projects where that directory already exists**, so it stays
silent in projects you never checkpoint. Creating the directory (this skill does
it on first run) opts the project in.

## What to produce

Write **two twin files** into `<project>/_bmad/handoff/`:

1. `HANDOFF-latest.md` — the human- and model-readable narrative. **This is what
   gets injected** into the next session, so it must be self-sufficient.
2. `HANDOFF-latest.json` — the machine-readable structured twin (durable state
   that must not be paraphrased away). Use JSON, not prose, for the state that
   matters most; models overwrite Markdown more readily than strict JSON.

Overwrite both each time (they are `*-latest`). Writing new content auto-resets
the injection dedupe (the hook keys on content hash), so the next fresh session
picks up the new checkpoint exactly once.

## Procedure

1. **Gather state from your live context first** — you ARE the session; do not
   parse the transcript. Recall: what you were asked to do, what you tried, what
   broke and *why*, what you decided and *why*, what is done vs pending.
2. **Cross-check durable sources** (read-only):
   - `git status` / `git branch --show-current` / recent commits — branch, WIP,
     uncommitted work, open PRs (`gh pr list` if relevant).
   - Any issue/task tracker state relevant to the work in flight.
   - Existing project docs / ADRs / CLAUDE.md — so the handoff does not duplicate
     facts already persisted durably; instead **reference** them and keep the
     handoff for *this* session's in-flight state.
3. **Read the previous handoff and interview the user (interactive, like plan
   mode).** Before writing anything, read the existing
   `_bmad/handoff/HANDOFF-latest.json` + `.md` if they exist (skip silently if
   this is the project's first handoff). Then run a short interview with the
   `AskUserQuestion` tool — **at most two rounds, at most three questions per
   round** (hard cap: 6 questions total; fewer is better). Every question must
   offer concrete options with a recommended default first.

   - **Round 1 — pending decisions.** If the previous handoff's `open_questions`
     (or anything in *this* session that is genuinely awaiting the human's call)
     is non-empty, ask those first — up to three, highest-impact first. Drop any
     that this session already resolved.
   - **If nothing is pending**, use round 1 instead to nail down the **next
     steps** so the next session starts on the right foot: e.g. which thread to
     pick up first, what "done" looks like for it, scope boundaries / anything
     to explicitly *not* touch, and what to verify before declaring it done.
   - **Round 2 (optional)** — only if round-1 answers opened a material follow-up
     (a chosen option needs a sub-decision, or the priority changed and the next
     steps need re-ordering). If nothing materially changed, skip it.
   - Do **not** ask things you can answer yourself from git/docs/context, and do
     not ask "shall I proceed?" — the interview is for decisions and direction,
     not permission.

   Fold the answers into the handoff: each answered question becomes a
   `decisions[]` entry (answer = `decision`, the user's reasoning/your context =
   `rationale`); `open_questions` keeps only what is still genuinely unresolved
   (a question the user declined or deferred stays there, marked as such);
   `next_steps` is re-ordered to match what the user chose. The markdown,
   progress snapshot, and continuation prompt below are all written **after**
   the interview so they reflect the final state.
4. **Write `HANDOFF-latest.json`** with the schema below.
5. **Write `HANDOFF-latest.md`** as the narrative: numbered sections, "the big
   pains", landmines, exact commands/paths. Include a short
   "Decisions made at handoff" section listing the interview outcomes so the
   next session knows they were settled by the human, not assumed.
6. **Append the learnings to the log** (deterministic helper):

   ```bash
   python3 ~/.claude/skills/handoff/scripts/handoff/log_learnings.py "$(pwd)"
   ```

   This distils `problems` / `landmines` / `decisions` from the JSON into an
   append-only `_bmad/handoff/learnings-log.jsonl`. It is idempotent per handoff
   (keyed on `created_at`), so running it twice is safe. Over time this log is
   the raw material for promoting recurring pains into project rules or
   CLAUDE.md entries.
7. **Render the progress snapshot** (deterministic helper) — this is the FIRST
   thing your final reply to the user shows, before any prose:

   ```bash
   python3 ~/.claude/skills/handoff/scripts/handoff/summarize_progress.py "$(pwd)"
   ```

   It reads the JSON you just wrote and prints a bar-charted view: a stacked
   progress bar over `problems` by status, a "Still open / next" list, open PRs,
   and a "Needs your decision" section fed from `open_questions`. So the chart is
   accurate, make sure the JSON's `problems[].status`, `next_steps`, and
   `open_questions` reflect the true end-of-session state before you run it — in
   particular, anything genuinely awaiting the human's call belongs in
   `open_questions`, and a merged/closed item should be `status: fixed`, not left
   `open`.
8. **Copy the continuation prompt to the clipboard.** Write a tight kickoff
   prompt for the next session (what to read, the ordered next actions as
   settled in the interview, the load-bearing landmines — grounded in the JSON
   you just wrote). **The first line must be a title** so it is easy to find in
   a clipboard manager, in exactly this shape:

   ```
   HANDOFF <repo>@<branch> — <YYYY-MM-DD HH:MM local> — <what was being done, ≤8 words>
   ```

   e.g. `HANDOFF tp@main — 2026-08-22 14:05 — wiring Stripe webhook retries`.
   Put one blank line after the title, then the prompt body. Write it to a path
   **unique to this worktree and branch** — never a shared
   `/tmp/handoff-continuation.txt`, which two concurrent sessions silently
   overwrite for each other, so the second to finish wins and the first
   session's prompt is gone with nothing to signal it:

   ```bash
   CONT="/tmp/handoff-continuation-$(basename "$(git rev-parse --show-toplevel)")-$(git rev-parse --abbrev-ref HEAD | tr '/' '-').txt"
   # ... write the prompt to "$CONT" ...
   pbcopy < "$CONT"   # macOS
   ```

   Each linked worktree has its own `--show-toplevel`, so parallel sessions on
   the same repo get distinct files even on the same branch name.

   Use `pbcopy` on macOS (`wl-copy`/`xclip -selection clipboard` on Linux if
   `pbcopy` is absent). Confirm to the user that it is on their clipboard — quote
   the title line so they can recognise it — so they can paste it straight into
   a fresh session. If no clipboard tool exists, say so and print the prompt
   inline instead.
9. **Tell the user** it is written: LEAD with the progress snapshot from step 7,
   then report **both handoff paths**, confirm the continuation prompt is on
   their clipboard, and note they can now `/clear` (same terminal) or open a
   fresh session to continue — the SessionStart hook re-seeds it. Do **not** run
   `/clear` yourself; that is the human's call.

## JSON schema (`HANDOFF-latest.json`)

```json
{
  "created_at": "<ISO-8601 UTC — produce it with exactly `date -u +%Y-%m-%dT%H:%M:%SZ`; the bare `date` default is locale-dependent and not ISO-8601>",
  "repo": "<repo name>",
  "branch": "<git branch>",
  "head_sha": "<short sha>",
  "mission": "One paragraph: what this session set out to do and where it got to.",
  "problems": [
    {"problem": "...", "root_cause": "...", "solution": "...", "status": "fixed|open|workaround"}
  ],
  "decisions": [
    {"decision": "...", "rationale": "..."}
  ],
  "current_state": {
    "wip": "what is half-done right now",
    "open_prs": ["#NN ..."],
    "uncommitted": "summary of working-tree changes"
  },
  "next_steps": ["ordered, concrete, the first thing the next session should do"],
  "landmines": ["things that will bite — do NOT do X; Y looks done but isn't"],
  "open_questions": ["still unresolved after the handoff interview (incl. ones the user deferred)"],
  "files_touched": ["path — why"],
  "verification": ["exact commands to confirm state, e.g. npm test ..."],
  "related_docs": ["doc/ADR slug — what it covers"]
}
```

## Quality bar

- **Capture the *why*, not just the *what*.** Rationale and dead-ends are the
  first thing lost to compaction and the most expensive to rediscover.
- **Landmines are mandatory** if any exist (e.g. "merging to main auto-deploys
  prod"). These are the highest-value lines in a handoff.
- **Be concrete**: real paths, real commands, real SHAs.
- **Stay under ~24k characters** in the markdown (the injection cap,
  `MAX_INJECT_CHARS`). If the session is huge, summarise older threads and keep
  the forward-looking detail.
- **Reference, don't duplicate**: durable cross-session facts belong in the
  project's docs/ADRs; the handoff is for *this* session's in-flight state.

## Critical rules

- Read-only on production source — this skill only writes under `_bmad/handoff/`.
- Never run `/clear` or start a new session for the user.
- The interview is capped at two rounds of three questions; never exceed it,
  and skip round 2 when nothing material came out of round 1.
- Never wrap the write in a way that could fail silently — confirm both files
  were written and report their paths.

## Gitignore

`_bmad/handoff/HANDOFF-latest.*`, `_bmad/handoff/.consumed`,
`_bmad/handoff/.reminder` and `_bmad/handoff/*.lock` (the advisory flock
sidecars that serialise concurrent hook writes) are regenerable scratch and
should be gitignored. `_bmad/handoff/learnings-log.jsonl` and
`_bmad/handoff/.kaizen-watermark` are **committable signal** — the durable
learnings feed — and stay in git.

Suggested `.gitignore` block:

```gitignore
_bmad/handoff/HANDOFF-latest.*
_bmad/handoff/.consumed
_bmad/handoff/.reminder
_bmad/handoff/*.lock
```
