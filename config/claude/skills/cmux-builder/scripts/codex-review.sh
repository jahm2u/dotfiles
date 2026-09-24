#!/usr/bin/env bash
# codex-review.sh [--base origin/main] [--model gpt-6-astra] [--effort low] [--timeout 540]
#                 [--no-tab] [--keep-tab]
#
# Local review #2 of the builder loop (after the Claude `/code-review`, before the PR opens
# and the CT210 reviewer takes over). Codex reviews the COMMITTED diff of this worktree's
# branch against --base, in a cmux tab next to the caller so the human can watch it; this
# script blocks until it finishes and prints the review.
#
# Exit: 0 = no P0-P2 findings
#       1 = at least one P0-P2 finding (address each: fix it, or record why it is wrong)
#       2 = the review failed / timed out (codex may still be running in its tab) / came back
#           empty or in a format with findings this script could not parse
#       3 = refused before reviewing (dirty tree, no commits, no codex, bad args) -- NOT findings
# Codex tags findings [P0]..[P3]; P3 is a nit. P2 is NOT optional: in testing gpt-6-astra
# rated a plain off-by-one that returned NaN for every input as P2.
#
# Measured gotchas (2026-09-24, codex-cli 0.154.0) -- each is why a line below exists:
#   * `-c` overrides must go BEFORE the subcommand. `cg codex review -c model=x` makes the
#     subcommand's -c layer replace cg's gateway provider block and the call goes straight
#     to api.openai.com -> 401 "Missing bearer". `cg codex -c model=x review` works.
#   * The interactive TUI stops on "Do you trust the contents of this directory?" in any repo
#     not yet trusted -- even with --yolo. Worktrees inherit trust from the primary checkout.
#     `codex review` itself never asks, but the tab is watched anyway and the prompt is
#     answered with Enter (default = "Yes, continue"); codex then persists the trust itself.
#   * The TUI also opens on an "Update available" menu: check_for_update_on_startup=false.
#   * `codex review` prints the final review on STDOUT and its whole transcript on STDERR.
#
# From a builder: call it by its literal path (a $VAR in the command defeats the pre-approved
# allow-list) with a Bash timeout of 600000.
set -euo pipefail
LIB="$HOME/.claude/skills/cmux-orchestrator/scripts/lib.sh"
# shellcheck disable=SC1090
. "$LIB"
# Refusals must not share exit 1 with "findings" (lib.sh's bf_die exits 1).
die() { echo "ERROR: $*" >&2; exit 3; }

BASE="origin/main"
MODEL="${CODEX_REVIEW_MODEL:-gpt-6-astra}"
EFFORT="${CODEX_REVIEW_EFFORT:-low}"
TIMEOUT=540          # fits inside the builder's 600s Bash ceiling
TAB=1 KEEP_TAB=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE=$2; shift 2;;
    --model) MODEL=$2; shift 2;;
    --effort) EFFORT=$2; shift 2;;
    --timeout) TIMEOUT=$2; shift 2;;
    --no-tab) TAB=0; shift;;
    --keep-tab) KEEP_TAB=1; shift;;
    -h|--help) sed -n '2,29p' "$0"; exit 0;;
    *) die "unknown arg $1";;
  esac
done

WT=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git worktree"
cd "$WT"
BRANCH=$(git branch --show-current)
git fetch -q origin 2>/dev/null || echo "WARNING: git fetch failed; reviewing against the local $BASE" >&2
# The review reads COMMITS. Uncommitted edits would be silently left out of it.
# Untracked counts too: a new file never committed would silently fall outside the review.
if [ -n "$(git status --porcelain)" ]; then
  git status --short >&2
  die "uncommitted changes (above) would not be reviewed. Commit first, then re-run."
fi
[ -n "$(git log --oneline "$BASE..HEAD" 2>/dev/null)" ] || die "no commits on $BRANCH beyond $BASE; nothing to review"

