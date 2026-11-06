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
# It lists the builders of every known repo (root=<repo> column), including ones belonging
# to other orchestrator sessions. A leading * marks the ones this session spawned; --mine shows only those.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"
MINE_ONLY=0
[ "${1:-}" = "--mine" ] && { MINE_ONLY=1; shift; }
ME=$(bf_my_workspace 2>/dev/null || echo "")
if [ $# -ge 1 ]; then
  bf_load "$1"
  echo "slug=$BF_SLUG status=${BF_STATUS:-} pr=${BF_PR:-none} builder=$(bf_builder_where) group=${BF_GROUP:-none} orch=${BF_ORCH_WS:-}"
  echo "branch=${BF_BRANCH:-} worktree=${BF_WORKTREE:-}"
  echo "spec=${BF_SPEC:-}"
  echo "--- log ---"
  cat "$(bf_log_file "$1")" 2>/dev/null || echo "(no log)"
  exit 0
fi
shopt -s nullglob
found=0
ROOTS=$(bf_known_roots "$(bf_cwd_root 2>/dev/null || true)")
while IFS= read -r root; do
  [ -n "$root" ] || continue
  DIR="$root/_bmad/handoff/cmux"
  for f in "$DIR"/*.env; do
    if ! grep -qE '^BF_SLUG=.+' "$f"; then
      echo "WARNING: skipping $f: no BF_SLUG" >&2
      continue
    fi
    found=1
    ( unset BF_MUX BF_HERDR_SOCKET BF_BUILDER_TAB BF_BUILDER_AGENT BF_BUILDER_WS BF_BUILDER_SURFACE BF_STATUS BF_PR BF_ORCH_WS
      set -a; . "$f"; set +a
      bf_herdr_env
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
        last=$(tail -1 "$DIR/$BF_SLUG.log" 2>/dev/null | cut -d'|' -f3- | cut -c1-84 || true)
      fi
      printf '%s%-28s %-12s pr=%-6s %-13s %-11s root=%s %s\n' "$mine" "$BF_SLUG" "${BF_STATUS:-?}" "${BF_PR:-none}" "${BF_BUILDER_SURFACE:-${BF_BUILDER_WS:-}}" "$state" "$(basename "$root")" "$last" )
  done
done <<< "$ROOTS"
[ $found -eq 1 ] || echo "(no live builders in any known root: $(printf '%s' "$ROOTS" | tr '\n' ' '))"
[ $found -eq 1 ] && echo "(* = spawned by this session. state is read off the screen; 'unsubmitted' means it is stalled — press Enter with: approve.sh <slug>)"
