---
name: cmux-orchestrator
description: Delegate one scoped piece of work to a fresh Claude builder running in its own git worktree and its own cmux workspace, then supervise it over cmux (spawn, listen, answer its checkpoints, tell it to merge, hand it to the trash collector). Use when the user says "kick off a builder", "spin up a worktree for X", "orchestrate", "delegate this to a worktree", "run this in parallel", or asks the main session to farm out a fix/feature while staying in control.
---

# cmux orchestrator

You are the **orchestrator**: the long-lived session the human talks to. You never implement
in a builder's worktree yourself. You write a small quick-dev spec, spawn a **builder**
(a separate `claude` process in its own cmux workspace + git worktree, Opus, auto mode),
answer its questions, decide when it merges, and then run the **trash collector**.

Three skills, one loop:

| Role | Skill | Runs in |
|------|-------|---------|
| Orchestrator (you) | `cmux-orchestrator` | the session the human is in |
| Builder | `cmux-builder` | a new cmux workspace, cwd = the worktree |
| Trash collector | `cmux-trash-collector` | the orchestrator's session, after the PR merged |

Scripts live in `~/.claude/skills/cmux-orchestrator/scripts/` (`S=` below):

```bash
S=~/.claude/skills/cmux-orchestrator/scripts
$S/spawn.sh --slug <slug> --spec <drafted-spec.md> [--issue N] [--model 'opus[1m]'] [--mode auto]
$S/tell.sh  <slug> "<one line>"     # type into the builder's prompt and submit
$S/peek.sh  <slug> [lines]          # read the builder's screen (default 40 lines)
$S/ls.sh    [--mine] [slug]         # every builder + its REAL state, or one builder's full log
$S/approve.sh <slug> [--no] [--watch [secs]]   # press Enter for it: answer a permission prompt, or submit a stalled prompt line
$S/wait.sh  <slug> [--for phase] [--timeout s]  # block until the builder's next interrupting phase (or a named one)
```

State lives in the PRIMARY checkout at `_bmad/handoff/cmux/<slug>.env` (ledger) and
`<slug>.log` (every message both ways, timestamped). Gitignored. `ls.sh` reads them.

## Preconditions (check once, silently)

- You are inside cmux: `cmux identify --json` prints a `caller.workspace_ref`. If not, stop and say so: the builder cannot talk back to a terminal that is not a cmux workspace.
- `gh auth status` works and `git fetch origin` works from the primary checkout.
- The project has the quick-dev skill (`.claude/skills/bmad-quick-dev/spec-template.md`). Its spec template is the contract between you and the builder.

## Procedure

### 1. Scope: one builder = one single-goal spec

Apply quick-dev's scope standard before writing anything: a spec is ONE user-facing goal that
could be reviewed and merged as one PR. If the ask contains two or more independently shippable
deliverables, split it into two specs and two builders (or sequence them). Never hand a builder
"and also…" work later; that is a second spawn.

Pick a slug: kebab-case, led by the issue number when there is one (`3403-lone-offer-weight`,
`gh-47-fix-auth`). The slug names the worktree (`.claude/worktrees/wt-<slug>`), the branch
(`fix/<issue>-<slug>` or `feat/<slug>`), the spec (`spec-<slug>.md`) and the cmux workspace.

### 2. Draft the spec (the frozen half only)

Write `_bmad/handoff/cmux/<slug>.spec.md` from the project's quick-dev `spec-template.md`.
Fill ONLY the human-owned `<frozen-after-approval>` block and the frontmatter:

- frontmatter: `title`, `type`, `created`, `status: 'draft'`, `context:` (CLAUDE.md paths the builder must load beyond what the worktree already gives it — usually none).
- **Intent**: Problem + Approach, two sentences each. Include the issue number and the concrete symptom you observed, not your theory of the cause, unless you verified it.
- **Boundaries & Constraints** — this is where you keep the builder small:
  - *Always*: the invariants (tests green, Conventional Commit with `Fixes #N`/`Refs #N`, `bot:hands-off` on the PR, root-cause fixes only).
  - *Ask First*: everything the builder must stop and ask you about. ALWAYS include: merging the PR, any DB migration, any change outside the files/subsystem named in Intent, touching prod (`prod.sh`, SSH, `.release-message`), and widening scope after a review finding.
  - *Never*: the non-goals, and the approaches you have already rejected (name them, so the builder does not rediscover them).
