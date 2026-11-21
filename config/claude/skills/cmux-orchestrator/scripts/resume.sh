#!/usr/bin/env bash
# resume.sh <slug> [<session-id>]
#
# Bring a builder back after a restart or a mistaken collect, inside its OWN Claude conversation.
# Works when the builder's transcript still exists under ~/.claude/projects/<worktree-path-dashed>/
# (and, if the worktree is gone, when the branch is on origin). Run from the repo's primary
# checkout, inside the orchestrator's mux (herdr / Orca), like spawn.sh. Also the fix for a
# watchdog DRIFT line: a builder restored by herdr with the wrong model, mode or route.
#
#   1. worktree at the SAME path as before (the transcript's project dir is keyed by it),
#      recreated from the origin branch only when missing; node_modules symlinked as spawn.sh does
#   2. ledger: the live <slug>.env if present, else archive/<slug>/ledger.env (+ builder.log),
#      re-pointed at THIS orchestrator (BF_ORCH_PEER from ListAgents via $ORCH_PEER, workspace,
#      surface); spec and deferred-work restored from the archive when missing
#   3. `claude --resume <session-id>` with the ledger's --model and mode, the BF_* env and this
#      pane's gateway route: a new tab under Orca; under herdr the builder's own pane, after
#      asking any claude still running there to exit. The new process is then checked with
#      bf_launch_drift and the script fails if it still drifts.
#
# <session-id> defaults to the newest transcript in the worktree's project dir.
# Then SendMessage the builder: what happened, its head sha, its next step.
set -euo pipefail
SLUG=${1:?usage: resume.sh <slug> [<session-id>]}; SID=${2:-}
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd -P)
CM=$ROOT/_bmad/handoff/cmux; ARCH=$CM/archive/$SLUG
SRC_LEDGER=$CM/$SLUG.env; [ -f "$SRC_LEDGER" ] || SRC_LEDGER=$ARCH/ledger.env
[ -f "$SRC_LEDGER" ] || bf_die "no ledger for $SLUG (neither $CM/$SLUG.env nor $ARCH/ledger.env)"
get() { sed -n "s/^$1=//p" "$SRC_LEDGER" | head -1 | sed "s/^'//; s/'$//"; }
BRANCH=$(get BF_BRANCH); WT=$(get BF_WORKTREE); SPEC=$(get BF_SPEC); ISSUE=$(get BF_ISSUE)
MCP=$(get BF_MCP); MODEL=$(get BF_MODEL); MODE=$(get BF_MODE); BMAD_ROOT=$(get BF_BMAD_ROOT)
ADD_DIRS=$(get BF_ADD_DIRS)
: "${MODEL:=opus[1m]}" "${MODE:=yolo}"
PEER=${ORCH_PEER:?set ORCH_PEER to the ListAgents name of this session}

# 1. worktree at the same path
if [ ! -d "$WT" ]; then
  git -C "$ROOT" fetch -q origin "$BRANCH" || bf_die "branch $BRANCH is not on origin"
  git -C "$ROOT" worktree add -q -B "$BRANCH" "$WT" "origin/$BRANCH"
  git -C "$WT" branch -q --set-upstream-to "origin/$BRANCH"
fi
[ -d "$ROOT/node_modules" ] && [ ! -e "$WT/node_modules" ] && ln -s "$ROOT/node_modules" "$WT/node_modules"
[ -d "$ROOT/admin-app/node_modules" ] && [ ! -e "$WT/admin-app/node_modules" ] && ln -s "$ROOT/admin-app/node_modules" "$WT/admin-app/node_modules"
mkdir -p "$(dirname "$SPEC")"
[ -f "$SPEC" ] || { [ -f "$ARCH/$(basename "$SPEC")" ] && cp "$ARCH/$(basename "$SPEC")" "$SPEC"; } || true
DW="$(dirname "$SPEC")/deferred-work.local.md"
[ -f "$DW" ] || { [ -f "$ARCH/deferred-work.local.md" ] && cp "$ARCH/deferred-work.local.md" "$DW"; } || true

