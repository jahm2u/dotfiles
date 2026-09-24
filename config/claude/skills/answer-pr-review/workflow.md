# IPM Answer PR Review — Workflow

**Goal:** Land the findings that would have hurt in production, and get off the PR. Everything else is churn.

A review comment is a *claim*, not a work order. The deliverable is a correct branch shipped quickly, not a high acceptance rate and not a wall of resolved threads. Most bot findings are not worth the round-trip they cost; the skill is knowing which few are.

## The two rules that matter

**1. Only work findings that clear the impact bar.** Read every finding, act on the ones with real consequences, and let the rest die unanswered. Time spent arguing with a nitpick is time the PR is not merged.

**2. Never act on a finding you have not verified against the current code.**

Automated reviewers reason from partial reads. They quote a construct and stop one line above the part that refutes them. A finding built on a false premise usually argues for a change that reintroduces the bug the branch just fixed.

So: open the file it cites, read the construct end to end — *past where the quote stops* — and confirm the premise before you touch anything. A severity label is not evidence. "Major" from a bot means nothing until you have read the code yourself — and neither does "nitpick": a bot's own severity label is a starting guess, not the triage.

## Step 1 — Fetch everything

Findings hide in three places. Sweeping only the inline threads is the most common way a real finding ships unaddressed.

```bash
PR=<number>; REPO=<owner/repo>
gh api --paginate repos/$REPO/pulls/$PR/reviews  --jq '.[] | "\n### REVIEW BODY by \(.user.login) [\(.submitted_at)] head \(.commit_id[0:7])\n\(.body)"'
gh api --paginate repos/$REPO/pulls/$PR/comments --jq '.[] | "\n### INLINE by \(.user.login) on \(.path):\(.line // .original_line) [id \(.id)] [\(.created_at)]\n\(.body)"'
gh api --paginate repos/$REPO/issues/$PR/comments --jq '.[] | "\n### ISSUE COMMENT by \(.user.login) [\(.created_at), edited \(.updated_at)]\n\(.body)"'
```

For anything large, redirect to the scratchpad and Read it — do not let a pipe truncate a finding.

Body-only findings have **no thread to resolve**, so nothing tracks their closure. They are the ones that ship broken. The "Prompt for all review comments with AI agents" block is a compact worklist of every finding the bot raised — reconcile it against the inline threads so that nothing reaches Step 2 unseen.

Fetching is cheap and complete; *acting* is what the bar rations. Read everything, then triage.

Capture each inline comment's `id`; you need it to reply in-thread.

## Step 2 — Triage: does it clear the bar?

Sort every finding into **worth working** or **drop** *before* you start reading code end to end. Verification is expensive; spend it on the shortlist.

### The bar

A finding is **worth working** if letting it ship would plausibly cause one of these:

- Wrong behavior or wrong data for a user — a bad branch, an off-by-one, a race, a non-idempotent handler that double-credits.
- Data loss, corruption, or an unrecoverable state.
- A security, auth, privacy, or consent hole — including a fail-open where the project's rules demand fail-closed.
- A broken contract someone else consumes — an event payload, a DTO field, an API shape, a migration, a config/flag that ships unset in a deployed env.
- A crash, a boot failure, a broken build, a broken deploy.
- A test that asserts nothing, or that would pass with the bug reintroduced.

A finding also clears the bar, whatever its impact, when **the fix is cheaper than the decision**: one mechanical edit, no design judgment, no behavior change, caught by gates you were going to run anyway. A rename, a hoist, a wording fix. What this skill rations is the cost of *arguing*; for these there is nothing to argue about, and applying is faster than triaging. Cheap is a property of the edit, not of the diff — a one-liner that changes behavior, or that you would have to think about to get right, is not cheap and goes back to the impact test.

Everything else is **drop** by default. The usual population: formatting, import order, "consider extracting this helper", type narrowing with no runtime effect, defensive guards for states that cannot occur, micro-optimizations off the hot path, suggestions to add tests for code paths already covered, and restatements of a design choice as if it were a defect.

### Promoting a drop

A finding below both bars earns action only when you can name the concrete value it adds, in one sentence, to someone other than the reviewer. "It would be cleaner" is not that sentence. "This name says the opposite of what the function does and the next reader will use it wrong" is.

When you are hesitating, cost breaks the tie, not impact. Hesitation over a one-edit fix means apply and move on — the deliberation has already cost more than the fix would. Hesitation over anything needing thought means drop.

Three below-the-bar findings that do earn a fix, because all three mislead the *next* reader rather than the current one:

- **A finding citing the project's own recorded rule** — CodeRabbit's `Source: Learnings` or "As per coding guidelines", a `CLAUDE.md` line, an established convention in the surrounding code. This is not the reviewer's taste; it is the repo's standard, and the next agent will read the standard, never your decline. Confirm the rule exists and actually applies — bots do misattribute — then follow it, or change the rule. Do not leave the code and its documented convention disagreeing.
- **A doc or comment that states something false.** A bot that misreads a comment has proven the comment misleads. Fix the comment, decline the code change.
- **A stale doc used as your own defense.** If you decline by pointing at a comment or doc, re-read it. If it says something false, the reviewer was right that *something* is broken — the fix is the doc.

