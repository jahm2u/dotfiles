#!/usr/bin/env bash
# Shared helpers for the cmux-orchestrator / cmux-builder / cmux-trash-collector skills.
# Source this file; do not execute it.
#
# Ledger: one KEY=VALUE file per builder at <primary-repo>/_bmad/handoff/cmux/<slug>.env
# plus an append-only <slug>.log. The primary repo is resolved from git's common dir, so
# this works from inside any worktree of the same repo.

export CMUX_QUIET=1

bf_die() { echo "ERROR: $*" >&2; exit 1; }

# Absolute path of the PRIMARY checkout (the one that owns .git), from anywhere in the repo.
bf_primary_root() {
  local common
  common=$(git rev-parse --git-common-dir 2>/dev/null) || bf_die "not inside a git repo"
  common=$(cd "$common" && pwd -P)
  dirname "$common"
}

bf_ledger_dir() {
  local root; root=$(bf_primary_root)
  local d="$root/_bmad/handoff/cmux"
  mkdir -p "$d/archive"
  echo "$d"
}

bf_ledger_file() { echo "$(bf_ledger_dir)/$1.env"; }
bf_log_file()    { echo "$(bf_ledger_dir)/$1.log"; }

# Load a ledger into the current shell (exports BF_* vars).
bf_load() {
  local f; f=$(bf_ledger_file "$1")
  [ -f "$f" ] || bf_die "no ledger for slug '$1' at $f"
  # A pre-herdr ledger has no BF_MUX line, and a herdr builder's own env exports
  # BF_MUX=herdr -- without this unset, that ledger would load as herdr.
  unset BF_MUX BF_HERDR_SOCKET BF_BUILDER_TAB BF_BUILDER_AGENT
  set -a; # shellcheck disable=SC1090
  . "$f"; set +a
  bf_herdr_env
}

# Set or replace one KEY in a ledger file.
bf_set() { # slug key value
  local f; f=$(bf_ledger_file "$1")
  local key=$2 val=$3
  touch "$f"
  if grep -q "^${key}=" "$f"; then
    # portable in-place replace (macOS sed needs the '' arg)
    sed -i '' "s|^${key}=.*|${key}=${val}|" "$f"
  else
    echo "${key}=${val}" >> "$f"
  fi
}

bf_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Append a line to the builder's log.
bf_logline() { # slug phase msg
  echo "$(bf_now)|$2|$3" >> "$(bf_log_file "$1")"
}

# --- multiplexer backend ----------------------------------------------------------------
# Two backends: cmux (the original) and herdr. The backend is decided ONCE, at spawn, from
# the orchestrator's own terminal (HERDR_ENV=1 means it is a herdr pane) and recorded in the
# ledger as BF_MUX. Ledgers written before the herdr port carry no BF_MUX and stay cmux.
# Every helper below dispatches on it, so call sites never need to know which one they drive.
#
# In herdr a "target" is a bare pane id (w1:p3) instead of cmux's --workspace/--surface flag
# string. herdr ids are scoped to one server, so the ledger also records the server socket
# (BF_HERDR_SOCKET) and bf_load exports it: a script run from ANOTHER herdr session, or from
# outside herdr entirely, still reaches the right server.
bf_mux() { echo "${BF_MUX:-cmux}"; }
bf_is_herdr() { [ "${BF_MUX:-cmux}" = herdr ]; }
bf_caller_is_herdr() { [ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_PANE_ID:-}" ]; }
bf_herdr_env() { # point the herdr CLI at the ledger's server
  if bf_is_herdr && [ -n "${BF_HERDR_SOCKET:-}" ]; then export HERDR_SOCKET_PATH="$BF_HERDR_SOCKET"; fi
  return 0
}

# Workspace ref of the terminal this script runs in (e.g. workspace:16, or w1 in herdr).
# Keyed on the CALLER's terminal, not the ledger: ls.sh compares it against BF_ORCH_WS.
bf_my_workspace() {
  if bf_caller_is_herdr; then echo "$HERDR_WORKSPACE_ID"; return 0; fi
  cmux identify --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["caller"]["workspace_ref"])'
}

