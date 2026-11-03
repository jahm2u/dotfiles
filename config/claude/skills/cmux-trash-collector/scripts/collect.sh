#!/usr/bin/env bash
# collect.sh <slug> [--force] [--keep-branch]   (--force never deletes the remote branch of a PR that is not merged)
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
  PR_INFO=$(cd "$ROOT" && gh pr view "$BF_PR" --json state,headRefName --jq '"\(.state) \(.headRefName)"' 2>/dev/null) \
    || bf_die "gh lookup failed for ledger BF_PR=$BF_PR (gh/network down, or $BF_PR is not a PR in this repo, e.g. an issue number), retry. Nothing removed."
  PR_STATE=${PR_INFO%% *}; PR_HEAD=${PR_INFO#* }
  [ "$PR_HEAD" = "$BRANCH" ] \
    || bf_die "ledger BF_PR=$BF_PR is the PR of branch '$PR_HEAD', not this builder's branch '$BRANCH'. Nothing removed. Clear it (bf_set $SLUG BF_PR '') and re-run to look the PR up by branch."
else
  PR_INFO=$(cd "$ROOT" && gh pr list --head "$BRANCH" --state all --json number,state \
      --jq '([.[] | select(.state != "CLOSED")][0] // .[0]) | select(.) | "\(.number) \(.state)"' 2>/dev/null) \
    || bf_die "gh lookup failed for branch '$BRANCH', retry. Nothing removed."
  if [ -n "$PR_INFO" ]; then
    BF_PR=${PR_INFO%% *}; PR_STATE=${PR_INFO#* }
    bf_set "$SLUG" BF_PR "$BF_PR"
  else
    PR_STATE="none"
  fi
fi
echo "==> PR ${BF_PR:-none}: $PR_STATE"
if [ "$PR_STATE" != "MERGED" ] && [ $FORCE -eq 0 ]; then
  bf_die "PR is '$PR_STATE', not MERGED. Nothing removed. Re-run with --force only after the human has decided to abandon '$SLUG'."
fi
DIRTY=""
if [ -d "$WT" ]; then
  DIRTY=$(git -C "$WT" status --porcelain --untracked-files=all 2>/dev/null | grep -v -e " _bmad-output/implementation-artifacts/$(basename "$BF_SPEC")$" -e " _bmad-output/deferred-work.local.md$" || true)
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
    # The primary may have no _bmad-output yet (a brain-rooted builder on the new BMAD):
    # without this the cp fails under set -e, after the archive copy but before the
    # worktree is removed, and the collector looks like it did nothing (2026-10-04).
    mkdir -p "$ROOT/_bmad-output/implementation-artifacts"
    dest="$ROOT/_bmad-output/implementation-artifacts/$(basename "$f")"
    [ -e "$dest" ] || cp "$f" "$dest"
  done
  [ -f "$WT/_bmad-output/implementation-artifacts/deferred-work.md" ] && cp "$WT/_bmad-output/implementation-artifacts/deferred-work.md" "$ARCH/deferred-work.md"
  LOCAL_DEFERRED="$WT/_bmad-output/deferred-work.local.md"
  if [ -s "$LOCAL_DEFERRED" ]; then
    cp "$LOCAL_DEFERRED" "$ARCH/deferred-work.local.md"
    SHARED_DEFERRED="${BF_BMAD_ROOT:-$ROOT}/_bmad-output/deferred-work.md"
    mkdir -p "$(dirname "$SHARED_DEFERRED")"
    { printf '\n## %s -- %s (%s, PR #%s)\n' "$(date +%Y-%m-%d)" "$SLUG" "$(basename "$ROOT")" "${BF_PR:-none}"; cat "$LOCAL_DEFERRED"; } >> "$SHARED_DEFERRED"
    echo "==> appended $(grep -c . "$LOCAL_DEFERRED") deferred-work lines to $SHARED_DEFERRED"
  fi
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
EXIT_WAIT=${BF_EXIT_WAIT:-20}
exit_screen() {
  local t scr
  t=$(bf_target)
  if bf_is_herdr; then
    case "$(herdr agent get "$t" 2>&1)" in *agent_not_found*) echo shell; return 0;; esac
  fi
  scr=$(bf_read "$t" 30)
  case "$(printf '%s' "$scr" | tr -d '[:space:]')" in
    *Backgroundworkisrunning*Exitandstop*)
      if grep -qE '^[[:space:]│]*❯[[:space:]]*1[[:space:]]*\.' <<< "$scr"; then echo tasks; else echo tasks-other; fi
      return 0;;
    *unsentfeedbackdraft*) echo drafts; return 0;;
  esac
  awk '
    NF { n++; l[n] = $0 }
    END {
      for (i = n; i > 0 && i > n - 6; i--)
        if (index(l[i], "──") || index(l[i], "shift+tab") || index(l[i], "esc to interrupt") || index(l[i], "? for shortcuts")) chrome = 1
      if (n && !chrome && l[n] !~ /❯|│/ && l[n] ~ /[%$#][ \t]*$/) { print "shell"; exit }
      for (i = n; i > 0; i--) if (l[i] ~ /^[ \t]*❯/) break
      if (i > 0 && i < n) {
        p = l[i]; sub(/^[ \t]*❯[ \t]*/, "", p); sub(/[ \t]+$/, "", p)
        if (p == "/exit" && index(l[i + 1], "──")) { print "typed"; exit }
      }
      print "claude"
    }' <<< "$scr"
}
exit_builder() {
  local t st i drafts=0 other=0
  local -a tf
  t=$(bf_target)
  st=$(exit_screen)
  case "$st" in
    shell) echo "==> builder already exited to its shell; skipping /exit"; return 0;;
    claude)
      if bf_is_herdr || bf_is_orca; then bf_say_to_builder "/exit" || true
      else
        read -ra tf <<< "$t"
        cmux send "${tf[@]}" -- "/exit" >/dev/null 2>&1 || true
        sleep 0.7
        bf_send_key "$t" enter || true
      fi;;
  esac
  for ((i = 0; i < EXIT_WAIT; i++)); do
    case "$st" in
      tasks) echo "==> builder at 'Background work is running': chose 1. Exit and stop tasks"; bf_send_key "$t" enter || true;;
      tasks-other)
        [ $other = 1 ] || echo "WARNING: builder at 'Background work is running' with another option than 1. Exit and stop tasks selected; not answering it" >&2
        other=1;;
      drafts)
        if [ $drafts = 0 ]; then echo "==> builder at 'You have unsent feedback drafts': Esc, discard and exit"; bf_send_key "$t" esc || true; fi
        drafts=1;;
      typed) bf_send_key "$t" enter || true;;
    esac
    sleep 1
    bf_builder_alive || { echo "==> builder exited"; return 0; }
    st=$(exit_screen)
    [ "$st" = shell ] && { echo "==> builder exited"; return 0; }
  done
  echo "WARNING: builder still up ${EXIT_WAIT}s after /exit (screen: $st); closing its tab anyway" >&2
}
if [ -n "${BF_BUILDER_WS:-}" ] && bf_builder_alive; then
  echo "==> closing builder $(bf_builder_where)"
  exit_builder
  # Close the TAB only (bf_close_builder). Closing BF_BUILDER_WS here would close the
  # orchestrator's own workspace, since in tab mode that field is the HOST workspace.
  bf_close_builder
