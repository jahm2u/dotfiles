# The cmux builder system — how it works, and what it takes to run it in another project

Written 2026-09-10 from the live implementation in `~/.claude/skills/`.
Audience: an agent or human standing this up in a repo that does not have it yet.

---

## 1. What it is

One long-lived Claude session (the **orchestrator**, the one the human talks to) farms a single
scoped change out to a fresh Claude session (the **builder**) that runs in its own git worktree
and its own terminal. The builder does the whole job — plan, implement, test, PR, review loop —
and narrates every phase back into the orchestrator's prompt. The orchestrator answers questions,
decides when to merge, and then runs a **trash collector** that archives what is worth keeping
and destroys the worktree, branch, terminal and ledger.

Three skills, one loop:

| Role | Skill | Runs in |
|---|---|---|
| Orchestrator | `cmux-orchestrator` | the human's session |
| Builder | `cmux-builder` | a new cmux tab/workspace, cwd = the worktree |
| Trash collector | `cmux-trash-collector` | the orchestrator's session, after merge |

The skills are **machine-wide** (`~/.claude/skills/`), so they are already available in every
repo on this Mac. Nothing needs to be copied per project. What each project must supply is
listed in §10.

---

## 2. Physical layout

```
~/.claude/skills/
├── cmux-orchestrator/
│   ├── SKILL.md                 # 170 lines: the orchestrator's procedure
│   └── scripts/
│       ├── lib.sh               # 168 lines: shared helpers, sourced by all three skills
│       ├── spawn.sh             # 194 lines: worktree + tab + ledger + claude process
│       ├── tell.sh              # type one line into the builder's prompt
│       ├── peek.sh              # read the builder's screen
│       ├── ls.sh                # list builders / dump one builder's log
│       ├── approve.sh           # answer the builder's permission prompt (Yes/No/--watch)
│       └── wait.sh              # block until the builder's next interrupting phase
├── cmux-builder/
│   ├── SKILL.md                 # 121 lines: the builder's procedure
│   ├── builder-settings.json    # the builder's pre-approved allow/deny list
│   └── scripts/report.sh        # the builder's ONLY channel back
└── cmux-trash-collector/
    ├── SKILL.md                 # 39 lines
    └── scripts/collect.sh       # 114 lines: gates, harvest, destroy
```

Per-repo state (gitignored) lives in the **primary checkout**, resolved from
`git rev-parse --git-common-dir` so it is found identically from inside any worktree:

```
<primary>/_bmad/handoff/cmux/
├── <slug>.env       # the ledger: KEY=VALUE
├── <slug>.log       # append-only, "<iso8601>|<phase>|<message>"
└── archive/<slug>/  # what the collector keeps
```

---

## 3. The ledger — the whole protocol in one file

`spawn.sh` writes it, `report.sh` and `collect.sh` mutate it, every other script reads it.

```
BF_SLUG=3403-lone-offer-weight     # identity; names branch, worktree, spec, tab, status pill
BF_ISSUE=3403                      # optional GitHub issue
BF_BRANCH=fix/3403-lone-offer-weight
BF_WORKTREE=/abs/path/.claude/worktrees/wt-<slug>
BF_SPEC=<worktree>/_bmad-output/implementation-artifacts/spec-<slug>.md
BF_ORCH_WS=workspace:16            # where the builder types its reports
BF_MODEL=opus[1m]
BF_MODE=auto
BF_MCP=none
BF_STATUS=implementing             # last phase reported
BF_PR=1712                         # scraped out of the first message naming "PR #N"
BF_CREATED=2026-09-10T14:02:11Z
BF_BUILDER_WS=workspace:16         # in tab mode this is the HOST (orchestrator) workspace
BF_BUILDER_SURFACE=surface:41      # set only in tab mode
BF_GROUP=workspace_group:3         # set only in workspace mode
```

The builder gets `BF_SLUG BF_LEDGER BF_ORCH_WS BF_WORKTREE BF_SPEC BF_BRANCH BF_ISSUE` in its
process environment; `report.sh` re-sources the ledger file for the rest.