# The codex BINARY via the gateway helper when present. In an interactive zsh `codex` is a
# function that routes through cg; a script does not inherit that function.
if [ -x "$HOME/.local/bin/cg" ]; then CODEX=("$HOME/.local/bin/cg" codex)
else CODEX=("$(command -v codex)") || die "codex is not installed"; fi

# Artifacts live beside the ledger (gitignored, in the PRIMARY checkout) so the worktree stays
# clean for the collector; without a ledger they go to a temp dir.
SLUG="${BF_SLUG:-$(basename "$WT")}"
if [ -n "${BF_LEDGER:-}" ]; then OUTDIR=$(dirname "$BF_LEDGER"); else OUTDIR="${TMPDIR:-/tmp}/codex-review"; fi
mkdir -p "$OUTDIR"
N=1; while [ -e "$OUTDIR/$SLUG.codex-review-$N.md" ]; do N=$((N + 1)); done
P="$OUTDIR/$SLUG.codex-review-$N"
REVIEW="$P.md" TRANSCRIPT="$P.log" DONE="$P.exit" RUNNER="$P.sh"

# Codex REVIEWS; the builder fixes. --yolo lets codex run code (it smoke-tests), so snapshot
# the tree and flag anything it wrote -- a change the builder did not make must not be committed.
TREE_BEFORE=$(git status --porcelain --untracked-files=all)

q() { printf '%q' "$1"; }
ARGS=(--yolo -c check_for_update_on_startup=false -c "model=$MODEL" -c "model_reasoning_effort=$EFFORT"
      review --base "$BASE")
{
  echo '#!/usr/bin/env bash'
  echo "cd $(q "$WT") || { echo 97 > $(q "$DONE"); exit 97; }"
  echo "echo '== codex review round $N: $BRANCH vs $BASE ($MODEL, effort $EFFORT) =='"
  # SHOW=1 (the tab) streams the transcript to the terminal; inline keeps it on disk only.
  printf '%s' "$(printf '%q ' "${CODEX[@]}" "${ARGS[@]}")"
  echo "> $(q "$REVIEW") 2> >(if [ \"\${SHOW:-0}\" = 1 ]; then tee $(q "$TRANSCRIPT") >&2; else cat > $(q "$TRANSCRIPT"); fi)"
  echo 'rc=$?; sleep 1'
  echo "echo \$rc > $(q "$DONE").tmp && mv $(q "$DONE").tmp $(q "$DONE")"
  echo "echo; echo \"== review done (exit \$rc) ==\"; cat $(q "$REVIEW")"
} > "$RUNNER"
chmod +x "$RUNNER"
logl() { [ -n "${BF_SLUG:-}" ] && bf_logline "$BF_SLUG" codex-review "$1" || true; }
logl "round $N started ($MODEL/$EFFORT vs $BASE)"

SURFACE="" WS=""
if [ $TAB -eq 1 ] && WS=$(bf_my_workspace 2>/dev/null) && [ -n "$WS" ]; then
  OUT=$(cmux new-surface --type terminal --workspace "$WS" --focus false 2>/dev/null || true)
  SURFACE=$(echo "$OUT" | sed -n 's/^OK \(surface:[0-9]*\).*/\1/p' | tail -1)
fi
if [ -n "$SURFACE" ]; then
  cmux rename-tab --workspace "$WS" --surface "$SURFACE" "🔍 review $SLUG #$N" >/dev/null 2>&1 || true
  sleep 0.5
  # Short on purpose: a long `cmux send` loses its middle. The command lives in $RUNNER.
  cmux send --workspace "$WS" --surface "$SURFACE" -- "SHOW=1 bash $(q "$RUNNER")" >/dev/null
  sleep 0.7
  cmux send-key --workspace "$WS" --surface "$SURFACE" enter >/dev/null
  # `send-key enter` can return OK and submit nothing. The transcript file appearing is the
  # proof it started; one more Enter, then give up on the tab and run inline.
  started=0
  for i in $(seq 1 30); do
    [ -e "$TRANSCRIPT" ] && { started=1; break; }
    [ "$i" = 10 ] && cmux send-key --workspace "$WS" --surface "$SURFACE" enter >/dev/null 2>&1
    sleep 0.5
  done
  if [ $started -eq 0 ]; then
    echo "WARNING: the review tab $SURFACE never started; closing it and running inline" >&2
    cmux close-surface --workspace "$WS" --surface "$SURFACE" >/dev/null 2>&1 || true
    SURFACE=""
  else
    echo "==> codex review round $N running in tab $SURFACE ($MODEL, effort $EFFORT)"
  fi