# The CALLER's own surface (herdr: its pane). Needed because a builder is a tab INSIDE the
# orchestrator's workspace, so a workspace ref alone no longer identifies which you mean.
bf_my_surface() {
  if bf_caller_is_herdr; then echo "$HERDR_PANE_ID"; return 0; fi
  cmux identify --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["caller"]["surface_ref"])'
}

# Last N rendered lines of a target's terminal. The one read primitive every script uses.
bf_read() { # target lines
  if bf_is_herdr; then
    herdr pane read "$1" --source recent --lines "${2:-40}" 2>/dev/null
  else
    cmux read-screen $1 --lines "${2:-40}" 2>/dev/null
  fi
}

# Text currently sitting UNSUBMITTED in a prompt (empty when the prompt is clear).
# No `❯` on screen at all (mid-turn, or a dialog) also reads as empty -- the safe
# direction, since a false "still there" would loop on Enter.
bf_prompt_text() { # target-flags
  bf_read "$1" 14 \
    | sed -n 's/^[[:space:]]*❯[[:space:]]*//p' | tail -1 \
    | grep -v '^Press up to edit queued messages' || true
}

# Press one key in a target (enter, esc, 2, ...).
bf_send_key() { # target key
  if bf_is_herdr; then herdr pane send-keys "$1" "$2" >/dev/null 2>&1
  else cmux send-key $1 "$2" >/dev/null; fi
}

# herdr delivery. `herdr agent prompt` writes text + Enter as one ordered submission
# (bracketed paste aware), so none of the cmux Enter-retry machinery below applies. It
# REFUSES an agent sitting at an approval/question dialog (agent_blocked) before typing
# anything -- retry for about a minute, then give up loudly; the caller's ledger log keeps
# the message either way. A pane with no recognised agent (agent_not_found) gets raw
# text + Enter, which is what a shell or a stand-in needs.
# Long text goes to a file and only its path is sent: the same rule as cmux, where a long
# `send` silently loses its middle.
bf_herdr_send_line() { # pane text
  local pane="$1" text="$2" out i f
  if [ "${#text}" -gt 800 ]; then
    f="${TMPDIR:-/tmp}/bf-msg-$(date +%s)-$$.md"
    printf '%s\n' "$text" > "$f"
    text="${text:0:160}... [message too long for the prompt; read it in full: $f]"
  fi
  for i in 1 2 3 4 5 6 7; do
    if out=$(herdr agent prompt "$pane" "$text" 2>&1); then return 0; fi
    case "$out" in
      *agent_blocked*) sleep 10 ;;
      *agent_not_found*)
        herdr pane send-text "$pane" "$text" >/dev/null 2>&1 || return 1
        sleep 0.5
        herdr pane send-keys "$pane" enter >/dev/null 2>&1
        return $? ;;
      *) echo "WARNING: herdr agent prompt $pane failed: $out" >&2; return 1 ;;
    esac
  done
  echo "WARNING: $pane stayed at a dialog for ~70s; message NOT delivered: ${text:0:120}" >&2
  return 1
}