### For everything that clears the bar

Now read the cited code end to end, then sort:

- **Apply** — premise verified, the defect is real. Fix it.
- **Decline** — premise false, or the behavior is deliberate. Requires `file:line` evidence in the reply. Never apply a softened version of a finding you believe is wrong. Check first whether the behavior was chosen on purpose earlier (a spec, a prior answer, a ticket); if it was, cite the decision rather than relitigating it silently.
- **Defer** — real, above the bar, but genuinely out of this PR's scope. Record it wherever the project tracks deferred work and say so in the reply. Do not use Defer as a polite Drop — a dropped nitpick goes nowhere, not onto a backlog nobody will read.

## Step 3 — Apply, then verify

Make the fixes. Then run whatever gates the project defines — and if the project forbids you from running some of them (infra commands, deploys), say so plainly rather than implying they passed.

Re-read your own diff before claiming done, including comments you *rewrote* — a rewritten comment is a new comment and gets the same hygiene check as a new one.

Reconcile the drop list against that diff. A finding you dropped but then satisfied anyway — a rename you made for your own reasons, a hoist that fell out of a rewrite — was never a considered decline; it was a reflex. Move it to applied and reply, or the report you hand back is false.

## Step 4 — Commit and push

One commit for the review fixes, describing **the change**, not the review. No PR references inside the PR's own commits — the commit lives in the PR.

Never force-push or amend; always a new commit, so reviewers can see what moved.

## Step 5 — Reply only where a reply does work

Reply to what you applied, declined, or deferred. **Dropped findings get no reply.** A nitpick you did not act on does not need a paragraph explaining why — closing the tab is the correct response, and every reply to a bot invites another round.

Reply **in-thread** so the finding is linked:

```bash
gh api repos/$REPO/pulls/$PR/comments/<comment_id>/replies -f body="$(cat <<'EOF'
<reply>
EOF
)"
```

For a **standalone PR-level comment** (no thread to attach to), open with the recipient's `@handle` — e.g. `@coderabbitai` — or nothing links your reply to them.

What a good reply contains:

- The verdict up front. "Declining — the premise is false" beats three paragraphs of throat-clearing.
- `file:line` evidence for anything you decline.
- The commit SHA for anything you applied.
- For a partial: what you fixed and what you did not, explicitly.

Two or three sentences is a complete reply. Be direct and factual. Do not thank a bot, do not apologize, and do not soften a correct decline into a hedge.

## Step 6 — Wait out one round, for one reason

Pushing re-triggers the bots. You wait for exactly one thing: **evidence that your fix broke something above the bar.** That is the only finding a later round can raise that is worth another commit.

Skip the wait entirely when:

- The review came from a human — say the branch is pushed and answered, and stop.
- You pushed no code (everything declined or dropped). Report that the review verdict stands as-is and let the user decide; do not sit through a round to watch a bot restate itself.

Otherwise start a ten-minute background timer and idle until it fires:

```bash
sleep 600   # Bash with run_in_background: true — a foreground sleep is blocked
```

When it fires, re-run the Step 1 fetch and separate the new round from what you already answered. Two reliable signals:

- **`created_at` later than your push.** Anchor on the push, not on "the last thing I read" — a round can land while you are still writing replies.
- **The head SHA in the review body** (`round N · head <sha>`). A body naming the SHA you just pushed is a genuine new round; one naming the previous head is the round you already handled.

Then:

- **New findings** → Step 2 triage first, and the bar applies unchanged. A later round is not more trustworthy than the first — it can be *less*, because it may be reasoning from a stale read of the file you just changed. Only findings that clear the bar get read end to end; the rest are dropped exactly like the first round's.
- **Nothing above the bar** → finish, and name the round you finished on.
- **Nothing new, and the bot posted nothing at all** → give it one more five-minute timer, then look for a rate-limit or error comment before you call it clean. CodeRabbit announces its own fair-usage limit as an issue comment; from the thread list, "reviewed and found nothing" and "never ran" are indistinguishable. Report which one it was.

### When to stop looping

Every push starts another round, so the end has to be one you choose. Stop at the first of these:

- A round raises nothing above the bar.
- A round only re-raises what you already declined. Do not answer again — repeating an argument to a bot is not progress. Note it for the user and stop.
- Two rounds, regardless. Past that, hand back with whatever is still open rather than letting the branch churn on the user's behalf.

## Done means

- Every finding was read and triaged. Above the bar: verified, then applied, declined, or deferred, and replied to. Below the bar: dropped, no reply.
- Branch is pushed.
- No round is outstanding: either the last one raised nothing above the bar, or you stopped on a stated rule and said what is still open.
- The user gets a short report:
  - what was applied,
  - what was **declined** and why, with `file:line` — the part they most need to audit, since a wrong decline is invisible until production,
  - a **one-line count of what was dropped** ("11 nitpicks dropped: naming, comment wording, test-name style"). Never an itemized list, and never silence — the count is what lets them ask for one back if they disagree with the bar.

Leaving nitpick threads unresolved is the expected end state, not an omission. A PR does not need a clean thread list; it needs correct code and a merge.
