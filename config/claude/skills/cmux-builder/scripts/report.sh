#!/usr/bin/env bash
# report.sh <phase> "<one-line message>" [--ping]
#
# The builder's only channel back to the orchestrator. Run from inside the builder's
# cmux workspace or herdr tab (BF_SLUG / BF_LEDGER / BF_ORCH_WS come from its env; the
# ledger's BF_MUX picks cmux or herdr -- in herdr the line goes in via `herdr agent prompt`).
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
bf_herdr_env   # herdr ledgers: point the CLI at the server this builder lives on

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

# PR number is worth keeping in the ledger for the collector. Take it from the
# builder's own branch, never from the message text: a checkpoint that mentions
# another PR ("PR 961 still OPEN") used to pin the wrong number (2026-10-29,
# builders 951 and 962), and collect.sh then judged the wrong PR.
case "$PHASE" in
  pr-open|converged|merged|done)
    if [ -n "${BF_BRANCH:-}" ]; then
      n=$(cd "${BF_WORKTREE:-.}" 2>/dev/null && gh pr list --head "$BF_BRANCH" --state all \
            --json number --jq '.[0].number // empty' 2>/dev/null || true)
      [ -n "$n" ] && [ "$n" != "${BF_PR:-}" ] && bf_set "$BF_SLUG" BF_PR "$n"
    fi;;
esac
bf_set "$BF_SLUG" BF_STATUS "$PHASE"
bf_logline "$BF_SLUG" "$PHASE" "$MSG"

MY_WS=$(bf_my_workspace 2>/dev/null || echo "")
[ -n "$MY_WS" ] && bf_wslog "$MY_WS" "$LEVEL" builder "$MSG"
bf_pill "$BF_SLUG" "$PHASE" "$COLOR" "$BF_ORCH_WS"

if [ "$INTERRUPT" = 1 ]; then
  bf_notify "$BF_ORCH_WS" "builder $BF_SLUG · $PHASE" "$MSG"
  if [ -n "${BF_ORCH_PEER:-}" ]; then
    # Peer channel: the builder's Claude delivers the line itself with SendMessage. Typing
    # into the orchestrator's terminal as well would deliver it twice.
    echo "NOW SEND: SendMessage({to: \"$BF_ORCH_PEER\", message: \"[builder $BF_SLUG] $PHASE: $MSG\"})"
  elif bf_ws_exists "$BF_ORCH_WS"; then
    # bf_orch_target, not bf_say_to: a builder is a tab inside the orchestrator's own
    # workspace, so a workspace-only ref can land this message in the BUILDER's prompt.
    bf_send_line "$(bf_orch_target)" "[builder $BF_SLUG] $PHASE: $MSG"
  else
    echo "WARNING: orchestrator workspace $BF_ORCH_WS is gone; message kept in ledger log only" >&2
  fi
fi
echo "reported $PHASE (interrupt=$INTERRUPT): $MSG"
