#!/usr/bin/env bash
# Put a transparent mascot cutout on a status-coloured square, for previewing widget states.
# Usage: status-card.sh <cutout.png> <good|normal|urgent|done|away|#RRGGBB> <out.png> [size=400]
set -euo pipefail
cut=$1; status=$2; out=$3; size=${4:-400}
case "$status" in
  good|done) hex=2BB673 ;;   # green: things are going well / all done
  normal)    hex=3B82F6 ;;   # blue: chores waiting, on time (orange is too close to red; Jeff 2026-10-18)
  urgent)    hex=E5484D ;;   # red: really overdue or about to run out of time
  away)      hex=8B93A7 ;;   # grey-blue: a custody day away, nothing expected
  \#*)       hex=${status#\#} ;;
  *) echo "unknown status: $status" >&2; exit 2 ;;
esac
inner=$(( size * 95 / 100 )); pad=$(( (size - inner) / 2 ))
ffmpeg -v error -y -f lavfi -i "color=c=0x${hex}:s=${size}x${size}" -i "$cut" \
  -filter_complex "[1]scale=${inner}:${inner}[c];[0][c]overlay=${pad}:${pad}" -frames:v 1 "$out"
echo "wrote $out"
