# cmux worktree skills: ipmedia-skills vs. the three-skill builder loop

Written 2026-09-11 by Jeff, after reading both codebases end to end.

**What I compared**

- Yours: `meupatrocinio/ipmedia-skills` at `main`, the skills you authored in the worktree
  lifecycle family (`new-worktree`, `new-worktree-build`, `new-worktree-build-auto`,
  `cleanup-worktree`), plus `ticket-autopilot` and `answer-pr-review`, plus
  `assets/tab-handoff.md`.
- Mine: three machine-wide skills in `~/.claude/skills/` (`cmux-orchestrator`, `cmux-builder`,
  `cmux-trash-collector`) plus nine shell scripts they drive.

Both solve the same problem: farm a scoped piece of work out to a fresh Claude in its own git
worktree and its own cmux workspace. We arrived at very different answers, and a few of yours
are straightforwardly better than mine. Where that is the case I say so.

---

## 0. The two systems in one paragraph each

**Yours.** A launcher skill prepares a worktree and fires a new `claude` into it with the task
already in its first prompt, then gets out of the way. `new-worktree` opens an empty one,
`new-worktree-build` opens one already running `/bmad-build`, `new-worktree-build-auto` opens one
running `/bmad-build-auto` with no approval gate. `ticket-autopilot` wraps that into a full
pipeline: triage a Linear ticket, build the worktree, launch a driver session, and the driver
plans, opens a tab to implement, reviews, opens the PR, answers bot rounds, and hands back a
merge-ready PR. `cleanup-worktree` closes the workspace, removes the worktree, and checks the
branch out in the main repo so review continues there.

**Mine.** One long-lived orchestrator session (the one the human is in) writes a small spec,
spawns a builder, and stays in a two-way conversation with it for the whole job. The builder
narrates every phase back into the orchestrator's prompt through a script, halts and asks
instead of deciding whenever the spec's boundaries say so, and merges only when told. A third
skill archives what is worth keeping and destroys the worktree, branch, workspace and ledger.

---

## 1. The one difference everything else follows from: is there a channel back?

This is the fork in the road. Everything below is downstream of it.

