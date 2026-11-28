#!/bin/bash
# health.sh [--min-free PCT] [--max-swap-mb MB] [--max-load-per-core N] [--max-builders N] [--max-claude N]
# Admission check for one more builder on the MBP. Prints the MBP's numbers and a verdict; exits 0 to
# admit, 1 to refuse (every reason is printed), 2 when the numbers cannot be read (a refusal too).
# launch.sh runs it before creating anything. Why it exists: on 2026-11-27 the MBP kernel-panicked
# (watchdogd starved at 100% of the compressor's segment limit, 38 swapfiles) with ~29 Claude
# sessions on 36 GB; the old gate looked only at memory_pressure's free percentage.
# MBP_HEALTH_FILE=<file> reads the numbers from a file instead of the MBP (tests).
set -euo pipefail
. "$(dirname "$0")/lib.sh"

min_free=${MBP_MIN_FREE:-20} max_swap_mb=${MBP_MAX_SWAP_MB:-4096} max_load_per_core=${MBP_MAX_LOAD_PER_CORE:-2}
max_builders=${MBP_MAX_BUILDERS:-10} max_claude=${MBP_MAX_CLAUDE:-30}
while [ $# -gt 0 ]; do
  case "$1" in
    --min-free) min_free=$2; shift 2 ;;
    --max-swap-mb) max_swap_mb=$2; shift 2 ;;
    --max-load-per-core) max_load_per_core=$2; shift 2 ;;
    --max-builders) max_builders=$2; shift 2 ;;
    --max-claude) max_claude=$2; shift 2 ;;
    *) die "health.sh: unknown argument $1" ;;
  esac
done

if [ -n "${MBP_HEALTH_FILE:-}" ]; then h=$(cat "$MBP_HEALTH_FILE")
else install_remote; h=$(mbb 30 health 2>/dev/null || true); fi
get() { sed -n "s/^$1=//p" <<<"$h" | head -1; }
free=$(get free) swap=$(get swap_mb) load5=$(get load5) ncpu=$(get ncpu) claude=$(get claude) builders=$(get builders)
echo "mbp health: free=${free:-?}% swap=${swap:-?}M load5=${load5:-?} on ${ncpu:-?} cores, claude=${claude:-?}, builders=${builders:-?}"

# An unreadable number is a refusal, never a pass: a gate that cannot see the box must not admit.
for v in free swap load5 ncpu claude builders; do
  [[ "${!v}" =~ ^[0-9]+$ ]] || { echo "REFUSE: could not read $v from the MBP (${!v:-empty})"; exit 2; }
done

why=()
[ "$free" -ge "$min_free" ] || why+=("free memory ${free}% < ${min_free}%")
[ "$swap" -le "$max_swap_mb" ] || why+=("swap in use ${swap}M > ${max_swap_mb}M")
[ "$load5" -le $((ncpu * max_load_per_core)) ] || why+=("5-min load ${load5} > ${max_load_per_core} per core ($((ncpu * max_load_per_core)))")
[ "$builders" -lt "$max_builders" ] || why+=("${builders} builder workspaces, cap ${max_builders}")
[ "$claude" -lt "$max_claude" ] || why+=("${claude} claude processes, cap ${max_claude}")

if [ "${#why[@]}" -gt 0 ]; then
  for w in "${why[@]}"; do echo "REFUSE: $w"; done
  echo "Not launching. Close finished builders first (scripts/sweep.sh), or launch on the Mini."
  exit 1
fi
echo "ADMIT"