# Type a line into a Claude prompt and SUBMIT it -- verifying the submit landed.
#
# Two steps on purpose: text first, Enter after a beat. A trailing \n inside `send`
# is treated as paste-with-newline by the TUI and does not always submit.
#
# But the Enter itself goes missing often enough to matter. On 2026-09-11 ALL THREE
# live builders in BabaFlow had been idle ~3h holding a typed-but-unsubmitted line,
# one of them the literal "[orchestrator] check round 7" that tell.sh had typed. An
# idle builder logs nothing, so nothing noticed. Hence: clear any stale fragment
# first (otherwise the new text CONCATENATES onto it), then confirm the prompt came
# back empty, re-pressing Enter up to 3 times before failing loudly.
# NOTE (2026-09-11): clearing a stale prompt is NOT actually solved here.
#
# Two separate defects, both verified, neither fixed because the fix needs bf_target to
# stop returning flags as a STRING:
#   1. `ctrl+u` does not clear a Claude TUI prompt. cmux returns OK; the text stays.
#      Repeated `backspace` DOES work -- but see 2 before writing that loop.
#   2. cmux ignores flags that arrive via SHELL VARIABLE EXPANSION. `cmux send $target ...`
#      lands on the CALLER's own surface while the byte-identical literal form lands on the
#      target. So a backspace loop written as `cmux send-key $target backspace` would erase
#      YOUR OWN prompt, not the builder's. That is why this is a comment and not code.
# CORRECTION (2026-09-12), measured -- two of the claims above are wrong:
#   * `cmux send` REPLACES the prompt contents, it does NOT concatenate. A stalled builder
#     holding `node scripts/pr-watch.js 3567 --wait` took a fresh `cmux send` and the old
#     text was gone. So stale text is not a reason to avoid tell.sh.
#   * `cmux send-key <literal-flags> enter` can return OK and submit NOTHING -- four
#     attempts in a row did nothing on a stalled surface, while tell.sh to that same
#     surface submitted first time. The literal-vs-variable rule is NOT the whole story.
# And the verification below FAILS FALSE: it reads Claude's own "Press up to edit queued
# messages" hint as unsubmitted text, so a message queued while the builder is mid-turn
# reports as a failure and is then delivered anyway. Three such warnings on 2026-09-12,
# all three delivered exactly once.
# Consequence, both directions: `tell.sh`'s "sent to ..." is an echo of intent, and its
# non-zero exit is not proof of failure. READ THE BUILDER'S SCREEN BACK -- bare prompt
# plus your text in the transcript means delivered, whatever the exit code said.
bf_send_line() { # target-flags text
  local target="$1" text="$2" i left
  if bf_is_herdr; then bf_herdr_send_line "$target" "$text"; return $?; fi
  cmux send-key $target ctrl+u >/dev/null 2>&1 || true
  cmux send $target -- "$text" >/dev/null
  sleep 0.7
  for i in 1 2 3; do
    cmux send-key $target enter >/dev/null
    sleep 1.0
    left="$(bf_prompt_text "$target")"
    [ -z "$left" ] && return 0
  done
  echo "WARNING: prompt still holds unsubmitted text after 3 Enter attempts: $left" >&2
  return 1
}

bf_say_to() { # workspace-ref text (herdr: a pane id or agent name)
  if bf_is_herdr; then bf_send_line "$1" "$2"; return $?; fi
  bf_send_line "--workspace $1" "$2"
}

# --- orchestrator addressing ----------------------------------------------------------
# Mirror of bf_target for the OTHER direction. Since builders-as-tabs a builder shares
# its orchestrator's workspace, so `--workspace $BF_ORCH_WS` is ambiguous and cmux can
# deliver a builder's own report into its own prompt -- observed repeatedly on
# 2026-09-12, where a converged PR sat unnoticed because its report never arrived.
# BF_ORCH_SURFACE disambiguates. Ledgers written before this carry no surface and fall
# back to the old workspace-only form, so builders spawned earlier keep working.
bf_orch_target() {
  if bf_is_herdr; then printf '%s' "${BF_ORCH_SURFACE:-}"; return 0; fi
  if [ -n "${BF_ORCH_SURFACE:-}" ]; then
    printf -- '--workspace %s --surface %s' "${BF_ORCH_WS:-}" "$BF_ORCH_SURFACE"
  else
    printf -- '--workspace %s' "${BF_ORCH_WS:-}"
  fi
}

# True if the workspace ref still exists.
bf_ws_exists() {
  if bf_is_herdr; then herdr workspace get "$1" >/dev/null 2>&1; return $?; fi
  cmux list-workspaces 2>/dev/null | grep -q "^\*\? *$1 "
}

