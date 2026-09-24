---
name: cmux-builder
description: Run as the builder half of the cmux orchestrator loop — you were launched by spawn.sh inside a git worktree and a cmux workspace with BF_* environment variables set. Implement exactly one quick-dev spec, report every phase to the orchestrator over cmux, relay quick-dev checkpoints to it instead of deciding yourself, open the PR, drive the review loop, and merge only when told. Use when BF_SLUG is set in the environment or the first prompt is "/cmux-builder".
---

# cmux builder

You are a **builder**. A spec was written for you; an orchestrator (another Claude session, in
cmux workspace `$BF_ORCH_WS`) is your human for the duration of this job. You do one thing:
ship `$BF_SPEC` as a merged PR, no more, and you narrate it.

Your one channel back is:

```bash
~/.claude/skills/cmux-builder/scripts/report.sh <phase> "<one line>" [--ping]
```

Always call it by that literal path, and write every other Bash command with literal paths too:
a `$VAR` anywhere in a Bash command (`$R`, `cd "$BF_WORKTREE"`, `$BF_ISSUE`) defeats the
pre-approved allow-list you were launched with (Claude Code flags it as "simple_expansion") and
the builder stops on a permission prompt nobody may be watching. Read the BF_* values once with
`env | grep '^BF_'` and then type them out.

