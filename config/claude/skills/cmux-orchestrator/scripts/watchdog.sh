#!/usr/bin/env bash
# watchdog.sh [--interval N] [--idle-polls N] [slug ...]
#
# WHY THIS EXISTS
# ---------------
# The orchestrator only ever learns about a builder when the builder REPORTS. A builder
# that goes idle reports nothing, so silence is indistinguishable from work -- and the
# failure is not rare. Measured across this repo: on 2026-09-11 all three live builders
# had been idle ~3h holding a typed-but-unsubmitted line; on 2026-09-12 builder
# 3561-routing-enable sat idle from 06:25 holding `node scripts/pr-watch.js 3567 --wait`
# in its prompt, while its PR was CONFLICTING with 4 blocking findings and CI had never
# run. In every case the human noticed, not the orchestrator.
#
# So: poll every builder's SCREEN and emit a line only when one needs the orchestrator.
# One stdout line per event, which is what Monitor turns into a wake-up.
#
# ARM IT AS A PERSISTENT MONITOR, right after the first spawn:
#   Monitor(command: "~/.claude/skills/cmux-orchestrator/scripts/watchdog.sh --interval 120 <slug>...",
#           description: "cmux builders -- stalls and idle waits",
#           persistent: true, timeout_ms: 3600000)
#
# STATES (the whole point -- these are NOT the same thing)
#   BUSY     live turn on screen                  -> silent, never emitted
#   STALLED  prompt holds UNSUBMITTED text        -> emitted at once. The builder is not
#            and no live turn                        working and never will be, unaided.
#   IDLE     bare prompt, no live turn            -> emitted after --idle-polls consecutive
#                                                    polls. Often legitimate (awaiting you),
#                                                    which is why it is not instant.
#   GONE     surface missing / builder exited     -> emitted once.
#
# Reads only. It never types into a builder -- deciding what to say is the orchestrator's
# job, and a watchdog that "helpfully" pressed Enter would resubmit stale text blind.
#
# NOTE ON cmux FLAGS: reads via `$(bf_target)` expansion are fine and are what peek.sh
# already does. The Rule 22 variable-expansion trap applies to `send`/`send-key`, which
# this script deliberately does not call.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"

INTERVAL=120
IDLE_POLLS=3
SLUG_LIST=""          # newline-separated; bash 3.2 on macOS has no mapfile and trips
                      # over an empty array under `set -u`, so no arrays here.
while [ $# -gt 0 ]; do
  case "$1" in
    --interval)   INTERVAL="$2"; shift 2 ;;
    --idle-polls) IDLE_POLLS="$2"; shift 2 ;;
    -h|--help)    sed -n '2,40p' "$0"; exit 0 ;;
    *)            SLUG_LIST="$SLUG_LIST$1
"; shift ;;
  esac
done

LEDGER_DIR="$(bf_ledger_dir 2>/dev/null || echo "")"
[ -n "$LEDGER_DIR" ] || LEDGER_DIR="$(pwd)/_bmad/handoff/cmux"
STATE_DIR="$LEDGER_DIR/.watchdog"
mkdir -p "$STATE_DIR" 2>/dev/null || true

