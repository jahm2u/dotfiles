#!/usr/bin/env bash
# ls.sh [--mine] [slug] — list every builder (state, PR, workspace) or dump one builder's log.
#
# STATE is read off the builder's screen, not from the log. The last logged phase cannot
# tell "working" from "dead": an idle builder logs nothing, which is how three builders
# sat for three hours holding an unsubmitted prompt line after reporting pr-open.
#   busy  working · idle  finished, waiting on you · unsubmitted  a line never submitted
#   rate-limited  killed mid-turn by a 429; the ledger still shows its last phase
#   prompt  stopped on a permission dialog (approve.sh) · gone  tab/workspace closed
#
# The ledger is per-REPO, so it lists builders belonging to other orchestrator sessions
# too. A leading * marks the ones this session spawned; --mine shows only those.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"
MINE_ONLY=0
[ "${1:-}" = "--mine" ] && { MINE_ONLY=1; shift; }
ME=$(bf_my_workspace 2>/dev/null || echo "")
DIR=$(bf_ledger_dir)
if [ $# -ge 1 ]; then
  bf_load "$1"
  echo "slug=$BF_SLUG status=$BF_STATUS pr=${BF_PR:-none} builder=$(bf_builder_where) group=${BF_GROUP:-none} orch=$BF_ORCH_WS"
  echo "branch=$BF_BRANCH worktree=$BF_WORKTREE"
  echo "spec=$BF_SPEC"
  echo "--- log ---"
  cat "$(bf_log_file "$1")" 2>/dev/null || echo "(no log)"
  exit 0
fi
shopt -s nullglob
found=0
for f in "$DIR"/*.env; do
  found=1
  ( set -a; . "$f"; set +a
    mine=" "; [ -n "$ME" ] && [ "${BF_ORCH_WS:-}" = "$ME" ] && mine="*"
    [ "$MINE_ONLY" = 1 ] && [ "$mine" != "*" ] && exit 0
    state=$(bf_builder_state)
    # For a stalled builder the actionable line is what is stuck in its prompt, not the
    # last thing it managed to log.
    if [ "$state" = unsubmitted ]; then
      last="NOT SUBMITTED: $(bf_prompt_text "$(bf_target)" | cut -c1-70)"
    elif [ "$state" = rate-limited ]; then
      last="RATE LIMITED: $(bf_rate_limit_note | cut -c1-70)"
    else
      last=$(tail -1 "$DIR/$BF_SLUG.log" 2>/dev/null | cut -d'|' -f3- | cut -c1-84)
    fi
    printf '%s%-28s %-12s pr=%-6s %-13s %-11s %s\n' "$mine" "$BF_SLUG" "$BF_STATUS" "${BF_PR:-none}" "${BF_BUILDER_SURFACE:-$BF_BUILDER_WS}" "$state" "$last" )
done
[ $found -eq 1 ] || echo "(no live builders — ledger dir $DIR is empty)"
[ $found -eq 1 ] && echo "(* = spawned by this session. state is read off the screen; 'unsubmitted' means it is stalled — press Enter with: approve.sh <slug>)"
