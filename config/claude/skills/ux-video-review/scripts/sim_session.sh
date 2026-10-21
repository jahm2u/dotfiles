#!/usr/bin/env bash
# sim_session.sh -- boot, record and shut down the iOS Simulator for a review video, from any repo,
# leaving the Mac the way it was found.
#
#   sim_session.sh boot [name|udid]   remember what is already running, then boot the device
#                                     (default $UX_SIM_DEVICE, else a booted one, else the newest
#                                     iPhone) and wait until it is up; prints its UDID
#   sim_session.sh record out.mp4     start `simctl io recordVideo` on it in the background
#   sim_session.sh stop               finish the recording (SIGINT, so the mp4 is written whole)
#   sim_session.sh end                stop recordings, shut down only the devices booted since
#                                     `boot`, quit Simulator.app if it was not open before
#   sim_session.sh end --all          no `boot` was run: shut down every booted device, quit the app
#                                     (only when no other session is using the Simulator)
#   sim_session.sh run [--device name] -- cmd...
#                                     boot, run cmd (a repo's own runner, e.g. Maestro), always end
#
# Repos keep their own test runners (they boot a Simulator and never shut it down); wrap them in
# `run` instead of copying them here. 2026-10-21: Simulator.app was left open for a day.
# Other builders may be recording at the same time, so `end` touches only what this session started.
set -uo pipefail

STATE_DIR="${TMPDIR:-/tmp}/ux-video-review"
STATE="$STATE_DIR/sim-$(printf '%s' "${BF_SLUG:-$PWD}" | shasum | cut -c1-12)"

booted() { xcrun simctl list devices booted 2>/dev/null | sed -nE 's/.*\(([0-9A-F-]{36})\) \(Booted\).*/\1/p'; }
app_running() { pgrep -xq Simulator; }
state() { [ -f "$STATE" ] && sed -n "s/^$1=//p" "$STATE"; }

pick_device() {   # name or udid -> udid; empty -> a booted device, else the newest available iPhone
  xcrun simctl list devices available -j | python3 -I -c '
import json, sys
want = sys.argv[1]
devs = [(rt, d) for rt, ds in json.load(sys.stdin)["devices"].items() for d in ds]
if want:
    hit = [d for _, d in devs if want in (d["udid"], d["name"])]
else:
    hit = [d for _, d in devs if d["state"] == "Booted"] or \
          [d for _, d in sorted(devs, key=lambda x: x[0], reverse=True) if d["name"].startswith("iPhone")]
print(hit[0]["udid"] if hit else "")' "${1:-${UX_SIM_DEVICE:-}}"
}

begin() {
  mkdir -p "$STATE_DIR"
  [ -f "$STATE" ] && return   # a second boot in the same session keeps the first snapshot
  { app_running && echo "app=1" || echo "app=0"; booted | sed 's/^/dev=/'; } > "$STATE"
}

stop_recording() {
  for pid in $(state rec); do
    kill -INT "$pid" 2>/dev/null || continue
    for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
    echo "recording stopped ($pid)"
  done
  [ -f "$STATE" ] && sed -i '' '/^rec=/d' "$STATE"
}

case "${1:-}" in
  boot)
    begin
    udid=$(pick_device "${2:-}")
    [ -n "$udid" ] || { echo "no Simulator device matches '${2:-${UX_SIM_DEVICE:-iPhone}}'" >&2; exit 2; }
    xcrun simctl boot "$udid" 2>/dev/null || true   # already booted is fine
    xcrun simctl bootstatus "$udid" -b >/dev/null || { echo "device $udid did not boot" >&2; exit 1; }
    sed -i '' '/^use=/d' "$STATE"; echo "use=$udid" >> "$STATE"
    echo "$udid"
    ;;
  record)
    out="${2:?usage: sim_session.sh record out.mp4}"
    udid=$(state use); [ -n "$udid" ] || { echo "run 'sim_session.sh boot' first" >&2; exit 2; }
    mkdir -p "$(dirname "$out")"
    xcrun simctl io "$udid" recordVideo --codec h264 --force "$out" >/dev/null 2>&1 &
    echo "rec=$!" >> "$STATE"
    echo "recording $udid -> $out"
    ;;
  stop)
    stop_recording
    ;;
  end)
    all=0; [ "${2:-}" = "--all" ] && all=1
    if [ ! -f "$STATE" ] && [ $all = 0 ]; then
      echo "no boot state for this session; run 'end --all' if nothing else is using the Simulator" >&2
      exit 2
    fi
    stop_recording
    [ $all = 1 ] && pkill -INT -f "simctl io .* recordVideo" 2>/dev/null && sleep 1
    before=""; app_before=0
    if [ $all = 0 ]; then
      before=$(state dev)
      [ "$(state app)" = 1 ] && app_before=1
    fi
    # An open Simulator.app boots its own current device alongside ours (2026-10-21), sometimes
    # seconds later, so sweep until two passes 3 s apart find nothing new.
    quiet=0
    for _ in $(seq 1 8); do
      found=0
      for udid in $(booted); do
        grep -qx "$udid" <<<"$before" || { found=1; xcrun simctl shutdown "$udid" && echo "shut down $udid"; }
      done
      [ $found = 0 ] && quiet=$((quiet + 1)) || quiet=0
      [ $quiet -ge 2 ] && break
      sleep 3
    done
    if [ $app_before = 0 ] && app_running && [ -z "$(booted)" ]; then
      osascript -e 'quit app "Simulator"' 2>/dev/null || pkill -x Simulator
      echo "quit Simulator.app"
    fi
    rm -f "$STATE"
    ;;
  run)
    shift; dev=""
    [ "${1:-}" = "--device" ] && { dev="$2"; shift 2; }
    [ "${1:-}" = "--" ] && shift
    [ $# -gt 0 ] || { echo "usage: sim_session.sh run [--device name] -- cmd..." >&2; exit 2; }
    "$0" boot "$dev" >/dev/null || exit $?
    trap '"$0" end' EXIT
    trap 'exit 130' INT TERM
    "$@"
    ;;
  *)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