# No slugs given: watch every ledger that still has a builder workspace.
discover_slugs() {
  local f base
  for f in "$LEDGER_DIR"/*.env; do
    [ -e "$f" ] || continue
    base="$(basename "$f" .env)"
    echo "$base"
  done
}

emit() { printf '[watchdog] %s\n' "$*"; }

classify() { # screen-text -> prints STATE and, for STALLED, the held text
  local screen="$1" live prompt
  # A live turn renders a spinner line ending in an ellipsis with an elapsed timer.
  # A FINISHED turn renders the same shape but says "done", so exclude it explicitly --
  # that distinction is the whole discriminator and getting it backwards makes every
  # idle builder look busy.
  # `grep -c` EXITS 1 on no match, so a `|| echo 0` fallback fires ON TOP of grep's own
  # "0" and the variable becomes "0\n0" -- which then blows up `[ -gt ]`. wc -l always
  # prints one number and always exits 0.
  live="$(printf '%s\n' "$screen" | grep -E '….*\([0-9]+' | grep -v 'done' | wc -l | tr -d '[:space:]')"
  # Last prompt line, with the marker stripped. Non-empty remainder = unsubmitted text.
  prompt="$(printf '%s\n' "$screen" | sed -n 's/^[[:space:]]*❯[[:space:]]*//p' | tail -1)"
  # Claude's own queued-messages hint is NOT unsubmitted text -- treating it as such is
  # how tell.sh reports a false failure on a delivery that actually landed.
  case "$prompt" in "Press up to edit queued messages"*) prompt="" ;; esac

  if [ "${live:-0}" -gt 0 ]; then echo "BUSY"; return; fi
  if [ -n "$prompt" ]; then echo "STALLED|$prompt"; return; fi
  echo "IDLE"
}

while :; do
  if [ -n "$SLUG_LIST" ]; then WATCH="$SLUG_LIST"; else WATCH="$(discover_slugs)"; fi

  printf '%s\n' "$WATCH" | while IFS= read -r slug; do
    [ -n "$slug" ] || continue
    ( bf_load "$slug" ) >/dev/null 2>&1 || continue
    # shellcheck disable=SC1090
    . "$LEDGER_DIR/$slug.env" 2>/dev/null || continue
    [ -n "${BF_BUILDER_WS:-}" ] || continue

    sf="$STATE_DIR/$slug"
    prev="$(cat "$sf.state" 2>/dev/null || echo "")"
    n="$(cat "$sf.count" 2>/dev/null || echo 0)"

    screen="$(cmux read-screen --workspace "$BF_BUILDER_WS" --surface "$BF_BUILDER_SURFACE" --lines 40 2>/dev/null)"
    if [ -z "$screen" ]; then
      [ "$prev" = "GONE" ] || emit "$slug GONE -- surface $BF_BUILDER_SURFACE unreadable; builder exited or was collected"
      echo GONE >"$sf.state"; echo 0 >"$sf.count"; continue
    fi

    res="$(classify "$screen")"
    state="${res%%|*}"
    held="${res#*|}"; [ "$held" = "$state" ] && held=""

    case "$state" in
      BUSY)
        [ "$prev" = "BUSY" ] || echo 0 >"$sf.count"
        echo BUSY >"$sf.state" ;;
      STALLED)
        # Always actionable, and re-announced every 10th poll so a stall that is not
        # dealt with does not fall silent again.
        if [ "$prev" != "STALLED" ] || [ $(( n % 10 )) -eq 0 ]; then
          emit "$slug STALLED -- idle holding UNSUBMITTED text: ${held:0:120}"
          emit "$slug         it is NOT working. Resubmit or replace via tell.sh, then read the screen back."
        fi
        echo STALLED >"$sf.state"; echo $(( n + 1 )) >"$sf.count" ;;
      IDLE)
        n=$(( n + 1 ))
        # Emit ONCE when it first crosses the threshold, then BACK OFF hard (every 15th
        # poll). A builder waiting on a reviewer round is legitimately idle for long
        # stretches; nagging every IDLE_POLLS turns the watchdog into noise, and a
        # watchdog that cries wolf gets ignored -- which costs more than it saves.
        if [ "$prev" = "IDLE" ] && { [ "$n" -eq "$IDLE_POLLS" ] || { [ "$n" -gt "$IDLE_POLLS" ] && [ $(( n % 15 )) -eq 0 ]; }; }; then
          emit "$slug IDLE for $n polls (~$(( n * INTERVAL / 60 ))m) -- prompt clear, no live turn. Awaiting you, or it stopped without reporting. PR=${BF_PR:-none} status=${BF_STATUS:-?}"
        fi
        echo IDLE >"$sf.state"; echo "$n" >"$sf.count" ;;
    esac
  done
  sleep "$INTERVAL"
done