**Addressing indirection.** A builder is either a *tab* (surface) inside the orchestrator's own
workspace (the default) or a *workspace* of its own. `lib.sh` hides the difference behind
`bf_target()` (emits `--workspace X [--surface Y]`), `bf_builder_alive()` and
`bf_say_to_builder()`, so ledgers written before tab mode existed still work. Port this
indirection, not the two shapes.

---

## 4. The phase protocol

`report.sh <phase> "<one line>" [--ping]` is the builder's only channel. Phases are a closed set,
split by whether they interrupt the human's session:

| Class | Phases | Effect |
|---|---|---|
| Progress | `started planning implementing testing review-round pushing` | ledger + log + sidebar pill only |
| Interrupting | `checkpoint question blocked pr-open converged merged done failed` | all of the above **plus** a macOS notification and the line typed into the orchestrator's prompt |

`--ping` promotes any phase to interrupting. Every call also: sets `BF_STATUS`, appends to the
log, recolors the `bf-<slug>` status pill on the orchestrator's workspace (red for
failed/blocked, amber for checkpoint/question, green for done/merged/converged), and writes a
line into the builder's own activity log.

The interrupt arrives in the orchestrator's prompt as a user turn shaped:

```
[builder <slug>] checkpoint: (1) split or keep the migration? [S]/[K]; (2) plan ready [A]/[E]
```

The orchestrator answers with `tell.sh <slug> "1: K 2: A"`, which arrives in the builder's prompt
as `[orchestrator] 1: K 2: A`. **The rule that makes the channel cheap: one round-trip per halt.**
The builder gathers everything quick-dev wants answered into one numbered checkpoint; the
orchestrator answers all items in one `tell.sh`. Two tells for one checkpoint cost a re-ask.

Because everything is also appended to the log, a message is never lost even if the orchestrator
is mid-turn, `/clear`ed, or gone.

---

## 5. Transport: exactly which cmux verbs are used

This is the part that is not portable to another multiplexer without work. The full surface:

| Verb | Used for |
|---|---|
| `cmux identify --json` | who am I — `.caller.workspace_ref`; also the precondition check |
| `cmux new-surface --type terminal --workspace W --working-directory D` | create the builder's tab |
| `cmux new-workspace --name --cwd --env --command` | create a builder as its own workspace (`--place workspace`) |
| `cmux send [--workspace W] [--surface S] -- "text"` | type into a prompt |
| `cmux send-key ... enter` | submit it |
| `cmux read-screen ... --lines N` | `peek.sh`, and prompt detection in `approve.sh` |
| `cmux list-workspaces` / `list-pane-surfaces` | liveness checks |
| `cmux close-surface` / `close-workspace` | teardown |
| `cmux tab-action --action rename\|pin` | name the tab `🔨 <slug>`, keep the orchestrator's tab first |
| `cmux set-status <key> <text> --icon --color --priority` / `clear-status` | the `bf-<slug>` sidebar pill |
| `cmux notify --title --body` | macOS notification on interrupting phases |
| `cmux log --level --source` | per-workspace activity feed |
| `cmux workspace-group create/add/list/pin/set-icon/set-color/delete` | the sidebar folder |

Two non-obvious mechanics, both learned the hard way and both load-bearing:

1. **Send, sleep, then Enter — and then VERIFY.** A trailing `\n` inside `send` is treated by
   the TUI as paste-with-newline and does not reliably submit, so it is two steps. But the
   Enter itself goes missing often enough to matter: on 2026-09-11 all three live builders in
   one repo had been idle ~3h holding a typed-but-unsubmitted line, one of them the literal
   orchestrator message the tell script had typed. Nothing noticed, because a builder that is
   not working logs nothing. The send helper therefore clears any stale fragment first
   (otherwise new text CONCATENATES onto it), then re-reads the prompt and re-presses Enter up
   to 3 times before failing loudly.
2. **A terminal surface takes text, not a `--command`.** Unlike `new-workspace`, `new-surface`
   has no `--env` and no `--command`, so tab mode inlines the `BF_*` assignments as a shell
   prefix in front of the `claude` invocation, quoted, and types the whole line.

---

## 6. Spawn, step by step

