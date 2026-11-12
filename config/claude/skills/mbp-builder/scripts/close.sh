#!/bin/bash
# close.sh <slug> [--force]: end builder b-<slug> on the MBP and remove its worktree and local branch.
# Refuses unless the worktree is clean, nothing is unpushed, and the branch has a MERGED PR (checked with
# gh on this Mini). --force skips those checks; it is a person's call, never a builder's.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
slug=${1:?usage: close.sh <slug> [--force]}; force=${2:-}
info=$(mbb 30 close-check "$slug")
branch=$(sed -n 's/^branch=//p' <<< "$info"); repo=$(sed -n 's/^repo=//p' <<< "$info")
dirty=$(sed -n 's/^dirty=//p' <<< "$info"); unpushed=$(sed -n 's/^unpushed=//p' <<< "$info")
if [ "$force" != --force ]; then
  [ "$dirty" = 0 ] || die "worktree has $dirty uncommitted path(s); commit, archive or use --force"
  [ "${unpushed:-0}" = 0 ] || die "$unpushed commit(s) not on origin/$branch; push first or use --force"
  merged=$(gh pr list -R "$repo" --head "$branch" --state merged --json number --jq 'length' 2>/dev/null || echo error)
  [ "$merged" != error ] || die "gh could not read PRs for $repo"
  [ "$merged" -ge 1 ] || die "no merged PR for $repo:$branch; use --force to close anyway"
fi
mbb 60 close "$slug"