fi
# herdr: codex-review.sh records every review tab it opens; a failed round leaves its tab
# open on purpose. Close those -- and only those -- now.
if bf_is_herdr; then
  for t in $(printf '%s' "${BF_REVIEW_TABS:-}" | tr ',' ' '); do herdr tab close "$t" >/dev/null 2>&1 && echo "==> closed review tab $t" || true; done
elif bf_is_orca; then
  for t in $(printf '%s' "${BF_REVIEW_TABS:-}" | tr ',' ' '); do bf_orca terminal close --terminal "$t" --tab --json >/dev/null 2>&1 && echo "==> closed review tab $t" || true; done
fi
# The builders folder goes when its last builder does (only the empty anchor left).
bf_group_drop_if_empty "${BF_GROUP:-}" "${BF_ORCH_WS:-}" || true

# Other tabs working inside the worktree (an interactive codex, a shell) would outlive it with a
# deleted cwd. Close the provably disposable ones; anything else -- a Claude session above all --
# is only reported. Then sweep trash stranded by collections that predate this step.
SWEEP="$HOME/.claude/skills/cmux-trash-collector/scripts/sweep-tabs.py"
# sweep-tabs.py is cmux-only. For a herdr builder, list (never close) herdr panes still
# sitting in the worktree -- the collector only closes tabs the ledger says it created.
if bf_is_herdr; then
  if [ -d "$WT" ]; then
    herdr pane list 2>/dev/null | python3 -c '