# --- builder addressing ---------------------------------------------------------------
# A builder lives EITHER as a tab (surface) inside its orchestrator's own workspace --
# the default since builders-as-tabs -- or, for --place workspace and for every ledger
# written before that, as a workspace of its own.
#
# Tab mode stores BF_BUILDER_SURFACE plus BF_BUILDER_WS, where BF_BUILDER_WS is the HOST
# workspace (the orchestrator's), NOT a workspace of the builder's own. Legacy ledgers
# carry BF_BUILDER_WS alone and no surface. bf_target emits the right cmux flags for
# either shape so no call site has to know which it is -- that is what keeps builders
# spawned before this change supervisable by the scripts after it.
bf_target() {
  if bf_is_herdr; then printf '%s' "${BF_BUILDER_SURFACE:-}"; return 0; fi
  if [ -n "${BF_BUILDER_SURFACE:-}" ]; then
    printf -- '--workspace %s --surface %s' "$BF_BUILDER_WS" "$BF_BUILDER_SURFACE"
  else
    printf -- '--workspace %s' "${BF_BUILDER_WS:-}"
  fi
}

# True if the builder is still there, whichever shape it has.
bf_builder_alive() {
  if bf_is_herdr; then
    [ -n "${BF_BUILDER_SURFACE:-}" ] && herdr pane get "$BF_BUILDER_SURFACE" >/dev/null 2>&1
    return $?
  fi
  if [ -n "${BF_BUILDER_SURFACE:-}" ]; then
    [ -n "${BF_BUILDER_WS:-}" ] || return 1
    cmux list-pane-surfaces --workspace "$BF_BUILDER_WS" 2>/dev/null \
      | grep -q "^\*\? *$BF_BUILDER_SURFACE "
  else
    bf_ws_exists "${BF_BUILDER_WS:-x}"
  fi
}

# The retry line off a rate-limited builder's screen ("Retry in 1830s."), for messages.
bf_rate_limit_note() {
  bf_read "$(bf_target)" 18 \
    | grep -oE '(Retry in [0-9]+s|All [0-9]+ accounts exhausted|usage limit reached[^.]*)' \
    | tr '\n' ' ' | sed 's/ $//'
}

# Human-readable location, for messages.
bf_builder_where() {
  if bf_is_herdr; then echo "${BF_BUILDER_SURFACE:-unknown} (herdr${BF_BUILDER_TAB:+ tab $BF_BUILDER_TAB} in ${BF_BUILDER_WS:-?})"; return 0; fi
  if [ -n "${BF_BUILDER_SURFACE:-}" ]; then echo "$BF_BUILDER_SURFACE (tab in $BF_BUILDER_WS)"
  else echo "${BF_BUILDER_WS:-unknown}"; fi
}

# Type a line into the builder's Claude prompt, wherever it lives.
#
# KEEP IT SHORT. `cmux send` SILENTLY DROPS TEXT from a long message -- verified 2026-09-11,
# a ~1,900-char brief arrived with a large middle span missing, start and tail intact, no
# error at either end. For anything longer than a few lines, write a file and send the path.
bf_say_to_builder() { # text
  bf_send_line "$(bf_target)" "$1"
}

# What the builder is ACTUALLY doing right now, read off its screen:
#   busy        a turn is in flight
#   rate-limited killed mid-turn by a 429 / exhausted quota, with a retry timer
#   prompt      stopped on a permission dialog (approve.sh answers it)
#   unsubmitted idle, with text sitting in its prompt that was never submitted
#   idle        finished its turn, prompt clear, waiting on you
#   gone        the tab/workspace is no longer there
# The last logged phase CANNOT tell these apart -- an idle builder logs nothing,
# which is exactly how three builders sat dead for three hours after `pr-open`.
bf_builder_state() {
  local scr left
  bf_builder_alive || { echo gone; return 0; }
  if bf_is_herdr; then bf_herdr_builder_state; return 0; fi
  scr="$(cmux read-screen $(bf_target) --lines 18 2>/dev/null)"
  case "$scr" in
    *"Do you want to proceed"*|*"Do you want to make this edit"*) echo prompt; return 0;;
  esac
  # Checked BEFORE busy: a 429 can leave a stale spinner on screen, and "waiting out a
  # quota timer" is a different decision from "working". A builder killed mid-turn this
  # way CANNOT run report.sh, so its ledger freezes on its last phase -- 2950 sat reading
  # "pushing", which looks like progress, through 30 minutes of dead air.
  if printf '%s' "$scr" | grep -qE 'API Error.*429|\(429\)|accounts exhausted|usage limit reached'; then
    echo rate-limited; return 0
  fi
  # A turn in flight always renders a live token counter / interrupt hint.
  if printf '%s' "$scr" | grep -qE 'esc to interrupt|·[[:space:]]*↓[[:space:]]*[0-9]'; then
    echo busy; return 0
  fi
  left="$(bf_prompt_text "$(bf_target)")"
  [ -n "$left" ] && { echo unsubmitted; return 0; }
  echo idle
}