```bash
spawn.sh --slug <kebab> --spec <abs-path.md> [--issue N] \
         [--base origin/main] [--model 'opus[1m]'] [--mode auto|acceptEdits|yolo] \
         [--place tab|workspace] [--group repo|mine|none] [--mcp none|full] \
         [--focus] [--spec-dir _bmad-output/implementation-artifacts]
```

1. Validates: kebab slug, spec exists (absolute, or retried against the primary checkout), spec
   has `status:` frontmatter, **no ledger / branch / worktree path already exists for this slug**
   (idempotence guard — the collector must run before a slug is reused).
2. `git fetch origin`, then `git worktree add <root>/.claude/worktrees/wt-<slug> -b <branch> --no-track <base>`.
   `--no-track` is load-bearing: without it the branch's upstream becomes `origin/main` and every
   `git status` in the worktree reports a bogus "diverged from origin/main". The builder's first
   push is `git push -u origin <branch>`, which sets the correct upstream.
   Branch is `fix/<issue>-<slug>` — or `fix/<slug>` when the slug already leads with the issue
   number, so you never get `fix/71-71-foo` — or `feat/<slug>` with no issue.
3. Symlinks `node_modules` (and `admin-app/node_modules`) from the primary checkout into the
   worktree, so the builder does not reinstall. **Repo-specific; see §10.**
3b. Symlinks `~/.claude/projects/<worktree-slug>/memory` to the primary checkout's memory
   directory. Claude Code keys file-based memory on the **cwd** with no git awareness, so a
   worktree is a different project and without this the builder starts with zero curated
   memories. The slug replaces every non-alphanumeric character with a dash. Two-way: a memory
   the builder saves is visible everywhere. If the primary checkout has no memory directory,
   spawn warns and says the builder started without memories rather than failing silently.
   The collector removes the link (and only the link) at teardown.
4. Copies the spec into the worktree at `<spec-dir>/spec-<slug>.md`.
5. Writes the ledger.
6. Launches:
   `claude --model '<model>' <mode-flag> --settings ~/.claude/skills/cmux-builder/builder-settings.json [--strict-mcp-config] -- '/cmux-builder'`
7. Places it in the sidebar (tab: rename + pin the orchestrator's tab first; workspace: join the
   `🔨 <repo> builders` group).
8. Best-effort: if the orchestrator's cwd looks like `Baba{F,f}low-<ORG>`, records the spawn in
   that org's babysit-chat sidecar. **Repo-specific; harmless elsewhere.**
9. Sets the orchestrator's `bf-<slug>` pill to `spawned` and prints the builder ref last.

Within ~30s the builder should report `started`. If it does not, `peek.sh <slug> 60` — it is a
login prompt, a trust dialog, or a missing skill.

---

## 7. Placement and the sidebar folder

cmux groups are **flat**: a group's members are workspaces, and a group cannot contain another
group. So a builder given its own workspace can only sit *beside* its orchestrator, never under
it. That is why the default is `--place tab`: the builder becomes a tab inside the orchestrator's
own workspace row, which is the nesting the sidebar cannot otherwise express.

`--place workspace` keeps the older shape and then uses groups: one pinned, collapsible group per
repo named `🔨 <repo> builders`, created from the orchestrator's workspace so cmux's empty anchor
terminal becomes the folder header, the orchestrator is the first child, builders append below.
`--group mine` reuses the orchestrator's existing group; `--group none` skips it. The collector
keeps the folder while the orchestrator is in it and deletes it only when nothing but the empty
anchor remains.