import json,sys
wt=sys.argv[1]
for p in json.load(sys.stdin)["result"]["panes"]:
    c=p.get("foreground_cwd") or p.get("cwd") or ""
    if c==wt or c.startswith(wt+"/"): print("WARNING: herdr pane %s is still in the worktree (%s) -- close it yourself if disposable" % (p["pane_id"], c))
' "$WT" >&2 || true
  fi
elif bf_is_orca; then
  # Orca tabs all report the orchestrator's worktree as their cwd, so a tab left in the
  # builder worktree cannot be told apart from here. Nothing to sweep; say so.
  [ -d "$WT" ] && echo "note: orca -- check for stray tabs that cd'd into $WT" >&2 || true
elif [ -d "$WT" ]; then (cd "$ROOT" && "$SWEEP" --dir "$WT") || echo "WARNING: tab sweep failed; check for tabs left in $WT" >&2; fi

# 4. worktree + branch
if [ -d "$WT" ]; then
  echo "==> git worktree remove $WT"
  git -C "$ROOT" worktree remove --force "$WT"
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
# Only after a merge: --force on an OPEN PR must not cancel its CI or delete its
# remote branch (deleting the head branch closes the PR on GitHub; 2026-10-18 it
# closed 11 open PRs during a worktree cleanup).
if [ "$PR_STATE" = "MERGED" ]; then
  for RUN_ID in $(cd "$ROOT" && gh run list --branch "$BRANCH" --limit 20 --json databaseId,status --jq '.[] | select(.status != "completed") | .databaseId' 2>/dev/null); do
    (cd "$ROOT" && gh run cancel "$RUN_ID" >/dev/null 2>&1) && echo "==> cancelled CI run $RUN_ID on $BRANCH (it held a runner after the merge)" || echo "WARNING: could not cancel CI run $RUN_ID"
  done
fi
if [ $KEEP_BRANCH -eq 0 ] && git -C "$ROOT" ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  if [ "$PR_STATE" = "MERGED" ]; then
    git -C "$ROOT" push -q origin --delete "$BRANCH" && echo "==> deleted remote branch $BRANCH" || echo "WARNING: could not delete remote branch $BRANCH"
  else
    echo "==> kept remote branch $BRANCH (PR ${BF_PR:-?} is $PR_STATE, not merged)"
  fi
fi

bf_is_herdr || bf_is_orca || (cd "$ROOT" && "$SWEEP" --deleted) || true

# 5. bookkeeping
bf_pill_clear "$SLUG" "$BF_ORCH_WS"
bf_logline "$SLUG" collected "pr=${BF_PR:-none} state=$PR_STATE force=$FORCE archive=$ARCH"
bf_set "$SLUG" BF_STATUS "collected"
mv "$(bf_ledger_file "$SLUG")" "$ARCH/ledger.env"
mv "$(bf_log_file "$SLUG")" "$ARCH/builder.log" 2>/dev/null || true
bf_wslog "$BF_ORCH_WS" success collector "collected $SLUG (PR ${BF_PR:-none} $PR_STATE); archive $ARCH"
echo "DONE: $SLUG collected. PR ${BF_PR:-none} ($PR_STATE). Archive: $ARCH"