# herdr version of the above. herdr classifies the agent itself (idle/working/blocked/
# done/unknown via its Claude hook), which replaces the spinner heuristics; the screen is
# still read for the two things herdr cannot know: a 429 kill, and unsubmitted text.
# No agent in the pane any more (Claude exited back to the shell) reads as gone -- for
# every caller that means the same thing: nobody there to talk to.
bf_herdr_builder_state() {
  local st scr left
  st=$(herdr agent get "$BF_BUILDER_SURFACE" 2>/dev/null | python3 -c '
import json,sys
r=json.load(sys.stdin).get("result",{})
a=r.get("agent") or r
print(a.get("agent_status") or a.get("status") or "unknown")' 2>/dev/null) || { echo gone; return 0; }
  scr="$(bf_read "$BF_BUILDER_SURFACE" 18)"
  if printf '%s' "$scr" | grep -qE 'API Error.*429|\(429\)|accounts exhausted|usage limit reached'; then
    echo rate-limited; return 0
  fi
  case "$st" in
    working) echo busy; return 0;;
    blocked) echo prompt; return 0;;
    unknown)
      if printf '%s' "$scr" | grep -qE 'esc to interrupt|·[[:space:]]*↓[[:space:]]*[0-9]'; then echo busy; return 0; fi
      case "$scr" in *"Do you want to proceed"*|*"Do you want to make this edit"*) echo prompt; return 0;; esac;;
  esac
  left="$(bf_prompt_text "$BF_BUILDER_SURFACE")"
  [ -n "$left" ] && { echo unsubmitted; return 0; }
  echo idle
}

# --- status pills / notifications / sidebar log -----------------------------------------
# Cosmetic, never fatal. cmux: a pill on the orchestrator's sidebar row, a macOS
# notification, a line in the workspace log. herdr: a token on the orchestrator's
# workspace (display-only metadata) and a herdr notification; it has no log feed.
bf_pill() { # slug phase color orch-ws
  if bf_is_herdr; then
    herdr workspace report-metadata "$4" --source "bf-$1" --token "bf-$1=$2" >/dev/null 2>&1 || true
  else
    cmux set-status "bf-$1" "$2" --workspace "$4" --icon hammer --color "$3" --priority 50 >/dev/null 2>&1 || true
  fi
}
bf_pill_clear() { # slug orch-ws
  if bf_is_herdr; then
    herdr workspace report-metadata "$2" --source "bf-$1" --clear-token "bf-$1" >/dev/null 2>&1 || true
  else
    cmux clear-status "bf-$1" --workspace "$2" >/dev/null 2>&1 || true
  fi
}
bf_notify() { # orch-ws title body
  if bf_is_herdr; then
    herdr notification show "$2" --body "$3" --sound request >/dev/null 2>&1 || true
  else
    cmux notify --workspace "$1" --title "$2" --body "$3" >/dev/null 2>&1 || true
  fi
}
bf_wslog() { # ws level source msg
  bf_is_herdr && return 0
  if [ -n "$2" ]; then cmux log --workspace "$1" --level "$2" --source "$3" -- "$4" >/dev/null 2>&1 || true
  else cmux log --workspace "$1" --source "$3" -- "$4" >/dev/null 2>&1 || true; fi
}