**Tab-mode trap encoded in the scripts:** in tab mode `BF_BUILDER_WS` is the *host* workspace
(the orchestrator's). `collect.sh` therefore closes the *surface*, never the workspace — closing
`BF_BUILDER_WS` there would close the human's own session.

---

## 8. Permissions, model, MCP

- **Model** defaults to `opus[1m]` (Opus 5, 1M window; bare `opus` is the standard window).
  Auto permission mode is Opus-class only; a Haiku builder falls back to `--mode acceptEdits` and
  will stop on prompts.
- **Modes**: `auto` (default) · `acceptEdits` · `yolo` → `--dangerously-skip-permissions`, for a
  trusted spec in an isolated worktree.
- **`builder-settings.json`** is passed with `--settings` in *every* mode, so routine tooling
  never prompts: allow Read/Edit/Write/Glob/Grep/Skill, `report.sh` by both literal paths,
  `git gh node npm npx cmux python3` and read-only shell (`ls cat head tail grep find wc sed diff
  echo env cd pwd`), plus assignment forms like `BEFORE=*`. Deny: `git push --force*`,
  `git push -f`, force-push to main, `git reset --hard`, `git checkout/switch main`, `ssh`,
  `rm -rf`, and the prod SSH wrapper.
- **No MCP servers by default** (`--strict-mcp-config`). MCP tool descriptions are the builder's
  largest fixed per-turn cost — in BabaFlow the project MCP alone is ~78k tokens/turn: a Haiku
  builder started at 86% context and an Opus builder auto-compacted before its second report.
  `--mcp full` opts back in when the spec genuinely needs a browser or a project MCP, and the
  spec should say so.

---

## 9. The four contracts

### 9.1 Spec contract (orchestrator → builder)

The orchestrator writes **only the human-owned frozen half** of the project's quick-dev spec
template (`.claude/skills/bmad-quick-dev/spec-template.md`):

- frontmatter: `title`, `type`, `created`, `status`, `context:`
- **Intent**: Problem + Approach, two sentences each; the observed symptom, not an unverified
  theory of the cause
- **Boundaries & Constraints** — the size control:
  - *Always*: invariants (tests green, Conventional Commit with `Fixes #N`/`Refs #N`, the PR
    label, root-cause fixes only) — **spelled out literally**, exact token, exact label name
  - *Ask First*: merging, DB migrations, anything outside the named files/subsystem, prod/SSH,
    widening scope after a review finding
  - *Never*: non-goals, and approaches already rejected — named, so the builder does not
    rediscover them
- **I/O & Edge-Case Matrix** when there are observable inputs/outputs; delete it otherwise

Code Map, Tasks, Design Notes and Verification are left empty: investigating the code is the
builder's job in its own context. `status: draft` makes quick-dev plan and halt at
`[A] Approve | [E] Edit`; `status: ready-for-dev` skips straight to implementation.

**Budget: the frozen block stays under ~600 tokens.** The builder's Code Map + Tasks +
Verification must fit alongside it inside quick-dev's ~1600-token proposal. A 1,100-token intent
block forces the builder to choose between an oversized spec and a split question — all three
AjudaDuda builders on 2026-09-07 hit exactly that. A spec that will not fit is a sign the goal
is not single.

**One builder = one single-goal spec** — one PR's worth. Two independently shippable
deliverables = two specs and two builders. You never hand a builder a second goal later.

### 9.2 Supervision contract (builder → orchestrator)

| Phase | Meaning | Orchestrator does |
|---|---|---|
| `checkpoint` | quick-dev waiting on `[A]/[E]/[S]/[K]` | read the spec, `tell.sh <slug> A` (all items in one line) |
| `question` | Ask-First boundary fired, or intent unclear | one-line answer; escalate to the human if needed |
| `blocked` | auth, flaky CI, missing access, context ~70% | fix what is yours, `tell.sh continue`, or `stop` |
| `pr-open` | PR exists, review loop starting | note the number |
| `converged` | review converged on the current head | `tell.sh merge` or `tell.sh hold` (say why) |
| `merged` / `done` | merged, issue closed | run the trash collector |
| `failed` | gave up | `ls.sh` for the log, `peek.sh` for the screen; respawn or collect `--force` |

Rules of the channel: no sleep-polling (use `wait.sh`, which blocks on the log); one line per
`tell.sh`; never edit files in the builder's worktree (amend the spec with `E`, or stop and
respawn); never give a second goal; `peek.sh` before assuming a quiet builder is stuck — a
non-auto builder may be sitting on a permission prompt that `approve.sh` can answer. A builder
in `--mode acceptEdits` reports *nothing* while it waits on a prompt, which is the main way a
run looks dead when it is not.

### 9.3 Ship contract (builder → the repo)