# transcript (Claude Code maps / . _ to - in project dir names)
PD="$HOME/.claude/projects/$(printf '%s' "$WT" | sed 's#[/._]#-#g')"
MEM="$HOME/.claude/projects/$(printf '%s' "$ROOT" | sed 's#[/._]#-#g')/memory"
mkdir -p "$PD"; [ -d "$MEM" ] && [ ! -e "$PD/memory" ] && ln -s "$MEM" "$PD/memory" || true
[ -n "$SID" ] || SID=$(ls -t "$PD"/*.jsonl 2>/dev/null | head -1 | xargs -n1 basename 2>/dev/null | sed 's/\.jsonl$//' || true)
[ -n "$SID" ] && [ -f "$PD/$SID.jsonl" ] || bf_die "no transcript in $PD (pass the session id)"

# 2. ledger back in place, pointed at this orchestrator
ORCH_WS=$(bf_my_workspace) || bf_die "cannot identify the orchestrator workspace"
ORCH_SURFACE=$(bf_my_surface 2>/dev/null || echo "")
LEDGER=$CM/$SLUG.env
[ "$SRC_LEDGER" = "$LEDGER" ] || cp "$SRC_LEDGER" "$LEDGER"
[ -f "$CM/$SLUG.log" ] || { [ -f "$ARCH/builder.log" ] && cp "$ARCH/builder.log" "$CM/$SLUG.log"; } || true
bf_set "$SLUG" BF_STATUS resumed
bf_set "$SLUG" BF_ORCH_PEER "$PEER"
bf_set "$SLUG" BF_ORCH_WS "$ORCH_WS"
bf_set "$SLUG" BF_ORCH_SURFACE "$ORCH_SURFACE"

# 3. builder tab resuming its own conversation
SETTINGS="$HOME/.claude/skills/cmux-builder/builder-settings.json"
# An MCP-free builder also runs without the context-mode plugin: its PreToolUse hook redirects
# gradle/maven/curl to ctx_execute whenever ANY session on the machine has the MCP server up, and a
# --strict-mcp-config builder has no such tool, so the build is refused (Jeff 2026-11-13: allow
# build tools for builders). The variant is regenerated from the base file on every launch.
if [ "${MCP:-none}" = none ]; then
  NOMCP_SETTINGS="${SETTINGS%.json}.nomcp.json"
  jq '.enabledPlugins["context-mode@context-mode"]=false' "$SETTINGS" > "$NOMCP_SETTINGS.$$" \
    && mv "$NOMCP_SETTINGS.$$" "$NOMCP_SETTINGS" && SETTINGS="$NOMCP_SETTINGS" \
    || { rm -f "$NOMCP_SETTINGS.$$"; echo "WARNING: could not write $NOMCP_SETTINGS; builder keeps the context-mode hook and cannot run gradle" >&2; }
fi
FLAGS="--model '$MODEL'"
if [ "$MODE" = yolo ]; then FLAGS+=" --dangerously-skip-permissions"; else FLAGS+=" --permission-mode $MODE"; fi
FLAGS+=" --settings $SETTINGS"
[ "${MCP:-none}" = none ] && FLAGS+=" --strict-mcp-config"
for d in $ADD_DIRS; do FLAGS+=" --add-dir '$d'"; done
AGENTS_PY="$HOME/.claude/skills/ux-video-review/scripts/agents_json.py"
[ -f "$AGENTS_PY" ] && FLAGS+=" --agents \"\$(python3 '$AGENTS_PY')\""
CLAUDE_CMD="claude --resume $SID $FLAGS"

# Gateway routing, as spawn.sh does it: this pane's exports, else `cg env`. A resumed builder
# must not take its route from the shell it lands in -- after a restart that shell is a fresh
# login shell, and cg.sh's sticky pins it to Kimi (2026-11-20). So the env file unsets every
# model and route variable first, then exports this pane's, and points CG_STICKY_FILE at a file
# that never exists so the builder's own shells do not re-apply the sticky either.
GW_VARS=(ANTHROPIC_BASE_URL ANTHROPIC_API_KEY ANTHROPIC_CUSTOM_HEADERS ANTHROPIC_MODEL
         ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL
         ANTHROPIC_DEFAULT_FABLE_MODEL CLAUDE_CODE_SUBAGENT_MODEL CG_ACTIVE CG_KEY_FILE CG_URL)
GW_SRC=""
if [ -n "${ANTHROPIC_BASE_URL:-}" ]; then GW_SRC="this pane's exports"
elif GW_CG=$(command -v tpcg || command -v cg) && GW_OUT=$($GW_CG env); then eval "$GW_OUT"; GW_SRC="$GW_CG env"
  CG_URL=${CG_URL:-$ANTHROPIC_BASE_URL}
fi
if [ -n "$GW_SRC" ] && bf_is_claude_model "$MODEL"; then
  GW_BAD=$(printf '%s\n' "ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL:-}" "ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-}" \
    "ANTHROPIC_DEFAULT_OPUS_MODEL=${ANTHROPIC_DEFAULT_OPUS_MODEL:-}" "CLAUDE_CODE_SUBAGENT_MODEL=${CLAUDE_CODE_SUBAGENT_MODEL:-}" \
    | bf_launch_drift "" "" | paste -sd ';' -)
  [ -z "$GW_BAD" ] || bf_die "refusing to resume $SLUG on $MODEL: the route from $GW_SRC is not Claude ($GW_BAD). Run this from a pane on the Claude pool."
fi
ENVF=$(mktemp "${TMPDIR:-/tmp}/bf-env-$SLUG.XXXXXX"); chmod 600 "$ENVF"
{
  printf 'unset %s\n' "${GW_VARS[*]}" ANTHROPIC_SMALL_FAST_MODEL
  printf '%s\n' 'for v in $(env | sed -n "s/^\(CG_KIMI_[A-Z0-9_]*\)=.*/\1/p"); do unset "$v"; done'
  for v in "${GW_VARS[@]}"; do [ -n "${!v:-}" ] && printf 'export %s=%q\n' "$v" "${!v}"; done
  [ -n "$GW_SRC" ] && printf 'export CG_STICKY_FILE=%q\n' "$HOME/.config/claude-gateway/.sticky-off-for-builders"
  for kv in "BF_SLUG=$SLUG" "BF_LEDGER=$LEDGER" "BF_ORCH_WS=$ORCH_WS" "BF_ORCH_SURFACE=$ORCH_SURFACE" \
            "BF_WORKTREE=$WT" "BF_SPEC=$SPEC" "BF_BRANCH=$BRANCH" "BF_ISSUE=$ISSUE" "BF_BMAD_ROOT=$BMAD_ROOT"; do
    printf 'export %s=%q\n' "${kv%%=*}" "${kv#*=}"
  done
  OWNER=$(git -C "$ROOT" remote get-url origin | sed -nE 's#.*github\.com[:/]([^/]+)/.*#\1#p')
  T=$( [ -n "$OWNER" ] && gh auth token --user "$OWNER" 2>/dev/null || true ); [ -n "$T" ] && printf 'export GH_TOKEN=%q\n' "$T"
} > "$ENVF"
CMD="cd '$WT' && . '$ENVF' && rm -f '$ENVF' && $CLAUDE_CMD"
if bf_caller_is_orca; then
  echo "export BF_MUX=orca" >> "$ENVF"
  OUT=$(bf_orca terminal create --worktree "id:$ORCH_WS" --title "🔨 $SLUG" --command "$CMD" --json)
  read -r SURF PANE < <(printf '%s' "$OUT" | python3 -c 'import json,sys; t=json.load(sys.stdin)["result"]["terminal"]; print(t["handle"], t.get("paneKey",""))')
  bf_set "$SLUG" BF_BUILDER_TAB "$PANE"
