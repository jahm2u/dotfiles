#!/usr/bin/env bash
# wait.sh <slug> [--for <phase>] [--timeout <secs>]
# Block until the builder logs its next INTERRUPTING phase (checkpoint question blocked pr-open
# converged merged done failed) — or the named phase — then print that log line and exit 0.
# Exit 2 on timeout (default 1800s), exit 3 as soon as the builder is demonstrably NOT
# working -- idle, stalled on an unsubmitted prompt line, or held at a permission dialog.
# That exit is the point: waiting on the LOG alone can never end, because a builder that
# is not working writes no log. Use this instead of sleep-polling; builder messages also
# arrive in your prompt, so only wait when you have nothing else to do.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"
[ $# -ge 1 ] || bf_die "usage: wait.sh <slug> [--for <phase>] [--timeout <secs>]"
SLUG=$1; shift; FOR=""; LIMIT=1800
while [ $# -gt 0 ]; do case "$1" in --for) FOR=$2; shift 2;; --timeout) LIMIT=$2; shift 2;; *) bf_die "unknown arg $1";; esac; done
bf_load "$SLUG"
LOG=$(bf_log_file "$SLUG"); start=$(wc -l < "$LOG" | tr -d ' '); end=$(( $(date +%s) + LIMIT ))
PAT='\|(checkpoint|question|blocked|pr-open|converged|merged|done|failed)\|'
[ -n "$FOR" ] && PAT="\|$FOR\|"
idle_streak=0
while [ "$(date +%s)" -lt "$end" ]; do
  hit=$(tail -n +"$((start+1))" "$LOG" | grep -E "$PAT" | head -1 || true)
  if [ -n "$hit" ]; then echo "$hit" | awk -F'|' '{print $2": "$3}'; exit 0; fi
  # bf_builder_alive, not bf_ws_exists: in tab mode BF_BUILDER_WS is the ORCHESTRATOR's
  # workspace, so the old check asked whether *we* still existed and always said yes.
  state=$(bf_builder_state)
  case "$state" in
    gone) echo "builder $(bf_builder_where) is gone"; exit 1;;
    busy) idle_streak=0;;
    *)    idle_streak=$((idle_streak + 1));;
  esac
  if [ "$idle_streak" -ge 4 ]; then
    echo "builder is '$state' and logging nothing — it is not working."
    case "$state" in
      unsubmitted) echo "  stuck in its prompt: $(bf_prompt_text "$(bf_target)")"
                   echo "  submit it:  approve.sh $SLUG";;
      prompt)      echo "  waiting on a permission dialog:  approve.sh $SLUG";;
      idle)        echo "  it finished its turn and is waiting on you:  tell.sh $SLUG \"...\"";;
      rate-limited) echo "  killed mid-turn by a rate limit: $(bf_rate_limit_note)"
                    echo "  its ledger phase is stale — check the tree before assuming work was lost:"
                    echo "    git -C $BF_WORKTREE status --short && git -C $BF_WORKTREE log --oneline -3";;
    esac
    exit 3
  fi
  sleep 5
done
echo "timeout after ${LIMIT}s; last: $(tail -1 "$LOG" | cut -d'|' -f2-)"; exit 2
