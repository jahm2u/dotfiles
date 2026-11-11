#!/usr/bin/env bash
# rotate.sh <slug> ask      ask the builder for a handoff (no interview), then it replies CHECKPOINTED
# rotate.sh <slug> finish   verify the handoff, /clear the builder in place, reseed it from the handoff
# rotate.sh <slug> status   context %, handoff age, whether it has answered
#
# WHY THIS EXISTS
# ---------------
# On 2026-11-11 an ajudaduda builder (support-inbox) was at 97% of its window after five
# rounds of work and still being handed questions. Builders never act on "hand off at ~70%"
# themselves, so the ORCHESTRATOR rotates them at 60% (watchdog.sh emits CONTEXT). This is
# the same pattern seatctl uses for baba (seatctl.py fixed_checkpoint_prompt / restart_fixed):
# handoff written fresh, a one-word reply, restart, reseed. A builder can /clear in place,
# which keeps its BF_* environment, pane and MCP config, so nothing is relaunched.
#
# Never `finish` while the builder is mid-turn, and never without a handoff written AFTER the
# `ask`: a /clear without one throws the builder's whole state away.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"
SLUG=${1:?usage: rotate.sh <slug> ask|finish|status}; ACT=${2:?usage: rotate.sh <slug> ask|finish|status}
bf_load "$SLUG"
[ -n "${BF_WORKTREE:-}" ] || bf_die "ledger for $SLUG has no BF_WORKTREE"
HANDOFF="$BF_WORKTREE/_bmad/handoff/HANDOFF-latest.md"
LD=$(bf_ledger_dir); MARK="$LD/.watchdog/$SLUG.rotate-asked"; KEEP="$LD/$SLUG.handoff.md"
mkdir -p "$LD/.watchdog"
WORD=CHECKPOINTED
ctx() { "$HERE/ctx.sh" --path "$BF_WORKTREE" --model "${BF_MODEL:-opus[1m]}"; }
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

case "$ACT" in
  ask)
    bf_builder_alive || bf_die "builder $(bf_builder_where) is gone"
    read -r _ pct _ <<<"$(ctx)"
    date +%s >"$MARK"
    bf_say_to_builder "[orchestrator] Context rotation: you are at ${pct}% of your window. Finish only the step in hand (commit and push WIP to your branch if the tree is dirty), then write your handoff with the handoff skill and SKIP its interview: no questions, record open decisions as next steps with your recommendation. It must name the spec ($BF_SPEC), the branch, the head sha, the PR if any, what is done, what is next, and anything you were waiting on. Write it to $HANDOFF (only that file counts, and only if written after this message). Then reply with the single word $WORD and stop. I will /clear you and reseed you from it."
    bf_logline "$SLUG" orchestrator "rotation asked at ${pct}%"
    echo "asked $SLUG for a handoff at ${pct}%; run 'rotate.sh $SLUG finish' once it replies $WORD" ;;
  status)
    read -r _ pct tok win tr <<<"$(ctx)"
    asked=$(cat "$MARK" 2>/dev/null || echo 0)
    echo "$SLUG context ${pct}% ($tok/$win) transcript $(basename "$tr")"
    if [ -f "$HANDOFF" ]; then echo "handoff $HANDOFF written $(( $(date +%s) - $(mtime "$HANDOFF") ))s ago; $([ "$(mtime "$HANDOFF")" -gt "$asked" ] && echo fresh || echo 'OLDER than the ask')"
    else echo "handoff: none at $HANDOFF"; fi
    bf_read "$(bf_target)" 30 2>/dev/null | grep -q "$WORD" && echo "screen: $WORD seen" || echo "screen: no $WORD yet" ;;
  finish)
    asked=$(cat "$MARK" 2>/dev/null || echo 0)
    [ "$asked" -gt 0 ] || bf_die "no 'ask' recorded for $SLUG; run 'rotate.sh $SLUG ask' first"
    [ -f "$HANDOFF" ] || bf_die "no handoff at $HANDOFF; not clearing"
    [ "$(mtime "$HANDOFF")" -gt "$asked" ] || bf_die "$HANDOFF is older than the ask; not clearing"
    [ "$(wc -c <"$HANDOFF")" -gt 400 ] || bf_die "$HANDOFF is under 400 bytes; too thin to resume from, not clearing"
    st=$(bf_builder_state 2>/dev/null || echo unknown)
    [ "$st" = idle ] || bf_die "builder is '$st', not idle; /clear only an idle builder that has replied $WORD"
    bf_read "$(bf_target)" 30 2>/dev/null | grep -q "$WORD" || bf_die "no $WORD on the builder's screen yet"
    read -r _ before _ _ oldtr <<<"$(ctx)"
    cp "$HANDOFF" "$KEEP"
    bf_say_to_builder "/clear"
    for _ in $(seq 1 30); do
      sleep 2
      read -r _ pct _ _ tr <<<"$(ctx)"
      [ "$tr" != "$oldtr" ] && break
    done
    bf_say_to_builder "[orchestrator] You were rotated at a context ceiling (${before}%). You are still /cmux-builder for $SLUG: your BF_* environment is unchanged. Read $KEEP (a copy of your handoff) and your spec $BF_SPEC first, then continue from the handoff's next steps and report through report.sh as before."
    for _ in $(seq 1 30); do
      sleep 2
      read -r _ pct _ _ tr <<<"$(ctx)"
      [ "$tr" != "$oldtr" ] && [ "$pct" != "?" ] && break
    done
    rm -f "$MARK"
    if [ "$tr" = "$oldtr" ]; then
      bf_logline "$SLUG" orchestrator "rotation: /clear sent but the transcript did not change; CHECK THE SCREEN"
      bf_die "the transcript did not change after /clear; peek.sh $SLUG and check by hand"
    fi
    bf_logline "$SLUG" orchestrator "rotated: ${before}% -> ${pct}%, reseeded from $KEEP"
    echo "rotated $SLUG: ${before}% -> ${pct}% (new transcript $(basename "$tr")); handoff kept at $KEEP" ;;
  *) bf_die "unknown action $ACT (ask|finish|status)" ;;
esac