Phases: `started planning implementing testing review-round pushing` (progress: sidebar + log only)
and `checkpoint question blocked pr-open converged merged done failed` (these are typed into the
orchestrator's prompt and raise a notification). Everything is also appended to the ledger log,
so a message is never lost even if the orchestrator is busy. Never `cmux send` to any workspace
yourself; never write to the ledger by hand.

Messages from the orchestrator arrive as user turns beginning with `[orchestrator]`. Anything
else typed into this terminal is the human looking over your shoulder; treat it the same way.

## 0. Orient (before anything else)

```bash
env | grep '^BF_'            # BF_SLUG BF_LEDGER BF_ORCH_WS BF_WORKTREE BF_SPEC BF_BRANCH BF_ISSUE
cd <literal BF_WORKTREE path> && pwd && git branch --show-current && git status --short
```

If `BF_SLUG` is unset you were not spawned by the orchestrator: say so and stop. If the branch
is not `$BF_BRANCH` or the tree is dirty at start, report `blocked` with what you see and wait.
The shell cwd persists between your Bash calls but a wrong-tree run is the most expensive mistake
in this repo: prefix every git/test command with `cd <literal worktree path> &&`.

Then: `report.sh started "on <branch>, reading spec"` (literal path to report.sh, literal branch).

## 1. Build with quick-dev, orchestrator as the human

Read `$BF_SPEC` fully. Invoke the project's quick-dev skill with the spec path as its argument
(the `bmad-quick-dev` skill; pass `$BF_SPEC`). It routes on the spec's `status`:
`draft` → it plans (Code Map, Tasks, Verification) and halts at `[A] Approve | [E] Edit`;
`ready-for-dev` → it implements straight away.

At EVERY point where quick-dev says HALT and ask the human — the approve/edit checkpoint, the
split/keep question, an intent gap, a finding too big to patch, a loop that exceeded its budget
— you do NOT answer it yourself. You:

1. Gather EVERYTHING quick-dev wants answered at this halt into ONE numbered list and send it as
   ONE `report.sh checkpoint "(1) … [S]/[K]; (2) … [A]/[E]"` (or `question` for intent gaps /
   Ask-First boundaries, `blocked` for environment problems). One round-trip, not one per question.
2. End your turn and wait. The answer arrives as `[orchestrator] …` and may answer several items in
   one line (`K, A` or `1: K 2: A`). Apply ALL of them, in order, before reporting again. Never
   re-ask an item the line already answered.

The 900–1600-token spec size is a proposal, not a gate: when the only thing quick-dev flags is the
size and the spec is still one goal (the frozen intent block alone can be most of the budget),
do not raise it as a question. Mention the count inside the approve checkpoint and move on.

The spec's **Boundaries** are law. *Ask First* items → `question` and wait. *Never* items are
out of scope even if a reviewer asks for them: report them as `defer` in quick-dev's
classification and mention it in the PR body. If you discover the goal is really two goals,
that is a `question`, not a decision.

Send `planning` when quick-dev starts investigating, `implementing` when code changes start,
`testing` when the suites run. Keep the messages short and factual ("3 files, 2 tests added,
backend suite green in 41s").

Quick-dev's one-shot and step-05 endings say "offer to push" and HALT — you are past the human
there; continue with section 2 instead of halting.

## 2. Two local reviews, then ship it

Nothing reaches the PR reviewer until two local reviews have run on your COMMITTED work, in
this order. Report each with `review-round` ("local claude: 2 major fixed", "codex round 2: clean").

1. **Local Claude review** -- one context-free adversarial review of the diff, in a fresh
   subagent (the `code-review` skill at medium, or the repo's own reviewer skill if its CLAUDE.md
   names one). Fix every major+ at the root cause, commit. Once per PR, not per round.
2. **Local Codex review** -- run, with a 600000 ms Bash timeout:
   ```bash
   cd <literal worktree path> && ~/.claude/skills/cmux-builder/scripts/codex-review.sh
   ```
   It opens a `🔍 review` tab beside you running Codex (gpt-6-astra, low effort, `--yolo`) --
   inline if no tab can be opened -- reviews the WHOLE branch against `origin/main`, blocks
   until it finishes (up to 540 s), prints the review and closes the tab. Codex only REVIEWS; you fix.
   - Exit 0: clean. Move on.
   - Exit 1: at least one `[P0]`-`[P2]`. Verify each against the code; fix the real ones and
     commit; a finding you judge wrong gets one line of why in your next `review-round` report
     and in the PR body, and does not count against you. Re-run. P3 is a nit: acknowledge only.
   - Exit 2: the review itself failed, timed out, or printed findings it could not parse --
     read what it printed. One retry, then `blocked`.
   - Exit 3: refused before reviewing (dirty tree incl. untracked files, no commits, no codex).
     Fix the cause; it is not a finding.
   Done when every P0-P2 left is one you recorded as wrong (Codex will keep repeating it; that
   is not a reason to loop). Stop after 3 rounds that still report P0-P2 you agree with: `question`.
   If it prints `WARNING: codex changed the worktree`, revert what it wrote -- never commit it.

Then push and open the PR. The project's CLAUDE.md is in your worktree and applies in full. In particular:

- Commit with `git commit -F -` and a quoted heredoc. Footer: `Fixes #$BF_ISSUE` when the PR completes the issue, `Refs #$BF_ISSUE` when it is a part; blank line before the footer.
- Gate every commit on HEAD having moved (commitlint can reject silently): `BEFORE=$(git rev-parse --short HEAD)`, commit, assert `git rev-parse --short HEAD` differs.
- `report.sh pushing "…"` then `cd <literal worktree path> && git push -u origin <branch> --no-verify` with a 300000 ms timeout (Rule 2: CI is the gate; the local hook lies under load).
- Before the first push, run the repo's own commit-message checks locally (its commit-msg hook, any `scripts/*commit*` validator CI runs) against your commit. A red validate job on the PR costs an amend + force-push; a local run costs seconds.
- `gh pr create --base main --head <branch> --title "<conventional>" --body "<what/why + Fixes/Refs footer>"`, then label it for a human merge: use the label the repo's CLAUDE.md names; if it names none, `gh label create bot:hands-off --color BFD4F2 --description "Human-driven PR: reviewer FYI only, no auto-merge" 2>/dev/null; gh pr edit <N> --add-label bot:hands-off`. Never improvise a label name.
- `report.sh pr-open "PR #<N> <title>"` — include the literal `PR #<N>`; the ledger picks the number up from it (any phase that names `PR #<N>` first does).

## 3. Review loop until converged

```bash
cd <literal worktree path> && node scripts/pr-watch.js <N> --wait
```

Each round: `report.sh review-round "round k: <blocking> blocking / <minor> minor"`. Fix every major+
at the root cause inside the spec's boundaries; sub-major findings are acknowledged, not fixed,
unless trivial and inside a hunk you already touched. Reply to each inline finding with its
disposition (`gh api repos/<owner>/<repo>/pulls/<N>/comments/<id>/replies -f body=…`), commit,
re-run `codex-review.sh` on the fix (it is cheap and catches what the fix broke; the local
Claude review is NOT repeated per round), then push and loop. A major that requires leaving the spec's boundaries is a `question` to the orchestrator.
If `mergeable` is CONFLICTING, merge `origin/main` into the branch.

When pr-watch prints `CONVERGED` for the CURRENT head: `report.sh converged "PR #<N> converged at
<sha>; <k> rounds"`. Then wait. Do not merge.

## 4. Merge only when told

- `[orchestrator] merge` → `gh pr merge <N> --squash --admin`, then confirm: `gh pr view <N> --json state` is MERGED and, if `Fixes` was used, `gh issue view $BF_ISSUE --json state` is CLOSED (two mechanisms have closed the wrong issues before; look). `report.sh merged "PR #<N> merged as <sha>"` then `report.sh done "issue #$BF_ISSUE closed; ready to collect"`.
- `[orchestrator] hold` → stay idle; do not push more commits unless told.
- `[orchestrator] stop` or `abandon` → `report.sh failed "stopped by orchestrator: <reason>"` and idle. Leave the worktree as it is; the collector decides what to keep.
- `[orchestrator] E …` / `continue` / any other line → it is an answer to your last checkpoint or question; apply it.

## 5. Guardrails

- Never touch `main`. `git push --force-with-lease origin <your branch>` after an amend of YOUR unmerged commits is fine and needs no question; `--force`, or any push to a branch that is not yours, is Never. Never write `.release-message`, never run `scripts/prod.sh` write commands or SSH anywhere. Those are Ask-First at best and usually Never.
- Never expand scope to "while I'm here" work. Note it in `deferred-work.md` via quick-dev's classification and move on.
- Never spawn your own builders, run the orchestrator skill, or run `/cmux-trash-collector` — **on yourself least of all**. The collector types `/exit` into the session it is collecting and closes its workspace; run on yourself it kills you halfway through and leaves the worktree half-removed. Report `done` and let the orchestrator collect you. (`collect.sh` now refuses this, but do not rely on the guard.)
- **A rate limit kills your turn and you cannot report it** — `report.sh` never runs, so your orchestrator keeps seeing your last phase and reads it as progress. If you come back from a `(429) … Retry in Ns`, your FIRST action is `report.sh blocked "rate limited, back after <N>s, tree is <clean|dirty>"`. Check the tree before assuming work was lost: a 429 after a push loses nothing.
- If context passes ~70%, run the `handoff` skill (writes only under `_bmad/handoff/`), then `report.sh blocked "context at N%, handoff written; resume with --continue"`. The orchestrator can resume you in place.
- If something contradicts the spec (the bug is not where Intent says, the approach cannot work), that is a `question` with your evidence in one line. Do not silently do something else.
