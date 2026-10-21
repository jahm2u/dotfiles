#!/usr/bin/env bash
# sim_session.sh -- leave the iOS Simulator the way you found it after a recording.
#
#   sim_session.sh begin        before booting a Simulator: remembers what was already running
#   sim_session.sh end          after the last recording: stops `simctl io recordVideo`, shuts down
#                               only the devices booted since `begin`, quits Simulator.app if it
#                               was not open before
#   sim_session.sh end --all    no `begin` was run: shut down every booted device and quit the app
#                               (only when no other session is recording on this Mac)
#
# Recordings left Simulator.app open for a day with nothing booted (2026-10-21). Other builders
# may be recording at the same time, so `end` touches only what this session started.
set -uo pipefail

STATE_DIR="${TMPDIR:-/tmp}/ux-video-review"
STATE="$STATE_DIR/sim-$(printf '%s' "${BF_SLUG:-$PWD}" | shasum | cut -c1-12)"

booted() { xcrun simctl list devices booted 2>/dev/null | sed -nE 's/.*\(([0-9A-F-]{36})\) \(Booted\).*/\1/p'; }
app_running() { pgrep -xq Simulator; }

case "${1:-}" in
  begin)
    mkdir -p "$STATE_DIR"
    { app_running && echo "app=1" || echo "app=0"; booted | sed 's/^/dev=/'; } > "$STATE"
    echo "sim session begun ($(grep -c '^dev=' "$STATE") already booted)"
    ;;
  end)
    all=0; [ "${2:-}" = "--all" ] && all=1
    if [ ! -f "$STATE" ] && [ $all = 0 ]; then
      echo "no begin state for this session; run 'end --all' if nothing else is recording" >&2
      exit 2
    fi
    pkill -INT -f "simctl io .* recordVideo" 2>/dev/null && sleep 1   # INT lets it finish the mp4
    before=""; app_before=0
    if [ $all = 0 ]; then
      before=$(sed -n 's/^dev=//p' "$STATE")
      grep -q '^app=1' "$STATE" && app_before=1
    fi
    for udid in $(booted); do
      if ! grep -qx "$udid" <<<"$before"; then
        xcrun simctl shutdown "$udid" && echo "shut down $udid"
      fi
    done
    if [ $app_before = 0 ] && app_running && [ -z "$(booted)" ]; then
      osascript -e 'quit app "Simulator"' 2>/dev/null || pkill -x Simulator
      echo "quit Simulator.app"
    fi
    rm -f "$STATE"
    ;;
  *)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