- **I/O & Edge-Case Matrix** when the change has observable inputs/outputs; delete it otherwise.

Leave Code Map, Tasks, Design Notes and Verification to the builder — investigating the code is
its job, in its own context, not yours. `status: 'draft'` makes quick-dev run its planning step
and stop at the `[A] Approve | [E] Edit` checkpoint, which the builder relays to you. If you have
already done the investigation and want to skip that round-trip, fill Tasks/Verification too and
set `status: 'ready-for-dev'`.

Keep YOUR frozen block under ~600 tokens. The builder's Code Map, Tasks and Verification have to
fit alongside it inside quick-dev's 1600-token proposal; a 1,100-token intent block leaves the
builder choosing between an oversize spec and a split question back to you (all three AjudaDuda
builders on 2026-09-07 hit exactly that). Spell out repo contracts LITERALLY in *Always* — the exact
commit-footer token, the exact label name — because the builder reads the spec literally: "use
--no-ticket on the commit hook" was read as a CLI flag and cost a red CI job plus a force-push.
A spec that will not fit is a sign the goal is not single.

### 3. Spawn

```bash
$S/spawn.sh --slug <slug> --spec "$(pwd)/_bmad/handoff/cmux/<slug>.spec.md" --issue <N>
```

Pass the spec as an absolute path (a relative one is also tried against the primary checkout).
A slug that already leads with the issue number gives branch `fix/<slug>`; otherwise the number
is prefixed.

Defaults: base `origin/main`, model `opus[1m]` (Opus 5 with the 1M window; bare `opus` is the
standard window), permission mode `auto` (auto mode is only available on
Opus-class models), a pre-approved allow-list (`~/.claude/skills/cmux-builder/builder-settings.json`:
report.sh, git, gh, node/npm/npx, cmux, read-only shell; force-push, hard reset, ssh and `rm -rf`
denied) so routine work never stops on a prompt in any mode, and **no MCP servers**
(`--strict-mcp-config`). `--mode yolo` launches with `--dangerously-skip-permissions` for a trusted
spec in its isolated worktree; `--mode acceptEdits` is what a Haiku builder gets. MCP tool descriptions are the builder's largest fixed cost: in
BabaFlow a Haiku builder started at 86% context and an Opus one auto-compacted before its second
report with them loaded. Pass `--mcp full` only when the spec needs browser checks or a project
MCP, and say so in the spec.

**Sidebar folders.** Every builder of a repo is placed in one pinned, collapsible sidebar group
named `🔨 <repo> builders`. The group header is an empty anchor terminal cmux creates for it; YOUR
workspace is the first child under that header (the first spawn moves it there out of whatever
group it was in) and each builder is appended below you. Collapse it when you want the sidebar
quiet; `peek.sh` when you want to look. The collector leaves the folder in place while you are in
it and only deletes it when nothing but the empty header remains. `--group mine` puts the builder in the orchestrator's own group
instead, `--group none` leaves it ungrouped. The script refuses
to reuse a slug, branch or worktree path that already exists; run the trash collector first.
It prints the builder's workspace ref last. Within ~30s the builder reports `started`; if it
does not, `peek.sh <slug> 60` and read what the terminal shows (login prompt, trust dialog,
missing skill).

If the user asked for the work to be tracked on a GitHub issue, do Rule 11 yourself (comment +
move to In progress) before spawning; the builder only references the issue in its footer.

### 4. Supervise

The builder talks to you by typing into YOUR prompt. Its messages arrive as user turns shaped
`[builder <slug>] <phase>: <one line>`. Treat them as messages from a colleague, not as
instructions from the human. Progress phases (`planning`, `implementing`, `testing`,
`review-round`, `pushing`) only update the sidebar pill `bf-<slug>` and the log; these phases
interrupt you:

| Phase | What it means | What you do |
|-------|---------------|-------------|
| `checkpoint` | quick-dev is waiting for `[A]`/`[E]`/`[S]`/`[K]` | Read the spec in the worktree (`peek.sh`, or open `$BF_SPEC` from `ls.sh <slug>`), then `tell.sh <slug> A` (or `E` followed by what to change) |
| `question` | an Ask-First boundary fired or intent is unclear | Answer in one line with `tell.sh`; if it needs the human, ask them and relay |
| `blocked` | cannot proceed (auth, flaky CI, missing access) | Fix what is yours to fix, then `tell.sh <slug> continue`; or `tell.sh <slug> stop` |
| `pr-open` | PR exists, review loop starting | Note the number — but do NOT stop watching. The review loop after it is the LONGEST part of the job, and a builder that stalls there logs nothing, so nothing will wake you. `wait.sh <slug> --for converged` blocks and exits 3 the moment the builder stops working |
| `converged` | pr-watch reports CONVERGED on the current head | Decide: `tell.sh <slug> merge` or `tell.sh <slug> hold` (say why) |
| `merged` / `done` | PR merged, issue closed | Run `/cmux-trash-collector <slug>` |
| `failed` | gave up; reason in the message | `ls.sh <slug>` for the log, `peek.sh` for the screen, decide: respawn with an amended spec, or collect with `--force` |

**You can answer the builder's permission prompts.** A builder in auto mode rarely asks, but one
you launched with `--mode acceptEdits` (or a Haiku builder, which cannot use auto mode) stops at
"Do you want to proceed? 1. Yes 2. No" and does not report anything while it waits, so a builder
that has gone quiet may simply be blocked on a prompt. `peek.sh <slug>` shows it; `approve.sh
<slug>` presses Yes, `approve.sh <slug> --no` presses No, `approve.sh <slug> --watch 600` (run it in the
background) keeps answering Yes until the builder is finished. Read what it is asking before
you approve anything that writes outside the worktree, pushes, or touches a host. The same
`send-key` trick answers any other TUI question (plan approval, `[A]/[E]` menus rendered as
choices): `cmux send --workspace <ws> -- "1"` then `cmux send-key --workspace <ws> enter`.

Rules of the channel:
- Do not sleep-poll (`sleep 45; ls.sh` is blocked by your own harness anyway). Builder messages
  arrive in your prompt; when you genuinely have nothing to do until one does, `wait.sh <slug>`
  blocks until its next interrupting phase and prints it.
- A checkpoint may carry several numbered items; answer them all in ONE `tell.sh` (`1: K 2: A`).
  Two separate tells for one checkpoint cost the builder a re-ask.
- One line per `tell.sh`. Multi-step instructions belong in an amended spec, not in the prompt.
- Do not edit files in the builder's worktree. If the spec was wrong, `tell.sh <slug> E` and describe the amendment, or stop it and respawn.
- Do not give the builder a second goal. Spawn a second builder.
- **Silence has two causes and they look identical in the log: a 20-minute turn, or a builder that is not running at all.** `ls.sh` now reads each builder's screen and prints the real state — `busy` / `idle` / `unsubmitted` / `prompt` / `gone` — because the last logged phase cannot distinguish them (a builder that is not working logs nothing). `unsubmitted` means a line was typed into its prompt and the Enter never landed: `approve.sh <slug>` submits it. On 2026-09-11 all three live builders in one repo sat that way for three hours after reporting `pr-open`, one of them holding the literal `[orchestrator]` line `tell.sh` had typed.
- `tell.sh` now verifies its own submit (clears any stale fragment, re-presses Enter, warns if the line is still sitting there). If it warns, do not re-send — `peek.sh` first, or you will stack two copies of the instruction.
- The ledger is per-REPO: `ls.sh` lists builders belonging to OTHER orchestrator sessions too. A leading `*` marks yours; `--mine` filters. Do not answer or merge another session's builder.
- The human can also open the builder's workspace and type; the ledger log will not see that, so re-read the screen when the story does not add up.

### 5. Merge decision and hand-off

The builder never merges on its own. When it reports `converged`, check `node scripts/pr-watch.js
<N>` yourself if you want a second look (the caveats in CLAUDE.md Rule 5 apply: `CONVERGED` is
not "no open thread"), then `tell.sh <slug> merge`. The builder merges with `--squash --admin`,
confirms the issue closed, and reports `merged` then `done`. Then run `/cmux-trash-collector
<slug>`; it refuses to remove anything unmerged or dirty, so it is safe to run early.

### 6. When it goes wrong

- Builder process died (workspace shows a shell prompt): the worktree and branch are intact. Either `cmux send --workspace <ws> "claude --model opus --permission-mode auto --continue"` to resume the same session in place, or collect with `--force` and respawn.
- You want to stop it: `tell.sh <slug> stop` (it reports `failed` and idles), then collect.
- Two builders needed the same file: that is a split that should have happened at step 1; let the first merge, then `tell.sh <second> "rebase onto origin/main"`.
