---
name: cmux-trash-collector
description: Retire a finished cmux builder — verify its PR merged, harvest the spec/log/deferred-work into the primary checkout's archive, exit its Claude session, close its cmux workspace, remove the worktree and delete the branch, and clear the ledger. Use when the user says "clean up the builder", "collect <slug>", "trash collect", "tear down the worktree", or right after a builder reports done.
---

# cmux trash collector

Closes the loop the orchestrator opened. It takes what is worth keeping out of the builder's
worktree, then removes the worktree, branch, cmux workspace and ledger entry. It refuses to
destroy anything that has not landed.

```bash
C=~/.claude/skills/cmux-trash-collector/scripts/collect.sh
S=~/.claude/skills/cmux-orchestrator/scripts
$S/ls.sh                        # what builders exist and where each one is
$C <slug>                       # normal path: PR merged, worktree clean
$C <slug> --force               # abandon: discards uncommitted work — human decides, never you
$C <slug> --keep-branch         # leave the remote branch (someone else still needs it)
```

## Procedure

1. `$S/ls.sh` — confirm the slug exists and read its last phase. If the phase is not `done` / `merged` / `failed`, the builder may still be working: `$S/peek.sh <slug>` before going further, and ask the orchestrator/human if in doubt.
2. `$C <slug>`. It gates on two things and prints exactly why when it refuses:
   - the PR must be `MERGED` (looked up by the ledger's PR number, or by branch);
   - the worktree must have no uncommitted changes and no unpushed commits.
3. **If it refuses:** show the human the refusal verbatim (the dirty-file list or the PR state). Do not add `--force` on your own — Rule 9 is exactly this case. When the human says to abandon the work, re-run with `--force`; uncommitted changes are saved to `UNCOMMITTED-DISCARDED.patch` in the archive before the worktree goes, so nothing is lost silently.
4. On success it prints `DONE: <slug> collected` and the archive path. Report to the user:
   - PR number and state, what was archived (`_bmad/handoff/cmux/archive/<slug>/`: spec, builder log, ledger, commits, diffstat, deferred-work),
   - that the spec was also copied into the primary checkout's `_bmad-output/implementation-artifacts/` if it was not already there,
   - which branch/worktree/workspace were removed.
5. If the builder left entries in `deferred-work.md`, read the archived copy and tell the user what was deferred; that is the only place those items now exist besides the merged PR body.

## What it never does

- Merge a PR, close an issue, or push anything except a remote-branch delete after a confirmed merge.
- Remove a worktree that is dirty or unmerged without `--force`.
- Touch any other builder, worktree or branch than the slug given.
- Clean up `.claude/worktrees/` entries it has no ledger for. Those belong to other sessions or DevBot; list them and leave them.
