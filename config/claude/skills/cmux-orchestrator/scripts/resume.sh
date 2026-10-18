#!/usr/bin/env bash
# resume.sh <slug> [<session-id>]
#
# Bring a builder back after a restart or a mistaken collect, inside its OWN Claude conversation.
# Works when the branch is on origin and the builder's transcript still exists under
# ~/.claude/projects/<worktree-path-dashed>/. Run from the repo's primary checkout, inside the
# orchestrator's mux (cmux / herdr / Orca), like spawn.sh.
#
#   1. worktree at the SAME path as before (the transcript's project dir is keyed by it),
#      on the branch from origin; node_modules symlinked as spawn.sh does
#   2. ledger: the live <slug>.env if present, else archive/<slug>/ledger.env (+ builder.log),
#      re-pointed at THIS orchestrator (BF_ORCH_PEER from ListAgents via $ORCH_PEER, workspace,
#      surface); spec and deferred-work restored from the archive when missing
#   3. a new builder tab running `claude --resume <session-id>` with the BF_* env (Orca/cmux)
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
: "${MODEL:=opus[1m]}" "${MODE:=auto}"
PEER=${ORCH_PEER:?set ORCH_PEER to the ListAgents name of this session}

# 1. worktree at the same path
git -C "$ROOT" fetch -q origin "$BRANCH" || bf_die "branch $BRANCH is not on origin"
if [ ! -d "$WT" ]; then
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
FLAGS="--model '$MODEL'"
if [ "$MODE" = yolo ]; then FLAGS+=" --dangerously-skip-permissions"; else FLAGS+=" --permission-mode $MODE"; fi
FLAGS+=" --settings $SETTINGS"
[ "${MCP:-none}" = none ] && FLAGS+=" --strict-mcp-config"
for d in $ADD_DIRS; do FLAGS+=" --add-dir '$d'"; done
CLAUDE_CMD="claude --resume $SID $FLAGS"
ENVF=$(mktemp "${TMPDIR:-/tmp}/bf-env-$SLUG.XXXXXX"); chmod 600 "$ENVF"
{
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
else
  bf_die "resume.sh drives Orca only for now; under cmux/herdr launch by hand as spawn.sh does with: $CLAUDE_CMD"
fi
bf_set "$SLUG" BF_BUILDER_WS "$ORCH_WS"
bf_set "$SLUG" BF_BUILDER_SURFACE "$SURF"
( sleep 60; rm -f "$ENVF" ) >/dev/null 2>&1 &
echo "resumed $SLUG ($SID) in $SURF — now SendMessage it what happened and its next step"
