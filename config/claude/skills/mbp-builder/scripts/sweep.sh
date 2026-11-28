#!/bin/bash
# sweep.sh [--apply]: find MBP builders that should not be running, and with --apply close the two
# classes that are provably safe. Everything else is reported for a person to decide (Jeff's rule:
# cleanup is scan, then options, then his pick; the Janitor runs this and acts only on SAFE lines).
#
#   DUP     a 🔨 workspace for a slug whose open ledger names a DIFFERENT workspace: an old pane that
#           herdr resumed after a reboot or relaunch, a second Claude in the same worktree. SAFE when
#           its agent is not working; closes only that workspace (worktree and ledger untouched).
#   MERGED  an open ledger whose current branch's PR is merged, HEAD is on a remote branch, and the
#           only uncommitted files are the handoff hook's cache. SAFE when its agent is not working;
#           closes via close.sh --force (worktree, branch, workspace, ledger).
#   ORPHAN  a 🔨 workspace with no open ledger. Reported only.
#   NOPANE  an open ledger with no workspace. Reported only (parked, or its pane was closed).
#   WORKING a DUP or MERGED whose agent is working right now: reported, never closed.
#
# Both classes were closed by hand on 2026-11-27 after the MBP's out-of-memory panic, when herdr
# resumed 9 duplicate panes and 3 merged builders.
# SWEEP_FIXTURE_DIR=<dir> reads workspaces, ledgers and prs (slug<TAB>STATE) from files, and records
# what --apply would close in <dir>/applied instead of closing (tests).
set -euo pipefail
. "$(dirname "$0")/lib.sh"
apply=0; [ "${1:-}" = --apply ] && apply=1
F=${SWEEP_FIXTURE_DIR:-}

if [ -n "$F" ]; then
  wss=$(cat "$F/workspaces"); leds=$(cat "$F/ledgers")
else
  install_remote
  wss=$(mbb 30 workspaces) || die "could not list MBP workspaces"
  leds=$(mbb 600 ledgers) || die "could not read MBP ledgers"
fi

pr_state() { # slug repo branch -> MERGED|OPEN|CLOSED|none
  if [ -n "$F" ]; then awk -F'\t' -v s="$1" '$1==s{print $2; f=1} END{if(!f) print "none"}' "$F/prs"; return; fi
  local tok=""
  case "${2%%/*}" in jeffheartmp|meupatrocinio) tok=$(gh auth token --user jeffheartmp 2>/dev/null || true) ;; esac
  GH_TOKEN=${tok:-${GH_TOKEN:-$(gh auth token 2>/dev/null)}} gh pr list -R "$2" --head "$3" --state all \
    --json state --jq '.[0].state // "none"' 2>/dev/null || echo none
}
# </dev/null: these run inside `while read` loops, and ssh would swallow the rest of the loop's input
# (the first live --apply closed one workspace and silently skipped the next). The fixture path reads
# stdin too, so the test catches a regression.
close_ws() { if [ -n "$F" ]; then cat >/dev/null; echo "ws $1" >> "$F/applied"; else mbb 30 ws-close "$1"; fi; }
close_builder() { if [ -n "$F" ]; then cat >/dev/null; echo "builder $1" >> "$F/applied"; else "$SKILL_DIR/scripts/close.sh" "$1" --force | tail -1; fi; }

# Lookups by awk, not associative arrays: macOS /bin/bash is 3.2.
lws_of() { awk -F'\t' -v s="$1" '$1==s{print $2; exit}' <<<"$leds"; }
orch_of() { awk -F'\t' -v s="$1" '$1==s{print $8; exit}' <<<"$leds"; }
has_ledger() { awk -F'\t' -v s="$1" '$1==s{f=1} END{exit !f}' <<<"$leds"; }
ws_status() { awk -F'\t' -v w="$1" '$1==w{print $3; exit}' <<<"$wss"; }

n_safe=0 n_report=0
safe() { n_safe=$((n_safe + 1)); echo "SAFE    $*"; }
report() { n_report=$((n_report + 1)); echo "$*"; }

while IFS=$'\t' read -r ws slug st; do
  [ -n "$ws" ] || continue
  if ! has_ledger "$slug"; then report "ORPHAN  $ws $slug ($st): no open ledger"; continue; fi
  lws=$(lws_of "$slug"); orch=$(orch_of "$slug")
  [ "$ws" = "$lws" ] && continue
  if [ "$st" = working ]; then report "WORKING $ws $slug: duplicate of $lws but working now (orch $orch)"; continue; fi
  safe "DUP $ws $slug ($st): ledger workspace is $lws (orch $orch)"
  [ "$apply" = 1 ] && close_ws "$ws" </dev/null
done <<<"$wss"

while IFS=$'\t' read -r slug lws repo _lbr cur dirty onr orch; do
  [ -n "$slug" ] || continue
  st=$(ws_status "$lws")
  [ -n "$st" ] || report "NOPANE  $slug: ledger workspace $lws is not open (orch $orch)"
  [ "$cur" != - ] || continue
  prs=$(pr_state "$slug" "$repo" "$cur")
  [ "$prs" = MERGED ] || continue
  if [ "$dirty" != 0 ] || [ "$onr" != yes ]; then
    report "MERGED? $slug: PR merged but dirty=$dirty on-remote=$onr, needs a look (orch $orch)"; continue
  fi
  if [ "$st" = working ]; then report "WORKING $slug: PR merged but agent working now (orch $orch)"; continue; fi
  safe "MERGED $slug ($cur): PR merged, HEAD on remote, clean (orch $orch)"
  [ "$apply" = 1 ] && close_builder "$slug" </dev/null
done <<<"$leds"

echo "sweep: $n_safe safe to close$([ "$apply" = 1 ] && echo ', closed' || echo ' (dry run; --apply closes them)'), $n_report for a person"
