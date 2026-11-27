#!/usr/bin/env bash
# stress-run.sh --burners N --minutes M -- <command...>
#
# The ONLY way a builder puts CPU pressure on this host (a flake repro under load).
# Rule (Jeff, 2026-11-14): a builder's raw `yes`/busy-loop burners took the Mini to load 55
# and blocked another builder's spawn. This wrapper caps the pressure, allows one stress
# run on the host at a time, and guarantees the burners die with it.
#   caps: burners <= cores/3, minutes <= 15 (the command is killed at the deadline)
#   refuses: a second concurrent stress run; a host already above 1.5 x cores of load
# Prints `STRESS-DONE rc=<rc> burners-left=<n>`; burners-left must be 0.
set -uo pipefail
N=; M=
while [ $# -gt 0 ]; do case "$1" in
  --burners) N=$2; shift 2;; --minutes) M=$2; shift 2;; --) shift; break;;
  *) echo "usage: stress-run.sh --burners N --minutes M -- <command...>" >&2; exit 64;; esac; done
[ -n "$N" ] && [ -n "$M" ] && [ $# -gt 0 ] || { echo "usage: stress-run.sh --burners N --minutes M -- <command...>" >&2; exit 64; }
case "$N$M" in *[!0-9]*) echo "REFUSED: burners and minutes are whole numbers" >&2; exit 64;; esac
CORES=$(sysctl -n hw.ncpu 2>/dev/null || nproc)
MAXB=$(( CORES / 3 )); [ "$MAXB" -ge 1 ] || MAXB=1
[ "$N" -le "$MAXB" ] || { echo "REFUSED: $N burners; cap is $MAXB (cores/3 of $CORES). Use parallel runs of the test itself for more contention." >&2; exit 65; }
[ "$M" -ge 1 ] && [ "$M" -le 15 ] || { echo "REFUSED: $M minutes; cap is 15" >&2; exit 65; }
LOAD=$( (sysctl -n vm.loadavg 2>/dev/null || cat /proc/loadavg) | tr -d '{}' | awk '{print int($1)}')
[ "$LOAD" -le $(( CORES * 3 / 2 )) ] || { echo "REFUSED: host load $LOAD is already above 1.5 x $CORES cores; the host is loaded enough, run without burners" >&2; exit 66; }
LOCK=${TMPDIR:-/tmp}/bf-stress-run.lock
if ! mkdir "$LOCK" 2>/dev/null; then
  if kill -0 "$(cat "$LOCK/pid" 2>/dev/null)" 2>/dev/null; then echo "REFUSED: another stress run is live (pid $(cat "$LOCK/pid"), ${BF_SLUG:-?} must wait)" >&2; exit 67; fi
  rm -rf "$LOCK"; mkdir "$LOCK" || exit 67
fi
echo $$ > "$LOCK/pid"
PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done; [ -n "${CMD:-}" ] && kill -9 "$CMD" 2>/dev/null; [ -n "${TIMER:-}" ] && kill "$TIMER" 2>/dev/null; rm -rf "$LOCK"; }
trap 'cleanup; echo "STRESS-ABORTED by signal; burners killed, lock removed"; exit 143' INT TERM HUP
i=0; while [ "$i" -lt "$N" ]; do nice -n 19 sh -c 'while :; do :; done' & PIDS+=($!); i=$((i+1)); done
echo "STRESS-START burners=$N minutes<=$M slug=${BF_SLUG:-none} pids=${PIDS[*]:-}"
"$@" & CMD=$!
# The timer owns its sleep and kills it when it is told to stop, and its fds point at /dev/null,
# so a command that finishes early never leaves an orphaned sleep holding our stdout (a
# `stress-run.sh ... | tail` reader got EOF only at the 15-minute deadline, hive 2026-11-27).
( trap - INT TERM HUP; sleep $(( M * 60 )) & SP=$!; trap 'kill "$SP" 2>/dev/null; exit 0' TERM
  wait "$SP" && kill -TERM "$CMD" 2>/dev/null ) </dev/null >/dev/null 2>&1 & TIMER=$!
wait "$CMD"; RC=$?
kill "$TIMER" 2>/dev/null
LEFT=0; for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done; sleep 0.3
for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill -0 "$p" 2>/dev/null && LEFT=$((LEFT+1)); done
CMD=; rm -rf "$LOCK"
echo "STRESS-DONE rc=$RC burners-left=$LEFT"
[ "$LEFT" -eq 0 ] || exit 70
exit "$RC"