Commit with `git commit -F -` and a quoted heredoc; footer `Fixes #N` / `Refs #N`. Gate every
commit on HEAD having moved (a commit hook can reject silently). Run the repo's own commit-message
validator locally before the first push — a red validate job costs an amend plus a force-push.
Push with `--no-verify` and a 300s timeout (CI is the gate). Open the PR against `main`, label it
with the repo's hands-off label. Report `pr-open "PR #<N> …"` — the literal `PR #<N>` is how the
ledger learns the number.

Then the review loop: `node scripts/pr-watch.js <N> --wait`, one `review-round` report per round,
fix every major+ at the root cause **inside the spec's boundaries**, reply to each inline finding
with its disposition, push, repeat. A major that requires leaving the boundaries is a `question`.
`CONFLICTING` → merge `origin/main` in. On `CONVERGED` for the current head: report and **wait**.
The builder never merges on its own; `[orchestrator] merge` → `gh pr merge --squash --admin`,
then *verify* the PR is MERGED and the issue CLOSED before reporting `merged` and `done`.

### 9.4 Retirement contract (collector)

`collect.sh <slug> [--force] [--keep-branch]`:

1. **Gates** — refuses unless the PR is `MERGED` (looked up by ledger number, else by branch) and
   the worktree has no uncommitted changes and no unpushed commits. It prints exactly why and
   removes nothing. `--force` is a human decision, never the agent's; uncommitted work is saved
   to `UNCOMMITTED-DISCARDED.patch` in the archive first, so nothing vanishes silently.
2. **Harvest** → `_bmad/handoff/cmux/archive/<slug>/`: the spec(s), `deferred-work.md`,
   `commits.txt`, `diffstat.txt`, the builder log, and finally the ledger. The spec is also
   copied into the primary checkout's implementation-artifacts if not already there.
3. **Teardown**: types `/exit` into the builder, closes the surface (or the workspace), drops the
   sidebar group if only the anchor is left.
4. `git worktree remove` + `worktree prune`; `git branch -D` (squash-merged branches need `-D`);
   deletes the remote branch unless `--keep-branch`.
5. Clears the pill, moves the ledger into the archive, prints `DONE: <slug> collected`.

It never merges, never closes an issue, never pushes anything but a branch delete after a
confirmed merge, never touches another slug, and never cleans up `.claude/worktrees/` entries it
has no ledger for — those belong to other sessions.

---

## 10. What is repo-specific — the actual porting work

The skills are machine-wide and already active in every repo. What a project must provide, and
what currently assumes BabaFlow:

| Dependency | Status | What to do in the new project |
|---|---|---|
| `.claude/skills/bmad-quick-dev/` + `spec-template.md` | **required** — the builder invokes it and the spec is the contract | present in ajudaduda, dgx, fleetbots, homelab, jonas; add it if missing |
| `scripts/pr-watch.js` | **BabaFlow-only** (verified: exists in no other repo) | either port pr-watch, or amend §3 of the builder skill to the project's own convergence check (`gh pr checks --watch` + a reviewer convention). Without it the review loop has no terminal verdict |
| An automated PR reviewer | BabaFlow has one on CT 210 | without a reviewer, "converged" degenerates to "CI green"; decide what `converged` means in this repo and say so in the spec's *Always* |
| `CLAUDE.md` Rules 2/5/9/11/20 | referenced by number from the skills | BabaFlow numbering: 2 = `--no-verify` allowed, CI is the gate · 5 = ship to a PR, review happens there · 9 = never discard uncommitted work without asking · 11 = track work on GitHub issues · 20 = two kinds of worktree, neither may hold `main`. Either mirror these rules in the new repo's CLAUDE.md or replace the citations with the local equivalents |
| `bot:hands-off` label | fallback in the builder skill | name the repo's own label in CLAUDE.md; the builder is told never to improvise one |
| `node_modules` + `admin-app/node_modules` symlinks | hardcoded in spawn.sh step 3 | harmless where the dirs do not exist (guarded by `[ -d ]`); add the project's own heavy dirs (`.venv`, `vendor`, `target`) if worktrees need them |
| `_bmad-output/implementation-artifacts/` | default `--spec-dir` | create it, or pass `--spec-dir` |
| `_bmad/handoff/cmux/` gitignored | **required** — ledgers and logs must not be committed | add `_bmad/handoff/cmux/` to `.gitignore`. *(Not yet present in homelab.)* |
| babysit-chat org sidecar hook | BabaFlow org chats only | inert elsewhere; leave it |
| `main` as the base branch | hardcoded default | `--base` covers other bases; `gh pr create --base main` in the builder skill would need editing for a repo whose trunk is not `main` |
| `gh` auth + `git fetch origin` | required preconditions | check before the first spawn |
| Running inside cmux | required | the orchestrator cannot receive reports in a plain terminal; `cmux identify --json` is the check |