fi
if [ -z "$SURFACE" ]; then
  echo "==> codex review round $N running inline ($MODEL, effort $EFFORT)"
  SHOW=0 bash "$RUNNER" >/dev/null 2>&1 &
fi

end=$(( $(date +%s) + TIMEOUT ))
while [ ! -e "$DONE" ]; do
  if [ "$(date +%s)" -ge "$end" ]; then
    echo "TIMEOUT after ${TIMEOUT}s. Codex is still running${SURFACE:+ in tab $SURFACE}; transcript: $TRANSCRIPT"
    echo "Re-run with a larger --timeout, or read $REVIEW once $DONE exists."
    logl "round $N timed out"
    exit 2
  fi
  # Answer codex's startup dialogs if one ever renders in the tab (Enter = the default:
  # "Yes, continue" on trust; the update menu is already suppressed by config).
  if [ -n "$SURFACE" ] && cmux read-screen --workspace "$WS" --surface "$SURFACE" --lines 30 2>/dev/null \
       | grep -q "Do you trust the contents of this directory"; then
    echo "==> answering codex's trust prompt in $SURFACE"
    cmux send-key --workspace "$WS" --surface "$SURFACE" enter >/dev/null 2>&1 || true
  fi
  sleep 3
done
RC=$(cat "$DONE")

if [ "$RC" != 0 ] || [ ! -s "$REVIEW" ]; then
  echo "codex review FAILED (exit $RC). Tab left open${SURFACE:+ ($SURFACE)}. Transcript tail:"
  tail -15 "$TRANSCRIPT" 2>/dev/null || true
  logl "round $N failed exit=$RC"
  exit 2
fi
if [ -n "$SURFACE" ] && [ $KEEP_TAB -eq 0 ]; then
  cmux close-surface --workspace "$WS" --surface "$SURFACE" >/dev/null 2>&1 || true
fi

cat "$REVIEW"
TREE_AFTER=$(git -C "$WT" status --porcelain --untracked-files=all)
if [ "$TREE_AFTER" != "$TREE_BEFORE" ]; then
  echo
  echo "WARNING: codex changed the worktree during the review (it should only read). Inspect and"
  echo "revert anything you did not write before committing:"
  diff <(printf '%s\n' "$TREE_BEFORE") <(printf '%s\n' "$TREE_AFTER") | sed -n 's/^> /  /p'
  logl "round $N: codex modified the worktree"
fi
c() { grep -cE "^[[:space:]]*- \[$1\]" "$REVIEW" || true; }
P0=$(c P0) P1=$(c P1) P2=$(c P2) P3=$(c P3)
BLOCK=$((P0 + P1 + P2))
if [ $((BLOCK + P3)) -eq 0 ] && grep -qiE 'review comment|\[P[0-9]' "$REVIEW"; then
  echo "== codex round $N: findings present but not in the '- [Pn]' shape; read them above. (saved: $REVIEW)"
  logl "round $N: unparsed findings"
  exit 2
fi
echo
echo "== codex round $N: P0=$P0 P1=$P1 P2=$P2 P3=$P3 -> $([ $BLOCK -eq 0 ] && echo CLEAN || echo "$BLOCK to address") (saved: $REVIEW)"
logl "round $N: P0=$P0 P1=$P1 P2=$P2 P3=$P3"
[ $BLOCK -eq 0 ] && exit 0 || exit 1
