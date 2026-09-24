#!/usr/bin/env bash
# report.sh <phase> "<one-line message>" [--ping]
#
# The builder's only channel back to the orchestrator. Run from inside the builder's
# cmux workspace (BF_SLUG / BF_LEDGER / BF_ORCH_WS come from the workspace env).
#
# Phases and what each one does:
#   progress-only (log + sidebar pill, does NOT interrupt the orchestrator):
#       started planning implementing testing review-round pushing
#   interrupting (also typed into the orchestrator's prompt + macOS notification):
#       checkpoint question blocked pr-open converged merged done failed
#   --ping forces the interrupt for any phase.
#
# Every call: appends to <slug>.log, sets BF_STATUS in the ledger, updates the
# "bf-<slug>" pill on the orchestrator's workspace, logs in the builder's own sidebar.
set -euo pipefail
LIB="$HOME/.claude/skills/cmux-orchestrator/scripts/lib.sh"
# shellcheck disable=SC1090
. "$LIB"
[ $# -ge 2 ] || bf_die "usage: report.sh <phase> <message> [--ping]"
PHASE=$1; MSG=$2; PING=${3:-}
: "${BF_SLUG:?BF_SLUG not set — are you inside the builder workspace?}"
: "${BF_LEDGER:?BF_LEDGER not set}"
[ -f "$BF_LEDGER" ] || bf_die "ledger missing: $BF_LEDGER"
set -a; . "$BF_LEDGER"; set +a

case "$PHASE" in
  started|planning|implementing|testing|review-round|pushing) INTERRUPT=0;;
  checkpoint|question|blocked|pr-open|converged|merged|done|failed) INTERRUPT=1;;
  *) bf_die "unknown phase '$PHASE'";;
esac
[ "$PING" = "--ping" ] && INTERRUPT=1

case "$PHASE" in
  failed|blocked) COLOR="#e67e80"; LEVEL=error;;
  checkpoint|question) COLOR="#dbbc7f"; LEVEL=warning;;
  done|merged|converged) COLOR="#a7c080"; LEVEL=success;;
  *) COLOR="#7fbbb3"; LEVEL=progress;;
esac

# PR number is worth keeping in the ledger for the collector.
if [ -z "${BF_PR:-}" ] && [[ "$MSG" =~ (PR|pr|pull)[[:space:]]*#?([0-9]{1,6}) ]]; then
  bf_set "$BF_SLUG" BF_PR "${BASH_REMATCH[2]}"
fi
bf_set "$BF_SLUG" BF_STATUS "$PHASE"
bf_logline "$BF_SLUG" "$PHASE" "$MSG"

MY_WS=$(bf_my_workspace 2>/dev/null || echo "")
[ -n "$MY_WS" ] && cmux log --workspace "$MY_WS" --level "$LEVEL" --source builder -- "$MSG" >/dev/null || true
cmux set-status "bf-$BF_SLUG" "$PHASE" --workspace "$BF_ORCH_WS" --icon hammer --color "$COLOR" --priority 50 >/dev/null || true

if [ "$INTERRUPT" = 1 ]; then
  cmux notify --workspace "$BF_ORCH_WS" --title "builder $BF_SLUG · $PHASE" --body "$MSG" >/dev/null || true
  if bf_ws_exists "$BF_ORCH_WS"; then
    # bf_orch_target, not bf_say_to: a builder is a tab inside the orchestrator's own
    # workspace, so a workspace-only ref can land this message in the BUILDER's prompt.
    bf_send_line "$(bf_orch_target)" "[builder $BF_SLUG] $PHASE: $MSG"
  else
    echo "WARNING: orchestrator workspace $BF_ORCH_WS is gone; message kept in ledger log only" >&2
  fi
fi
echo "reported $PHASE (interrupt=$INTERRUPT): $MSG"