---

## 11. The landmines these scripts encode

Each of these cost a real incident and is now written into the skills — keep them when porting.

- **Literal paths, never `$VAR`, in builder Bash.** A `$VAR` anywhere in the command
  (`$R`, `cd "$BF_WORKTREE"`) makes Claude Code classify it "simple_expansion", which defeats the
  pre-approved allow-list; the builder then stops on a prompt nobody is watching. The builder
  reads `env | grep '^BF_'` once and types the values out.
- **Prefix every git/test command with `cd <literal worktree path> &&`.** A wrong-tree run is the
  most expensive mistake available to a builder.
- **The builder reads the spec literally.** "use `--no-ticket` on the commit hook" was read as a
  CLI flag and cost a red CI job plus a force-push. Spell out repo contracts exactly.
- **Spec-size flag is a proposal, not a gate.** When quick-dev's only complaint is size and the
  spec is still one goal, the builder mentions the count in its checkpoint and moves on instead
  of burning a round-trip.
- **`send` then `sleep` then `send-key enter`** (§5).
- **Tab mode: `BF_BUILDER_WS` is the host workspace** — close the surface, not the workspace (§7).
- **Squash-merged branches need `git branch -D`**, not `-d`.
- **`--no-track` on `git worktree add`.** Without it the branch's upstream is `origin/main`, so
  the worktree's `git status` permanently claims it has "diverged from origin/main" and a
  `git pull` there would merge main INTO the feature branch. The builder's first push is
  `git push -u origin <branch>`, which sets the real upstream.
- **A worktree is a different cwd, so it is a different Claude Code project.** Memory is keyed on
  the cwd with no git awareness, so a builder gets zero curated memories unless spawn symlinks
  them in. A missing memory dir and a mis-derived slug look identical, so spawn warns loudly and
  lists what it did find rather than skipping in silence.
- **`[ test ] && cmd` as the LAST statement of a loop body aborts the script under `set -e`**,
  because the loop's exit status becomes the failed test's. It survives in some nesting contexts
  and not others, which is worse than failing consistently: the memory block passed four test
  cases and only aborted on the fifth. Write `if [ test ]; then cmd; fi` in these scripts.
- **Two mechanisms have closed the wrong issues**, so the builder verifies PR state *and* issue
  state after merging rather than trusting `Fixes #N`.
- **MCP servers are the builder's biggest fixed context cost** (§8).
- **Quick-dev's one-shot and step-05 endings say "offer to push" and HALT** — the builder is past
  the human there and continues to §2 of its skill instead of halting.
- **Context at ~70%**: the builder runs the `handoff` skill and reports `blocked`; the
  orchestrator can resume it in place with `claude --continue` typed into its terminal.

---

## 12. Minimal checklist to enable this in a new repo

1. `.claude/skills/bmad-quick-dev/` present, with `spec-template.md`.
2. `echo '_bmad/handoff/cmux/' >> .gitignore` and commit.
3. `mkdir -p _bmad-output/implementation-artifacts`.
4. CLAUDE.md states: the PR label, the commit-footer convention, the trunk branch, the
   convergence check the builder should use, and the worktree rule.
5. A convergence check that exists in *this* repo — port `pr-watch.js` or name the substitute.
6. `gh auth status` green; `git fetch origin` works.
7. Open the orchestrator session inside cmux; `cmux identify --json` prints a workspace ref.
8. Dry run: spawn a trivial slug (a doc typo fix), watch `started → planning → checkpoint`,
   answer `A`, let it PR, `tell.sh merge`, then collect. That exercises every contract in one
   ~15-minute pass.
