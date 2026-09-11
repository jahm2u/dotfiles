#!/usr/bin/env bash
# approve.sh <slug> [--no] [--watch [seconds]]
#
# Press Enter for the builder. Two things need exactly that keystroke:
#   1. a permission prompt ("Do you want to proceed? 1. Yes 2. No")
#   2. a line typed into its prompt that was never SUBMITTED -- the stall that left three
#      builders dead for three hours on 2026-09-11. Enter submits it and work resumes.
# Default: press Enter once (= Yes) if a prompt is on screen, else say so and exit 1.
#   --no              answer No instead (sends "2" + Enter)
#   --watch [secs]    keep answering Yes to every prompt for up to secs (default 600) or until
#                     the builder is finished (done / merged / failed). Run it in the background
#                     and keep using tell.sh in the foreground: it keeps watching through the
#                     question/checkpoint phases because prompts can follow your answer.
# Read the prompt first (peek.sh) unless you have decided to trust the whole run; --watch is
# for a builder you deliberately launched without auto mode (e.g. --model haiku).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"
[ $# -ge 1 ] || bf_die "usage: approve.sh <slug> [--no] [--watch [seconds]]"
SLUG=$1; shift
ANSWER="yes"; WATCH=0; LIMIT=600
while [ $# -gt 0 ]; do
  case "$1" in
    --no) ANSWER="no"; shift;;
    --watch) WATCH=1; shift; [[ "${1:-}" =~ ^[0-9]+$ ]] && { LIMIT=$1; shift; };;
    *) bf_die "unknown arg $1";;
  esac
done
bf_load "$SLUG"
bf_builder_alive || bf_die "builder $(bf_builder_where) is gone"

prompt_on_screen() {
  cmux read-screen $(bf_target) --lines 15 2>/dev/null | grep -qE 'Do you want to proceed|Do you want to make this edit|Esc to cancel'
}
answer() {
  local what
  what=$(cmux read-screen $(bf_target) --lines 15 2>/dev/null | grep -vE '^\s*$' | grep -B1 -E 'Run shell command|Do you want' | head -2 | tr '\n' ' ' | cut -c1-160)
  if [ "$ANSWER" = "no" ]; then cmux send $(bf_target) -- "2" >/dev/null; sleep 0.3; fi
  cmux send-key $(bf_target) enter >/dev/null
  bf_logline "$SLUG" orchestrator "permission $ANSWER: $what"
  echo "$(date +%T) answered $ANSWER: $what"
}

submit_stalled() {   # returns 0 if it submitted something
  local left i
  left="$(bf_prompt_text "$(bf_target)")"
  [ -n "$left" ] || return 1
  echo "unsubmitted line sitting in the prompt: $left"
  for i in 1 2 3; do
    cmux send-key $(bf_target) enter >/dev/null
    sleep 1
    [ -z "$(bf_prompt_text "$(bf_target)")" ] && {
      bf_logline "$SLUG" orchestrator "submitted stalled prompt line: $left"
      echo "$(date +%T) submitted it"; return 0; }
  done
  echo "WARNING: still unsubmitted after 3 Enter presses — look at it: peek.sh $SLUG" >&2
  return 1
}

if [ $WATCH -eq 0 ]; then
  if prompt_on_screen; then answer; exit 0; fi
  if submit_stalled; then exit 0; fi
  echo "nothing to press Enter on — no permission prompt, prompt is clear (peek.sh $SLUG)"; exit 1
fi
[ "$ANSWER" = "yes" ] || bf_die "--watch only makes sense with Yes"
end=$(( $(date +%s) + LIMIT )); n=0
while [ "$(date +%s)" -lt "$end" ]; do
  if prompt_on_screen; then answer; n=$((n+1)); sleep 2; continue; fi
  if submit_stalled >/dev/null 2>&1; then n=$((n+1)); sleep 2; continue; fi
  st=$(grep '^BF_STATUS=' "$(bf_ledger_file "$SLUG")" | cut -d= -f2)
  case "$st" in merged|done|failed|collected) echo "builder is at '$st'; stopping watch after $n answers"; exit 0;; esac
  sleep 3
done
echo "watch limit reached after $n answers"
