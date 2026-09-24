#!/usr/bin/env bash
# collect.sh <slug> [--force] [--keep-branch]
#
# Retire one builder after its work has landed:
#   1. refuse unless the PR is MERGED (or --force) and the worktree is clean (or --force)
#   2. harvest: spec(s), deferred-work, builder log + ledger, commit list -> _bmad/handoff/cmux/archive/<slug>/
#      and copy any spec-<slug>*.md into the PRIMARY checkout's implementation-artifacts (no overwrite)
#   3. exit the builder's Claude session and close its cmux workspace; drop the builders
#      sidebar group when this was its last member
#   4. git worktree remove, delete local branch (and remote, unless --keep-branch)
#   5. clear the sidebar pill, move the ledger into the archive, print the summary
# Never runs without a ledger; never removes a dirty worktree without --force
# (Rule 9: the human decides what happens to uncommitted work).
set -euo pipefail
LIB="$HOME/.claude/skills/cmux-orchestrator/scripts/lib.sh"
# shellcheck disable=SC1090
. "$LIB"
[ $# -ge 1 ] || bf_die "usage: collect.sh <slug> [--force] [--keep-branch]"
SLUG=$1; shift
# The collector runs in the ORCHESTRATOR. A builder running it on ITSELF would type /exit
# into its own session and close its own workspace halfway through, leaving the worktree
# half-removed and the ledger inconsistent. 2908 had exactly that queued in its prompt on
# 2026-09-11. Read the env BEFORE bf_load overwrites BF_SLUG.
if [ -n "${BF_SLUG:-}" ]; then
  if [ "$BF_SLUG" = "$SLUG" ]; then
    bf_die "refusing: this IS builder '$SLUG' trying to collect itself. The collector runs in the orchestrator — report 'done' and let it collect you."
  fi
  echo "WARNING: BF_SLUG=$BF_SLUG is set, so this looks like builder '$BF_SLUG' collecting a DIFFERENT builder ('$SLUG'). Builders do not collect anything." >&2
fi
FORCE=0; KEEP_BRANCH=0
for a in "$@"; do case "$a" in --force) FORCE=1;; --keep-branch) KEEP_BRANCH=1;; *) bf_die "unknown arg $a";; esac; done
bf_load "$SLUG"
ROOT=$(bf_primary_root)
DIR=$(bf_ledger_dir)
ARCH="$DIR/archive/$SLUG"
WT=$BF_WORKTREE; BRANCH=$BF_BRANCH

