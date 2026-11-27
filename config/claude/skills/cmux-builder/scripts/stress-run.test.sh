#!/usr/bin/env bash
# stress-run.test.sh [path-to-stress-run.sh]
# A command that finishes well before the deadline must give a pipe reader EOF when it ends, and leave no orphaned
# timer behind. Before the 2026-11-27 fix the timer's `sleep` outlived the wrapper holding its
# stdout, so `stress-run.sh ... | cat` returned only at the deadline (60 s here) and one
# `sleep 60` with parent pid 1 was left. The deadline path is checked too: a command longer
# than the limit is still killed at it.
set -uo pipefail
SR=${1:-$(dirname "$0")/stress-run.sh}
fail=0
orphans() { ps -Ao ppid=,command= | awk '$1==1 && $2=="sleep" && $3=="60"' | wc -l | tr -d ' '; }

before=$(orphans)
s=$(date +%s)
# 3 s, not `true`: the timer must already be inside its sleep when it is stopped, or the bug hides
out=$(bash "$SR" --burners 1 --minutes 1 -- sleep 3 2>/dev/null | cat)
took=$(( $(date +%s) - s ))
sleep 1
left=$(( $(orphans) - before ))
grep -q 'STRESS-DONE rc=0 burners-left=0' <<<"$out" || { echo "FAIL: no clean STRESS-DONE line: ${out##*$'\n'}"; fail=1; }
[ "$took" -le 12 ] || { echo "FAIL: pipe reader got EOF after ${took}s; the command took 3s"; fail=1; }
[ "$left" -le 0 ] || { echo "FAIL: $left orphaned 'sleep 60' timer(s) left with parent pid 1"; fail=1; }
echo "early-exit: eof_after=${took}s orphans_left=${left}"

if [ "${STRESS_TEST_SLOW:-0}" = 1 ]; then
  s=$(date +%s)
  out=$(bash "$SR" --burners 1 --minutes 1 -- sleep 90 2>/dev/null | cat)
  took=$(( $(date +%s) - s ))
  [ "$took" -ge 55 ] && [ "$took" -le 75 ] || { echo "FAIL: deadline kill took ${took}s, want about 60"; fail=1; }
  grep -q 'STRESS-DONE rc=143' <<<"$out" || { echo "FAIL: deadline run did not end rc=143: ${out##*$'\n'}"; fail=1; }
  echo "deadline: killed_after=${took}s"
fi
[ "$fail" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