# Close what a builder occupies. Tab mode closes the TAB only -- in tab mode BF_BUILDER_WS
# is the orchestrator's own (host) workspace, so closing it would kill the orchestrator.
bf_close_builder() {
  if bf_is_herdr; then
    if [ -n "${BF_BUILDER_TAB:-}" ]; then herdr tab close "$BF_BUILDER_TAB" >/dev/null 2>&1 || true
    elif [ -n "${BF_BUILDER_WS:-}" ] && [ "${BF_BUILDER_WS}" != "${BF_ORCH_WS:-}" ]; then
      herdr workspace close "$BF_BUILDER_WS" >/dev/null 2>&1 || true
    elif [ -n "${BF_BUILDER_SURFACE:-}" ]; then herdr pane close "$BF_BUILDER_SURFACE" >/dev/null 2>&1 || true
    fi
    return 0
  fi
  if [ -n "${BF_BUILDER_SURFACE:-}" ]; then
    cmux close-surface --workspace "$BF_BUILDER_WS" --surface "$BF_BUILDER_SURFACE" >/dev/null || true
  else
    cmux close-workspace --workspace "$BF_BUILDER_WS" >/dev/null || true
  fi
}

# --- sidebar groups ("folders") -------------------------------------------------------
# Every builder of a repo lives in one collapsible sidebar group named "🔨 <repo> builders".
bf_group_name() { echo "🔨 $(basename "$(bf_primary_root)") builders"; }

# Print the workspace_group:N ref for a group name, or nothing.
bf_find_group() { # name
  cmux workspace-group list --json 2>/dev/null | jq -r --arg n "$1" '.groups[] | select(.name==$n) | .ref' | head -1
}

# Member count of a group ref (0 if the group is gone).
bf_group_members() { # group-ref
  cmux workspace-group list --json 2>/dev/null | jq -r --arg r "$1" '.groups[] | select(.ref==$r) | .member_count' | head -1
}

# Put a builder into the repo's builders group, creating the group on first use FROM the
# orchestrator's workspace. cmux gives every group its own empty anchor terminal, which is the
# folder header; the orchestrator is then the first child under it and each builder is appended
# after, so the session the human talks to is always the top item inside the folder.
# Prints the group ref.
bf_group_join() { # builder-ws orchestrator-ws
  local b=$1 o=$2 name g members
  name=$(bf_group_name); g=$(bf_find_group "$name")
  if [ -z "$g" ]; then
    cmux workspace-group create --name "$name" --from "$o" >/dev/null || return 1
    g=$(bf_find_group "$name"); [ -n "$g" ] || return 1
    cmux workspace-group pin "$g" >/dev/null 2>&1 || true
    cmux workspace-group set-icon "$g" --symbol hammer >/dev/null 2>&1 || true
    cmux workspace-group set-color "$g" --hex "#8fbcbb" >/dev/null 2>&1 || true
  else
    members=$(cmux workspace-group list --json | jq -r --arg r "$g" '.groups[] | select(.ref==$r) | .member_workspace_refs[]')
    echo "$members" | grep -qx "$o" || cmux workspace-group add --group "$g" --workspace "$o" >/dev/null || true
  fi
  cmux workspace-group add --group "$g" --workspace "$b" >/dev/null || return 1
  echo "$g"
}

# Tidy the builders group after a builder leaves. While the orchestrator is still a member the
# folder stays (it is the orchestrator's home); if only the empty header anchor is left, the
# group and that terminal go.
bf_group_drop_if_empty() { # group-ref orchestrator-ws
  [ -n "$1" ] || return 0
  local members n
  members=$(cmux workspace-group list --json 2>/dev/null | jq -r --arg r "$1" '.groups[] | select(.ref==$r) | .member_workspace_refs[]')
  [ -n "$members" ] || return 0
  if [ -n "${2:-}" ] && echo "$members" | grep -qx "$2"; then echo "group $1 kept: orchestrator $2 is in it"; return 0; fi
  n=$(echo "$members" | wc -l | tr -d ' ')
  [ "$n" -le 1 ] && cmux workspace-group delete "$1" --close-workspaces >/dev/null 2>&1 && echo "dropped empty group $1"
  return 0
}