elif [ "$(get BF_MUX)" = herdr ]; then
  # herdr: back into the builder's OWN pane, which a restore has already recreated. A claude still
  # running there (the drifted one) is asked to exit first; Claude's "Exit and stop tasks" menu, if
  # it shows, takes Enter.
  BF_MUX=herdr; BF_HERDR_SOCKET=$(get BF_HERDR_SOCKET); export BF_MUX BF_HERDR_SOCKET; bf_herdr_env
  printf 'export BF_MUX=herdr\nexport BF_HERDR_SOCKET=%q\n' "$BF_HERDR_SOCKET" >> "$ENVF"
  SURF=$(get BF_BUILDER_SURFACE); BUILDER_WS=$(get BF_BUILDER_WS)
  [ -n "$SURF" ] && [ -n "$(bf_read "$SURF" 5)" ] || bf_die "herdr pane '$SURF' for $SLUG is not readable; open a tab in $WT and set BF_BUILDER_SURFACE"
  if OLD=$(bf_builder_pid "$WT"); then
    bf_send_line "$SURF" "/exit" || true
    for _ in $(seq 1 30); do
      kill -0 "$OLD" 2>/dev/null || break
      bf_read "$SURF" 12 | grep -q 'Exit and stop tasks' && bf_send_key "$SURF" enter
      sleep 1
    done
    ! kill -0 "$OLD" 2>/dev/null || bf_die "claude pid $OLD in $WT did not exit; stop it in $SURF and run resume.sh again"
  fi
  bf_send_line "$SURF" "$CMD" || bf_die "could not type the resume command into $SURF"
  NEW=""
  for _ in $(seq 1 30); do NEW=$(bf_builder_pid "$WT") && break; sleep 1; done
  [ -n "$NEW" ] || bf_die "no claude came up in $WT within 30s; read $SURF"
  TOKENS=$(bf_proc_tokens "$NEW" || true)
  [ -n "$TOKENS" ] || bf_die "claude pid $NEW in $WT exited right after the resume; read $SURF"
  DRIFT=$(printf '%s\n' "$TOKENS" | bf_launch_drift "$MODEL" "$MODE" | paste -sd ';' -)
  [ -z "$DRIFT" ] || bf_die "resumed $SLUG (pid $NEW) still drifts: $DRIFT"
  echo "==> $SLUG pid $NEW verified: --model $MODEL, mode $MODE, route ${ANTHROPIC_BASE_URL:-own login}"
else
  bf_die "resume.sh drives Orca and herdr; under cmux launch by hand as spawn.sh does with: $CLAUDE_CMD"
fi
bf_set "$SLUG" BF_BUILDER_WS "${BUILDER_WS:-$ORCH_WS}"
bf_set "$SLUG" BF_BUILDER_SURFACE "$SURF"
( sleep 60; rm -f "$ENVF" ) >/dev/null 2>&1 &
echo "resumed $SLUG ($SID) in $SURF — now SendMessage it what happened and its next step"