**Yours is fire-and-forget at launch, with one report at the end.** The launcher's job ends once
the workspace is created and verified. In `new-worktree-build` and `-auto` there is no return
channel at all: the workflow says so plainly ("Your job ends once the workspace is created,
verified, and reported"). In `ticket-autopilot` there is exactly one message, the driver's
`SendMessage` at D6 carrying the terminal outcome. O4 is explicit that this is a design choice,
not an omission: no polling, no watcher, no timeout, and "if the driver dies without reporting,
this run stalls, accepted."

**Mine is a live two-way channel for the whole job.** The builder calls
`report.sh <phase> "<one line>"` at every transition. Six phases are progress only (sidebar pill
plus a log line) and eight interrupt the orchestrator by typing into its prompt as a user turn:
`checkpoint question blocked pr-open converged merged done failed`. The orchestrator answers with
`tell.sh <slug> "<one line>"`. Everything both ways lands in a per-slug log file, so a message is
never lost even when the orchestrator is mid-turn on something else.

**What each buys.**

Yours buys simplicity and a launcher that cannot become a bottleneck. Nothing to keep alive, no
protocol to keep in sync, no scripts to install. A batch of 25 tickets does not need 25 open
conversations.

Mine buys the ability to answer a question mid-run. When a builder hits an ambiguity it stops and
asks in one line instead of guessing, and a wrong guess in an unattended run is a revert. Your
own `bmad-build-auto` path pays that cost deliberately and your docs are honest about it ("Intent
gap: should halt and report, never guess"), but a halt with nobody listening is a stalled run,
which is the outcome O4 accepts.

Mine also costs more: nine scripts, a ledger file format, a phase vocabulary, and a pile of
recovery rules for when the channel itself breaks (see section 12).

Neither is wrong. They target different situations. Yours is better when the ticket is
well-specified and you want five running at once. Mine is better when the work is ambiguous
enough that you expect two or three questions.

---

## 2. Scripts vs. shell embedded in prose

**Yours has no executables.** Every shell command lives inline in the workflow markdown for the
model to read and adapt. The plugin ships no `bin/`.

**Mine has nine.** `spawn.sh`, `tell.sh`, `peek.sh`, `ls.sh`, `approve.sh`, `wait.sh`, a shared
`lib.sh`, `report.sh` on the builder side, and `collect.sh` for teardown. The skill body is
mostly about when to call them and how to read what comes back.

The cost of yours shows up in one specific place: **the same 14-line ps/lsof launch check is
duplicated verbatim in four files** (`new-worktree`, `new-worktree-build`,
`new-worktree-build-auto`, `cleanup-worktree`), and `ticket-autopilot` points at a fifth copy by
reference. Your own git history is the evidence. Four consecutive commits on 2026-08-28 fix that
block, and each one has to touch all four files:

- `7ca6ed8` make the worktree guards actually detect what they check for
- `0556328` compare physical paths, and carry the literal cwd match to the whole family
- `d4c8f1a` find launched agents that `lsof -c claude` cannot see
- `c4e4211` make the live-agent guard able to say "the check broke"

That is a function that wants to be a function. One `worktree-lib.sh` with `wt_agent_alive()` in
it, sourced by all four, and each of those commits is a one-file change.

The counter-argument for your approach is real and I want to state it fairly: a plugin installed
through a marketplace has no reliable place to put an executable bit, prose survives being read
by a model that decides to adapt it, and a script is one more thing that can be out of date
relative to the doc describing it. If you keep the inline form, the cheap middle ground is to put
the block in one asset file (`assets/agent-alive.md`, next to `tab-handoff.md`) and have the four
workflows say "run the check in `${CLAUDE_PLUGIN_ROOT}/assets/agent-alive.md`". You already use
exactly that pattern for `tab-handoff.md`, so it is consistent with the house style.

---

## 3. Liveness detection: yours answers "is anything alive", mine answers "what is it doing"

Your check is `ps -axo pid=,comm=` filtered on the executable path, then `lsof -a -p <pids> -d cwd`,
matched against the worktree path as a prefix. Three outcomes, and only one clears: a printed path
means live, `CHECK BROKE` means the check could not answer, and no output with exit 1 is the only
clean idle. It fails closed.

Three things in there are correct and I had not written them down anywhere:

1. **`lsof -c claude` misses cmux-launched sessions**, because `-c` matches the kernel's short
   command name, which a session started through `~/.local/bin/claude` does not carry. Your note
   says it saw 2 of 25 live sessions. That is a real finding.
2. **`pgrep -f` is no better**, because cmux passes the path as `--cwd` and it never appears in
   claude's argv.
3. **`pwd -P` vs `pwd`**, because `lsof` reports physical paths and on macOS `/tmp` vs
   `/private/tmp` makes that the common case rather than the exotic one.

I am taking all three.

Where it runs out of road: a cwd match cannot distinguish a session mid-turn from one that
finished twenty minutes ago, cannot see that it stopped on a permission dialog, and cannot see
text sitting typed but unsubmitted in its prompt. For teardown, which is what you use it for,
none of that matters. Any live process under the path is a stop, full stop, and your guard is
correct.

Mine reads the screen instead (`cmux read-screen`) and classifies five states: `busy`, `idle`,
`prompt` (stopped on a permission dialog), `unsubmitted` (a line was typed and the Enter never
landed), `gone`. I needed that because the last logged phase cannot tell them apart: a session
that is not working logs nothing, so silence and a 20-minute turn look identical. On 2026-09-11 I
had three builders sitting idle for about three hours after reporting `pr-open`, one of them
holding the literal line the orchestrator had typed at it. Nothing in the log said anything was
wrong, because nothing was being written.

**You already have both, applied by context, and that is the right call.** `driver.md` D2 says the
cwd recipe is invalid for verifying the implement tab, because the tab and the driver share a cwd
so a match proves only that someone is running there, and tells the driver to use
`cmux read-screen --surface <ref> --lines 40` instead. That distinction is sharper than anything I
wrote before I hit the problem live.

---

## 4. What the launched session is told: a spec vs. the user's own words

This is the place where we actively disagree, and both positions have evidence.

**Yours: pass the task through verbatim, never write a brief.** Stated as a rule, with two
reasons. First, you do not know the task better than the ticket does, and a brief written from
the same ticket only adds a lossy copy that can contradict its source. Second, your phrasing
leaks keywords into a skill that reads them: `bmad-build-auto` reacts to the word **implement**,
so "Implement RND-500 following..." steers the skill through wording the user never chose. You
mark that as an observed failure, not a hypothetical.

**Mine: the orchestrator writes a spec, but only half of it.** The human-owned block is Intent
(problem plus approach, two sentences each) and Boundaries in three lists:

- *Always*: the invariants (tests green, Conventional Commit with the right footer token, the PR
  label, root-cause fixes only).
- *Ask First*: everything that must stop and ask. Always includes merging, any DB migration, any
  change outside the files named in Intent, anything touching prod, and widening scope after a
  review finding.
- *Never*: the non-goals, plus approaches already rejected, named, so the builder does not
  rediscover them.

Code Map, Tasks, Design Notes and Verification are left blank on purpose. Investigating the code
is the builder's job in its own context, not the orchestrator's.

Where your argument lands hardest on mine: I have a hard token budget because of it. The human
block has to stay under about 600 tokens, because the builder's Code Map, Tasks and Verification
have to fit alongside it inside quick-dev's 1600-token proposal. An 1,100-token intent block
leaves the builder choosing between an oversize spec and a split question back to the
orchestrator. I hit that with three builders in a row on one day.

Where my argument lands on yours: the *Never* list has no equivalent in your design. "Do not fix
the adjacent thing you will notice", "we already tried X and it does not work", "do not touch the
migration" are facts that live in the human's head, not in the ticket. Your triage stage (O1)
partly covers this by refusing tickets that are not self-contained, which is a different and
cleaner answer: if the boundaries have to be explained, the ticket is not ready to run
unattended. But it means the boundary knowledge has to be written into the ticket before the run
rather than into a spec at launch time, and in practice tickets do not carry it.

One concrete thing I would take from your side regardless: **spell repo contracts literally**. I
had a spec say "use `--no-ticket` on the commit hook", the builder read it as a CLI flag, and it
cost a red CI job and a force-push. Your "verbatim or nothing" rule makes that class of error
impossible by construction.

---

## 5. Ticket integration: yours is a real system, mine barely exists

Yours is Linear-first and it is the most developed part of the family.

- **A bare ticket id is a complete invocation.** `/ipm:new-worktree-build-auto RND-500` is the
  whole thing.
- **Look for existing work before creating anything**: `git branch -a | grep -i <TICKET>`,
  `git worktree list`, and in `ticket-autopilot` also `gh pr list --state all --search <ticket>`.
  You grep the full ticket id, bounded (`'<ticket>($|[^0-9])'`), so `500` does not match `RND-1500`
  and `RND-525` does not match `RND-5250`. Two worktrees on one ticket is how work gets silently
  done twice.
- **Do not trust the tracker's auto-generated branch name.** It is built from the title, usually
  too long, usually not descriptive of the change.
- **Record the branch back on the ticket** and move it to In Progress, so the ticket is where
  "what is being worked on and where" lives, rather than somebody's memory.
- **Never invent a workflow state.** You read `list_issue_statuses` for the team and map to the
  closest real name.
- **Validate a branch name that came from a ticket comment** against the project convention and
  `^[A-Za-z0-9][A-Za-z0-9._/-]*$` with no `..` segment, because it is free text from an external
  system that later stages interpolate into git commands. That is a genuine injection guard and I
  have nothing like it.
- **Range expansion** (`RND-525 - RND-529`, `..`, `RND-525-529`) capped at 25, because every
  accepted ticket becomes a worktree and a workspace.

Mine: the orchestrator does the GitHub issue comment and column move itself before spawning, and
the builder only puts `Fixes #N` or `Refs #N` in the commit footer. There is no lookup for
existing branches, no reuse, no validation. That is a gap and I know it.

**The triage stage is the part I most want.** O1 spawns a read-only subagent whose job is to
decide whether a ticket can be run unattended at all, and to skip it with a precise reason if not.
Your criteria: feasible only when self-contained, with a concrete problem, scope pointed at or
clearly discoverable, and a clear definition of done. Not feasible when it needs a product or
design decision, copy sign-off, credentials, rollout coordination, or execution against a live
environment. Anything in the project's ask-first areas only when the ticket explicitly scopes
exactly that change. And the tiebreak: "when in doubt, skip with a precise reason, a skipped
ticket costs nothing, a wrong unattended guess costs a revert."

My system has no equivalent. It assumes the human already decided the work is suitable, which is
true when they are sitting there and false the moment anyone tries to batch.

---

## 6. Workspaces, tabs and why your implement step is a tab

Your reason is specific and worth restating because it is not obvious:
`bmad-build-auto`'s implement step mandates subagents, and subagents cannot spawn subagents.
So implementation has to run in a full Claude session, not one level down. That forces the driver
to also be a full session rather than a subagent of the main one, and forces the implement stage
into a **tab** of the driver's workspace via `cmux new-surface`.

You put it in a tab rather than a second workspace so one workspace stays the whole unit of work
for one ticket, and a single `cmux workspace close` tears down everything the ticket created.
That is clean.

Mine puts each builder in its own workspace, and groups every builder of a repo into one pinned
collapsible sidebar folder named after the repo, with the orchestrator's own workspace as the
first item under the header. `--group mine` puts builders in the orchestrator's group instead,
`--group none` leaves them loose. The collector deletes the folder only when nothing but the empty
header is left. Pure ergonomics, no correctness value, but with four builders open it is the
difference between a usable sidebar and a wall.

I have no tab-handoff. Yours (`assets/tab-handoff.md`) is a better-thought-out mechanism than
anything I have: cut a fresh session at the plan boundary so implementation starts with the
approved artifact and the codebase and none of the planner's investigation. Two details I
particularly like:

- **It is opt-in by phrase** (`Hand off to a new tab.`), not automatic on every plan-boundary
  halt. Your reasoning: on a small change the new session just re-reads the same three files and
  nothing was gained, and more importantly, if anything else is dispatching off the same
  `ready-for-dev` signal, an unconditional handoff means the artifact gets implemented twice, in
  parallel, on one branch.
- **The phrase is a no-op where nothing implements it**, so including it is never harmful. That is
  a nice property for a thing that crosses a project boundary.

---

## 7. Permissions and runtime guardrails

**Mine has a permission layer, yours does not.**

- A pre-approved allow-list ships with the builder skill
  (`~/.claude/skills/cmux-builder/builder-settings.json`, passed as `--settings`): report script,
  git, gh, node/npm/npx, cmux, read-only shell allowed; force-push, hard reset, ssh and `rm -rf`
  denied. So routine work never stops on a prompt, and the dangerous things stop even in auto mode.
- `--mode auto|acceptEdits|yolo`. Auto mode needs an Opus-class model; a Haiku builder falls back
  to `acceptEdits` and will therefore stop on prompts.
- `approve.sh <slug>` answers a permission prompt remotely, `--no` presses No, `--watch 600` keeps
  answering Yes in the background until the builder is done. Needed because a builder stopped on
  a dialog reports nothing while it waits, so it looks exactly like one that is working.
- **MCP servers are off by default** (`--strict-mcp-config`). MCP tool descriptions are the
  largest fixed context cost a builder carries, and with a full set loaded an Opus builder
  auto-compacted before its second report. `--mcp full` opts back in when the spec actually needs
  a browser or a project MCP.

Yours launches `claude` with whatever the user's defaults are. Ask-first and high-risk areas are a
*project fact* you read from `CLAUDE.md` or `_bmad/harness.yaml` and feed into triage, so they
gate whether a ticket runs at all rather than what the session may do once running.

That difference is mostly a consequence of section 1: with no channel back, there is nobody to
answer a permission prompt anyway, so a prompt is a stall and the only defense is to not launch
work that would trigger one. Triage is doing the job my allow-list does. Yours is the cheaper
mechanism; mine degrades better when triage was wrong.

**One rule we both landed on independently, phrased better by you.** Your D6: if the session's
own permission layer blocks the merge, do not retry it and do not ask another session to run it,
because "that launders a decision the user has to make." Mine says the same about `--force` in
the trash collector: the refusal goes to the human verbatim and the model never adds the flag on
its own. Same instinct, and your phrasing is the one I will use.

**The MCP cost is worth checking on your side.** `ticket-autopilot` requires the Linear MCP and
runs the whole pipeline in sessions that carry it, and the implement tab inherits the project's
MCP config too. If you have ever seen a driver auto-compact before D4, that is where I would look
first.

---

## 8. Who merges

**Yours: the user.** The run stops at a green PR unless the invocation carries the literal word
`merge`. Three details I am taking outright:

1. **`no merge` counts as the option's absence, never its presence.** Substring-matching `merge`
   would turn an explicit refusal into an irreversible squash merge. Anything not unambiguously
   an opt-in is treated as no-merge, and the report says it was read that way.
2. **Never analyze mergeability.** `mergeStateStatus` is not evidence: on a repo whose maintainer
   merges with admin bypass, `BLOCKED` with zero approving reviews is every PR's steady state and
   carries no information. Do not fetch it, do not reason about branch protection, do not report
   either as a blocker. `state`, `mergedAt` and `gh pr checks` are the only merge-relevant facts.
   I have watched a session spend three rounds trying to satisfy branch protection that was never
   going to be satisfied. This rule prevents exactly that.
3. **`git log origin/main..` is not a merge check.** A squash merge never lands the branch's own
   commits on `origin/main`, so that list stays non-empty after a clean merge. `mergedAt` is the
   only merge evidence. Anyone who has not been bitten by this will be.

**Mine: the orchestrator decides, the builder executes.** The builder never merges on its own.
On `converged` the orchestrator says `merge`, the builder runs `gh pr merge --squash --admin`,
then confirms two things separately: `gh pr view --json state` is MERGED, and if `Fixes` was used,
`gh issue view --json state` is CLOSED. Two mechanisms have closed the wrong issue before, so it
looks rather than assumes.

Your `O4` has the sharper version of the verification rule, though, and it is one I did not have:
**verify the PR by number, not by search.** `gh pr list --search "<TICKET>"` is full text over
titles, bodies and comments, so an unrelated or older PR that merely mentions the ticket reports
MERGED and fires the destructive cleanup against live work. You fall back to `--head <branch>`,
never `--search`. That is a genuinely dangerous failure mode and I had not thought about it.

---

## 9. The review loop

**Yours (`answer-pr-review`) is the most developed piece of writing in either codebase.** Mine
does not have a real equivalent; my builder runs a repo-specific `pr-watch.js` until it prints
`CONVERGED`, fixes every major-and-above at root cause inside the spec's boundaries, acknowledges
sub-major findings without fixing them, replies to each inline finding with its disposition, and
loops.

What yours has that mine does not:

- **An impact bar, with drop as the default.** A finding is worth working only if shipping it
  would plausibly cause wrong behavior or wrong data, data loss, a security or auth or privacy
  hole, a broken contract someone else consumes, a crash or broken build or broken deploy, or a
  test that asserts nothing. Everything else is dropped, and **dropped findings get no reply**.
  "Closing the tab is the correct response, and every reply to a bot invites another round."
- **The second bar: cheap beats impact.** A finding also clears if the fix is one mechanical edit
  with no design judgment and no behavior change, because what the skill rations is the cost of
  arguing and there is nothing to argue about. With the right qualifier: cheap is a property of
  the edit, not of the diff.
- **Never act on an unverified finding.** Bots reason from partial reads and stop one line above
  the part that refutes them, and a finding built on a false premise usually argues for a change
  that reintroduces the bug the branch just fixed. So open the file, read past where the quote
  stops, confirm the premise. A severity label is not evidence, in either direction.
- **Three below-the-bar findings that still earn a fix**, all because they mislead the *next*
  reader: a finding citing the project's own recorded rule (the next agent will read the standard,
  never your decline); a doc or comment that states something false (a bot that misread a comment
  has proven the comment misleads); and a stale doc you used as your own defense (if it says
  something false, the reviewer was right that something is broken, and the fix is the doc).
- **Reconcile the drop list against your own diff.** A finding you dropped but then satisfied
  anyway, through a rename you made for your own reasons or a hoist that fell out of a rewrite,
  was never a considered decline, it was a reflex. Move it to applied and reply, or the report you
  hand back is false. I have never seen anyone write this down before.
- **Findings hide in three places**: inline threads, the review body, and issue comments. Body-only
  findings have no thread to resolve, so nothing tracks their closure, and they are the ones that
  ship broken. Reconcile against the "Prompt for all review comments with AI agents" block.
- **The CodeRabbit rate-limit trap**: a rate-limit warning followed by "Review finished" with zero
  findings means no review ran, and is indistinguishable from a clean review if you only read the
  thread list. Never report that as clean. `ticket-autopilot` D5 carries the same warning and
  makes the subagent report separately whether any reviewer actually reviewed the head it answered.
- **A stop condition that is a choice, not an emergent property.** Every push starts another
  round, so: stop when a round raises nothing above the bar, or when a round only re-raises what
  you already declined, or after two rounds regardless.
- **`maxReviewRounds` nesting is handled.** D5 explicitly tells the subagent to stop after the
  skill's Step 5 and skip Step 6, because otherwise the skill's own wait-and-loop nests inside
  each autopilot round and `maxReviewRounds` bounds nothing. That is the kind of bug that only
  shows up in production and only once.

My only substantive disagreement is that `CONVERGED` from a tool and "no round raised anything
above the bar" are different claims, and I would want the second one written into the PR body so
a human can audit which findings were dropped. You partly do this: the final report carries a
one-line count of drops ("11 nitpicks dropped: naming, comment wording, test-name style"), never
an itemized list and never silence, so the user can ask for one back. That is a good middle.
It just lives in the chat rather than on the PR, where the next person to read the PR is.

---

## 10. Teardown: consolidate vs. destroy

These are genuinely different operations and both should exist.

**Yours (`cleanup-worktree`) consolidates.** Close the cmux workspace, remove the worktree, then
`git checkout <branch>` in the main repo so review and merge continue there. It **keeps the
branch** deliberately, and refuses to delete it without an explicit ask. Three blocking guards,
all fail-closed: worktree dirty, main repo dirty, or any claude process live under the path. No
`--force`, ever, not even offered.

Two details worth calling out:

- **The main checkout is `git worktree list`'s first entry and is never a valid target.**
  `git worktree remove` would refuse it, but `cmux workspace close` runs first and would already
  have closed the user's own workspace. Rejecting it up front is the right order.
- **`cmux workspace close` kills every tab in the workspace**, including a tab-handoff
  implementation session that is still building, and a clean `git status` does not prove the
  worktree is idle because an agent mid-run is simply between writes. That is why guard 3 exists
  and why it is a stop rather than a warning.

**Mine (`cmux-trash-collector`) destroys, after the PR already merged.** It gates on the PR being
`MERGED` and the worktree having no uncommitted changes and no unpushed commits. Then it archives
into the primary checkout under `_bmad/handoff/cmux/archive/<slug>/`: the spec, the full builder
log, the ledger, the commit list, a diffstat, and any deferred-work entries. Then it exits the
builder session, closes the workspace, removes the worktree, deletes the branch, clears the ledger
entry, and drops the sidebar folder if it is now empty. With `--force` it first saves uncommitted
changes to `UNCOMMITTED-DISCARDED.patch` inside the archive, so nothing is lost silently, and
`--force` is a human decision that the model never makes on its own.

Two things mine has that yours might want:

- **The archive.** Deferred-work entries in particular exist in exactly two places after
  teardown: the merged PR body and that archive. If you remove a worktree, whatever the run
  decided not to do vanishes with it.
- **A self-collection guard.** A builder must never run the collector on itself, because the
  collector types `/exit` into the session it is collecting and then closes its workspace, so
  run on itself it kills the session halfway through and leaves the worktree half-removed. The
  skill says this and `collect.sh` also refuses. Your equivalent risk is a driver that decides to
  tidy up its own workspace; `driver.md` D6 does tell it not to ("Do not close this workspace or
  remove this worktree, you live in both"), which covers it in prose.

One thing yours has that mine does not: **the branch survives and lands in the main checkout**.
That is the right shape for your flow, where the human merges. Mine assumes merge already
happened, so there is nothing to consolidate.

---

## 11. Two concrete bugs in mine that your docs caught, now fixed

Reading yours found two real defects in mine. Both are fixed, and both fixes are yours.

**1. Missing `--no-track`.** My `spawn.sh` runs
`git -C "$ROOT" worktree add -q "$WT" -b "$BRANCH" "$BASE"` with `$BASE` defaulting to
`origin/main` and no `--no-track`, so git sets the branch's upstream to `origin/main`. Which is
exactly the condition your gotcha section describes: `git status` reports "Your branch and
'origin/main' have diverged, and have N and M different commits each", and a `git pull` would try
to merge `main` into the feature branch. Your rule pair is the fix and I am adopting it verbatim:
create with `--no-track` so the branch has no upstream at all, and make the first push always
`git push -u origin <branch>` so upstream becomes the branch's own remote ref. Plus the check,
`git for-each-ref --format='%(upstream:short)' refs/heads/<branch>`, and the repair,
`git branch --unset-upstream <branch>`.

Verified before and after in a scratch repo with a real remote: `worktree add -b feat/x
origin/main` leaves upstream `origin/main`, the same command with `--no-track` leaves it empty.
Fixed in `spawn.sh`.

**2. No memory symlink.** Claude Code's file-based memory lives at
`~/.claude/projects/<cwd-slug>/memory/`, keyed by cwd, with no git awareness and no fallback to
the parent repo. A worktree is a different cwd, so my builders have been starting with **zero**
curated memories this whole time, and none of the accumulated house rules reach them. Your step 3
is the fix and it is copy-pasteable. The details that matter and that I would have got wrong:

- Slugification replaces **every** non-alphanumeric character with a dash, not just slashes.
- `pwd -P` before slugifying, because an unexpanded `~` slugifies to a directory that does not
  exist and `mkdir` plus `ln` then succeed in the wrong place.
- A leftover symlink whose target is gone reads as absent to `-e`, and `ln` then fails with
  "File exists", so test `-L` and `! -e` and remove it first.
- Guard on the main checkout actually having a memory directory, because a symlink to a missing
  target makes the worktree session fail on its first memory write.
- The link is two-way, so a memory saved from a worktree is immediately visible everywhere, and
  the one hazard is two worktrees racing on the `MEMORY.md` index line.

The last point in your section is the one I would have missed entirely: a mis-derived slug and a
genuinely absent memory directory **skip identically**, so read the `ls` fallback output and say
the worktree started without memories rather than reporting it as linked. My version prints the
warning to stderr and lists the project dirs that do match the repo name, so the two cases are
distinguishable at a glance.

Fixed in `spawn.sh`, and tested against a fake `HOME` for five cases: no memory dir upstream
(warns, exits 0, does not abort the spawn under `set -e`), link created, rerun is idempotent,
target removed so the link dangles and then heals when it returns, and a memory written from the
worktree side showing up on the main side. One thing your recipe does not cover and mine now
does: the collector removes the link at teardown, guarded on `-L` so it can only ever delete a
symlink, never a real directory and never the shared target. Without that, every collected
builder leaves a dangling entry behind in `~/.claude/projects/`.

I also kept a fallback you do not need and probably should not copy: if the repo itself sits
under a symlink, the logical and physical slugs differ and it is not knowable from the script
which form Claude Code keyed its projects dir on, so mine reads whichever one actually has the
memories and writes the worktree link under both. On both our setups the two forms agree,
because `git rev-parse` hands back a resolved path.

---

## 12. Failure modes each of us documented and the other did not

These are the hard-won ones. Worth trading in both directions.

**Yours, which I am adding:**

- **`--command` and `cmux send` are keystrokes, not exec.** Everything below follows from that,
  and it is the right mental model. On the specific ASCII claim I owe you a correction rather
  than agreement: I tried to reproduce it before adding a guard to my own `tell.sh`, and on
  **cmux 0.64.22 (102)** it does not reproduce on either path. `cmux send` of
  `NONASCII café em—dash arrow→` arrived intact on screen, and a workspace created with
  `--command 'echo "café em—dash arrow→ done"'` ran and printed it correctly. Test method: a
  throwaway workspace running `cat`, then `cmux read-screen`. So either it was fixed upstream
  since you hit it, or it was locale- or version-specific. Worth re-testing on your cmux before
  you keep paying for the rule, because it is an expensive one: it is the reason
  `new-worktree-build` has to refuse a perfectly good task and hand the user a line to type
  themselves. One caveat on my own test: I sent short strings. Do not read this as "`cmux send`
  is reliable", because of the next item.
- **A double quote in the task text has no escape**, because it closes the inner `claude "..."`
  early and the send goes out truncated. Backticks and `$` are the same problem. This one is
  about shell quoting rather than character encoding, so it stands regardless of the ASCII
  result above, and your answer is right: do not rewrite the user's text and do not spill it
  into a brief file, launch a plain `claude` and hand them the line to send themselves.
- **Keystrokes delivered before the shell is ready drop or mangle the leading characters.**
- **Re-send only on the single unambiguous dead-launch outcome** (no output at all, exit 1),
  because a false negative fires a second kickoff inside a session that is already building the
  same task on the same branch. A duplicate kickoff is worse than a launch you check by eye. This
  is the discipline behind the whole `CHECK BROKE` design and it is the part most people would
  skip.
- **The workspace ref must be passed exactly as printed** (`workspace:38`, not a bare `38`, which
  fails with "Workspace index not found").
- **Batched tickets do not see each other's work** unless the earlier PR merged first, because
  each O2 branches from `origin/main` as it fetches it. Stated up front so nobody batches a
  dependent chain by accident.

**Mine, which you may want:**

- **A rate limit kills the turn, and the session cannot report it.** `report.sh` never runs, so
  the orchestrator keeps seeing the last phase and reads it as progress. My builder's rule: coming
  back from a `(429) ... Retry in Ns`, the first action is to report `blocked` with the wait and
  whether the tree is clean. Your D2 watcher partly covers this by polling the spec frontmatter on
  disk, which is the better mechanism (disk is the truth), but your D5 and D6 have no equivalent
  and a rate limit there is invisible.
- **A 429 after a push loses nothing**, so check the tree before assuming work was lost.
- **`cmux send` silently drops text from a LONG message.** Verified on our side on 2026-09-11,
  and independent of character encoding. This is why my orchestrator holds the one-line-per-tell
  rule and why anything multi-step goes into an amended spec rather than the prompt. If your
  handoff contract line for `ticket-autopilot` ever grows (it already carries the ticket, the
  orchestrator session name, `waitMinutes`, `maxReviewRounds`, optionally `model` and `merge`),
  this is the failure I would expect to hit first, and D2's `read-screen` verification is what
  would catch it.
- **cmux ignores flags that arrive through shell variable expansion.** `cmux send $target ...`
  lands on the **caller's own surface**, while the byte-identical literal form lands on the target.
  This cost me a real debugging session. It does not bite you today because your workflows
  interpolate `<ref>` into a literal command line, but it will the moment anyone wraps those calls
  in a script.
- **`ctrl+u` does not clear a Claude TUI prompt.** cmux returns OK and the text stays. So stale
  prompt text concatenates with whatever is typed next. Repeated `backspace` does work, but
  writing that loop requires solving the variable-expansion problem above first.
- **Enter goes missing often enough to matter.** Three builders sat idle for about three hours
  holding typed-but-unsubmitted lines. My `tell.sh` now re-presses Enter up to three times and
  warns loudly if the prompt still holds text. Your D2 has the matching rule for the tab
  (`cmux send` without the `send-key enter` leaves the line typed and never submitted, which reads
  as the same failure on the next screen), so you have half of it.
- **A `$VAR` anywhere in a Bash command defeats a pre-approved allow-list.** Claude Code flags it
  as `simple_expansion` and the session stops on a permission prompt nobody is watching. My
  builder skill tells the model to read the env once and then type literal paths. Only relevant
  if you adopt an allow-list.
- **Context above about 70% means run the handoff skill and report `blocked`**, so the session can
  be resumed in place with `--continue` rather than auto-compacting mid-job.
- **The ledger is per-repo, so a listing shows other sessions' builders too.** A leading `*` marks
  yours. Answering or merging someone else's builder is a real hazard once two people orchestrate
  in the same repo.

---

## 13. Distribution and packaging: yours is a product, mine is a pile of files

Not a small difference.

Yours is a proper Claude Code plugin: `.claude-plugin/plugin.json` with an `ipm` namespace so
skills are `/ipm:new-worktree`, a marketplace entry, a version (0.13.0), install with auto-update
on session start, `userConfig` for the context-window number and the primary reviewer, hooks for
handoff injection and a context reminder, `RELEASING.md`, and three test scripts
(`plugin-smoke.sh`, `validate-skills.sh`, `docker-install.sh`). A new machine gets the whole
family with one install.

Mine is nine files in `~/.claude/skills/` on one Mac, no version, no tests, no install path. There
is a `PORTING.md` explaining how to stand it up elsewhere, but that is a document, not a package.
Yours is better and there is no argument to have.

**On the `SKILL.md` pointer pattern, I have to walk back something I nearly claimed.** My first
draft said your 8-line `SKILL.md` plus a separate `workflow.md` saves context at session start,
and that my 9KB to 13KB bodies were being loaded in every session. That is not how it works. The
Claude Code docs are explicit: "a skill's body loads only when it's used, so long reference
material costs almost nothing until you need it", and the frontmatter table lists the default as
"description always in context, full skill loads when invoked". So at session start we both pay
for descriptions only, and the split buys nothing there.

Where the split does pay is when the body can be loaded in **parts**, and `ticket-autopilot` is
the real example: a driver reads `workflow.md` plus `driver.md` and never loads `orchestrator.md`,
and vice versa. That is close to half the body avoided per role, and it matters because the docs
also say content "stays in context across turns" once loaded, so it is a recurring cost for the
rest of that session rather than a one-off. Splitting a body that every invocation reads end to
end, which is what my builder skill is, saves nothing and adds a file read.

What I am copying is narrower, then: the role split, not the pointer. And your **descriptions**,
which genuinely do more work than mine. They carry the `REQUIRES CMUX (macOS) AND BMAD` prefix,
the trigger phrases, and an explicit "Do NOT use when" list, so the routing decision gets made
from the one part that is always resident.

---

## 14. Short version

**Things of yours I am taking, in order of how much they are worth:**

1. The memory symlink, whole (section 11.2). My builders have been running without house rules.
2. `--no-track` plus first-push `-u` (section 11.1). Straight bug fix.
3. Nothing, on the ASCII rule. I went to add the guard, could not reproduce the failure on
   cmux 0.64.22, and left `tell.sh` alone. See section 12.
4. The **role split** inside a skill body (`ticket-autopilot`'s driver.md / orchestrator.md), so
   each role loads only its half. Not the `SKILL.md` pointer itself, which I wrongly thought
   saved session-start context and does not (section 13).
5. The triage stage: decide whether work can run unattended at all, and skip with a reason
   (section 5).
6. `answer-pr-review`'s impact bar, the drop-with-no-reply default, the three below-bar
   exceptions, and the reconcile-your-drop-list-against-your-own-diff rule (section 9).
7. Verify the PR by number, never by `--search` (section 8).
8. `mergedAt` is the only merge evidence, and never analyze `mergeStateStatus` (section 8).
9. The `lsof -c claude` and `pgrep -f` findings, and `pwd -P` (section 3).
10. Ticket-comment branch names validated against a regex before they touch a git command
    (section 5).

**Things of mine you might want:**

1. A single shared implementation of the live-agent check instead of four copies (section 2).
2. Screen-state classification (`busy` / `idle` / `prompt` / `unsubmitted` / `gone`) for the
   places where "is anything alive" is not a specific enough answer (section 3).
3. An archive step at teardown, mainly so deferred-work entries survive the worktree (section 10).
4. The rate-limit blind spot: a 429 kills the turn before any report can be sent, so D5 and D6
   have no way to say they are stuck (section 12).
5. Turning MCP servers off for launched sessions unless the task needs them, if you have seen a
   driver compact early (section 7).
6. The cmux flags-through-variable-expansion trap, before you ever wrap those calls in a script
   (section 12).

**Where we disagree and I do not think either of us is wrong:** whether the launcher writes a
spec. Your verbatim rule prevents a whole class of error that I have actually hit, and my
boundaries block carries knowledge that tickets usually do not. The honest synthesis is probably
yours plus a *Never* list, and I would be interested in what you think that would look like.