# Removing the directory you are standing in leaves the shell on a deleted path and the
# worktree half-gone. Cheap to check, impossible to recover from mid-flight.
case "$PWD/" in
  "$WT"/*) bf_die "refusing: you are inside the worktree being collected ($PWD). cd elsewhere first.";;
esac

echo "==> $SLUG  branch=$BRANCH  worktree=$WT  builder=$BF_BUILDER_WS  status=$BF_STATUS"

# 1. gates
PR_STATE="unknown"
if [ -n "${BF_PR:-}" ]; then
  PR_STATE=$(gh pr view "$BF_PR" --json state --jq .state 2>/dev/null || echo unknown)
else
  PR_STATE=$(gh pr list --head "$BRANCH" --state all --json state --jq '.[0].state' 2>/dev/null || echo unknown)
  n=$(gh pr list --head "$BRANCH" --state all --json number --jq '.[0].number' 2>/dev/null || true)
  [ -n "$n" ] && [ "$n" != "null" ] && bf_set "$SLUG" BF_PR "$n" && BF_PR=$n
fi
[ -z "$PR_STATE" ] && PR_STATE="none"
echo "==> PR ${BF_PR:-none}: $PR_STATE"
if [ "$PR_STATE" != "MERGED" ] && [ $FORCE -eq 0 ]; then
  bf_die "PR is '$PR_STATE', not MERGED. Nothing removed. Re-run with --force only after the human has decided to abandon '$SLUG'."
fi
DIRTY=""
if [ -d "$WT" ]; then
  DIRTY=$(git -C "$WT" status --porcelain 2>/dev/null || true)
  if [ -n "$DIRTY" ] && [ $FORCE -eq 0 ]; then
    echo "$DIRTY"
    bf_die "worktree has uncommitted changes (above). Nothing removed. Show these to the human; --force discards them."
  fi
  UNPUSHED=$(git -C "$WT" log --oneline "origin/$BRANCH..HEAD" 2>/dev/null || git -C "$WT" log --oneline "origin/main..HEAD" 2>/dev/null || true)
  if [ -n "$UNPUSHED" ] && [ "$PR_STATE" != "MERGED" ] && [ $FORCE -eq 0 ]; then
    echo "$UNPUSHED"; bf_die "worktree has unpushed commits (above). Nothing removed."
  fi
fi

# 2. harvest
mkdir -p "$ARCH"
if [ -d "$WT" ]; then
  shopt -s nullglob
  for f in "$WT"/_bmad-output/implementation-artifacts/spec-"$SLUG"*.md; do
    cp "$f" "$ARCH/"
    dest="$ROOT/_bmad-output/implementation-artifacts/$(basename "$f")"
    [ -e "$dest" ] || cp "$f" "$dest"
  done
  [ -f "$WT/_bmad-output/implementation-artifacts/deferred-work.md" ] && cp "$WT/_bmad-output/implementation-artifacts/deferred-work.md" "$ARCH/deferred-work.md"
  git -C "$WT" log --oneline "origin/main..HEAD" > "$ARCH/commits.txt" 2>/dev/null || true
  git -C "$WT" diff --stat "origin/main...HEAD" > "$ARCH/diffstat.txt" 2>/dev/null || true
  [ -n "$DIRTY" ] && git -C "$WT" diff > "$ARCH/UNCOMMITTED-DISCARDED.patch" 2>/dev/null || true
fi
cp "$(bf_log_file "$SLUG")" "$ARCH/builder.log" 2>/dev/null || true
# Codex review rounds (codex-review.sh writes them beside the ledger): keep the reviews and
# transcripts, drop the generated runner scripts and exit markers.
for f in "$DIR/$SLUG".codex-review-*.md "$DIR/$SLUG".codex-review-*.log; do if [ -e "$f" ]; then mv "$f" "$ARCH/"; fi; done
rm -f "$DIR/$SLUG".codex-review-*.sh "$DIR/$SLUG".codex-review-*.exit
echo "==> harvested to $ARCH: $(ls "$ARCH" | tr '\n' ' ')"

# 3. builder workspace
if [ -n "${BF_BUILDER_WS:-}" ] && bf_builder_alive; then
  echo "==> closing builder $(bf_builder_where)"
  bf_say_to_builder "/exit"
  sleep 3
  if [ -n "${BF_BUILDER_SURFACE:-}" ]; then
    # Close the TAB only. Closing BF_BUILDER_WS here would close the orchestrator's own
    # workspace, since in tab mode that field is the HOST workspace, not the builder's.
    cmux close-surface --workspace "$BF_BUILDER_WS" --surface "$BF_BUILDER_SURFACE" >/dev/null || true
  else
    cmux close-workspace --workspace "$BF_BUILDER_WS" >/dev/null || true
  fi
fi
# The builders folder goes when its last builder does (only the empty anchor left).
bf_group_drop_if_empty "${BF_GROUP:-}" "${BF_ORCH_WS:-}" || true

# Other tabs working inside the worktree (an interactive codex, a shell) would outlive it with a
# deleted cwd. Close the provably disposable ones; anything else -- a Claude session above all --
# is only reported. Then sweep trash stranded by collections that predate this step.
SWEEP="$HOME/.claude/skills/cmux-trash-collector/scripts/sweep-tabs.py"
if [ -d "$WT" ]; then (cd "$ROOT" && "$SWEEP" --dir "$WT") || echo "WARNING: tab sweep failed; check for tabs left in $WT" >&2; fi

# 4. worktree + branch
if [ -d "$WT" ]; then
  echo "==> git worktree remove $WT"
  if [ $FORCE -eq 1 ]; then git -C "$ROOT" worktree remove --force "$WT"; else git -C "$ROOT" worktree remove "$WT"; fi
fi
git -C "$ROOT" worktree prune

# The worktree's memory entry is a SYMLINK into the primary checkout's memory dir (spawn.sh
# creates it so the builder inherits the repo's house rules). The worktree is gone now, so the
# link dangles. Remove the link only -- never a real directory, and never the shared target it
# points at. $WT is already the physical path, so slugify the string rather than cd-ing to a
# path that no longer exists.
WT_SLUG=$(printf '%s' "$WT" | sed 's|[^A-Za-z0-9]|-|g')
MEM_LINK="$HOME/.claude/projects/$WT_SLUG/memory"
if [ -L "$MEM_LINK" ]; then
  rm "$MEM_LINK" && echo "==> removed memory symlink $WT_SLUG/memory"
  # and the project dir, but only when nothing else is left in it (rmdir refuses otherwise)
  rmdir "$HOME/.claude/projects/$WT_SLUG" 2>/dev/null && echo "==> removed empty project dir $WT_SLUG" || true
fi
if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  if [ "$PR_STATE" = "MERGED" ] || [ $FORCE -eq 1 ]; then
    git -C "$ROOT" branch -D "$BRANCH" >/dev/null && echo "==> deleted local branch $BRANCH (squash-merged branches need -D)"
  fi
fi
if [ $KEEP_BRANCH -eq 0 ] && git -C "$ROOT" ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  if [ "$PR_STATE" = "MERGED" ] || [ $FORCE -eq 1 ]; then
    git -C "$ROOT" push -q origin --delete "$BRANCH" && echo "==> deleted remote branch $BRANCH" || echo "WARNING: could not delete remote branch $BRANCH"
  fi
fi

(cd "$ROOT" && "$SWEEP" --deleted) || true

# 5. bookkeeping
cmux clear-status "bf-$SLUG" --workspace "$BF_ORCH_WS" >/dev/null 2>&1 || true
bf_logline "$SLUG" collected "pr=${BF_PR:-none} state=$PR_STATE force=$FORCE archive=$ARCH"
bf_set "$SLUG" BF_STATUS "collected"
mv "$(bf_ledger_file "$SLUG")" "$ARCH/ledger.env"
mv "$(bf_log_file "$SLUG")" "$ARCH/builder.log" 2>/dev/null || true
cmux log --workspace "$BF_ORCH_WS" --level success --source collector -- "collected $SLUG (PR ${BF_PR:-none} $PR_STATE); archive $ARCH" >/dev/null 2>&1 || true
echo "DONE: $SLUG collected. PR ${BF_PR:-none} ($PR_STATE). Archive: $ARCH"
