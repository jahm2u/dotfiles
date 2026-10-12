---
name: review
description: Review a code change (base-branch diff, commit, or uncommitted changes) and report defects as [P0]-[P3] findings. Use for `codex review`, "review this branch", or any delegated code review. This is the review skill; there is no other review SKILL.md to look for.
---

# Review

This file is the review skill. Do not search for another one: no review skill exists under
`~/.pane`, `~/Library/Application Support`, `~/.claude` or anywhere else on this machine.
Follow the built-in `review-agent` method (read-only, defect-first, `[Pn] title — path:line`).

## Stay inside the repository

The review target is the git repository you were started in, nothing else.

1. Find its root once: `git rev-parse --show-toplevel`. Every path you read, list or search
   must be inside it.
2. Never run `find`, `rg`, `grep -r`, `ls -R`, `fd` or `du` on `/`, `/Users`, `$HOME`, `~`,
   `~/Library`, `~/Pictures` or a parent of the repository root. Walking the home folder
   triggers macOS privacy prompts (Photos, Contacts, other apps' data) on the user's screen.
3. If something you need is not in the repository (a skill, a config, a tool), do not go
   looking for it. Say it is missing in the review and carry on.
4. To run tests, use what the repository provides (`uv run`, `.venv/bin/python`, `npm test`).
   Do not search the filesystem for interpreters or test runners.

## Review the change

1. Read the repository's `AGENTS.md` (at the root, and in directories you touch).
2. For a base-branch review: `git merge-base HEAD <base>`, then `git diff <merge-base>`.
3. Read enough surrounding code, tests and call sites to prove each finding is real.
4. Flag only discrete, actionable defects introduced by the change that the author would fix.
   No speculation, pre-existing problems or style nits.

## Write the result

Findings first, most severe first, one per issue:

`[P1] Imperative finding title — path/to/file:line`

followed by one short paragraph on the scenario and why it is wrong.
`P0` release blocker, `P1` urgent, `P2` ordinary defect, `P3` low impact.
If nothing qualifies, write `No findings.` Then a brief overall assessment and test gaps.
