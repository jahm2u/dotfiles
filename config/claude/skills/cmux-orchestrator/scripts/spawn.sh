#!/usr/bin/env bash
# spawn.sh — create a worktree + cmux workspace + Claude builder for one spec.
#
# Usage:
#   spawn.sh --slug <kebab-slug> --spec <path-to-drafted-spec.md> [--issue <N>] \
#            [--base origin/main] [--model opus[1m]] [--mode auto|acceptEdits|yolo] [--focus] [--spec-dir _bmad-output/implementation-artifacts] [--mcp none|full] [--place tab|workspace] [--group repo|mine|none]
#
# What it does (idempotent per slug: refuses if a ledger already exists):
#   1. git worktree add .claude/worktrees/wt-<slug> -b <branch> --no-track <base>   (Rule 20)
#   2. symlink node_modules + admin-app/node_modules from the primary checkout
#   3. copy the spec into the worktree's _bmad-output/implementation-artifacts/spec-<slug>.md
#   4. write the ledger  _bmad/handoff/cmux/<slug>.env
#   5. cmux new-workspace (env BF_* set) running `claude --model <m> --permission-mode <mode> /cmux-builder`
#   6. add the workspace to the "🔨 <repo> builders" sidebar group (created on first use)
#   7. put a status pill on the ORCHESTRATOR's workspace so the human sees it in the sidebar
# Prints: the builder workspace ref on the last line.
#
# herdr: run from a herdr pane (HERDR_ENV=1) and steps 5-7 happen in herdr instead -- the
# builder is a new herdr TAB in the caller's workspace (`herdr tab create`, BF_* via --env),
# Claude is started there with `herdr agent start` under an agent name (b-<slug>), and the
# ledger records BF_MUX=herdr plus the server socket, tab, pane and agent name. Steps 1-4
# are identical. --group does not apply (herdr has no sidebar folders).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"

SLUG="" SPEC="" ISSUE="" BASE="origin/main" MODEL="opus[1m]" MODE="auto" FOCUS="false" MCP="none" GROUP="repo" PLACE="tab" SPEC_DIR="_bmad-output/implementation-artifacts"
while [ $# -gt 0 ]; do
  case "$1" in
    --slug) SLUG=$2; shift 2;;
    --spec) SPEC=$2; shift 2;;
    --issue) ISSUE=$2; shift 2;;
    --base) BASE=$2; shift 2;;
    --model) MODEL=$2; shift 2;;
    --mode) MODE=$2; shift 2;;
    --focus) FOCUS="true"; shift;;
    --spec-dir) SPEC_DIR=$2; shift 2;;
    --mcp) MCP=$2; shift 2;;   # none (default) | full
    --place) PLACE=$2; shift 2;; # tab (default: a tab in THIS workspace) | workspace (its own sidebar row)
    --group) GROUP=$2; shift 2;; # repo (default: "🔨 <repo> builders" folder, orchestrator as its header) | mine (the orchestrator's own group) | none
    *) bf_die "unknown arg $1";;
  esac
done
[ -n "$SLUG" ] || bf_die "--slug required"
[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]] || bf_die "slug must be kebab-case: $SLUG"
if [ ! -f "$SPEC" ]; then
  # a relative --spec is tried against the cwd first, then the primary checkout (orchestrators
  # often run from a worktree or another directory than the one they drafted the spec in)
  alt="$(bf_primary_root)/$SPEC"; [ -f "$alt" ] && SPEC=$alt
fi
[ -f "$SPEC" ] || bf_die "--spec file not found: $SPEC (tried the cwd and the primary checkout; pass an absolute path)"
grep -q '^status:' "$SPEC" || bf_die "spec has no 'status:' frontmatter (use the quick-dev spec template)"

ORCH_CWD="$PWD"      # the orchestrator's own checkout; org chats run in Baba{F,f}low-<ORG>
ROOT=$(bf_primary_root)
LEDGER=$(bf_ledger_file "$SLUG")
[ ! -f "$LEDGER" ] || bf_die "ledger already exists for '$SLUG' ($LEDGER). Run the trash collector first, or pick another slug."

if bf_caller_is_herdr; then MUX=herdr; else MUX=cmux; fi
export BF_MUX=$MUX
ORCH_WS=$(bf_my_workspace) || bf_die "cannot identify the orchestrator's cmux workspace (not inside cmux or herdr?)"
[ -n "$ORCH_WS" ] || bf_die "cannot identify the orchestrator's workspace"
HERDR_SOCK=""; [ "$MUX" = herdr ] && HERDR_SOCK="${HERDR_SOCKET_PATH:-}"
# Surface too: builders are tabs in this same workspace, so the workspace ref alone
# cannot tell report.sh which prompt is the orchestrator's. Non-fatal if unavailable --
# report.sh falls back to the workspace-only form.
ORCH_SURFACE=$(bf_my_surface 2>/dev/null || echo "")
WT="$ROOT/.claude/worktrees/wt-$SLUG"
[ ! -e "$WT" ] || bf_die "worktree path already exists: $WT"
# Slugs conventionally lead with the issue number already; never write fix/71-71-foo.
if [ -n "$ISSUE" ]; then
  case "$SLUG" in "$ISSUE"-*|gh-"$ISSUE"-*) BRANCH="fix/${SLUG}";; *) BRANCH="fix/${ISSUE}-${SLUG}";; esac
else BRANCH="feat/${SLUG}"; fi
git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BRANCH" && bf_die "branch already exists: $BRANCH"

echo "==> fetching $BASE"
git -C "$ROOT" fetch -q origin
echo "==> git worktree add $WT -b $BRANCH --no-track $BASE"
# --no-track is REQUIRED. Without it git sets the new branch's upstream to origin/main
# (branch.autoSetupMerge defaults on for a remote-tracking start point), and then every
# `git status` in the worktree reports "Your branch and 'origin/main' have diverged,
# and have N and M different commits each" -- noise with no real remote counterpart --
# and a `git pull` there would try to merge main INTO the feature branch. The builder's
# first push is `git push -u origin <branch>` (see cmux-builder section 2), which is what
# sets the branch's own remote ref as upstream.
git -C "$ROOT" worktree add -q "$WT" -b "$BRANCH" --no-track "$BASE"

echo "==> node_modules symlinks"
[ -d "$ROOT/node_modules" ] && ln -s "$ROOT/node_modules" "$WT/node_modules"
[ -d "$ROOT/admin-app/node_modules" ] && ln -s "$ROOT/admin-app/node_modules" "$WT/admin-app/node_modules"

# Claude Code's file-based memory lives at ~/.claude/projects/<cwd-slug>/memory/, keyed by the
# CWD, with no git awareness and no fallback to the parent repo. A worktree is a different cwd,
# so without this link every builder starts with ZERO curated memories and none of the repo's
# house rules reach it. The link is two-way on purpose: a memory the builder saves is visible
# everywhere immediately. (Two worktrees saving at the same moment can race on the MEMORY.md
# index line; if an index entry goes missing, re-add it -- the memory file itself was written.)
echo "==> memory symlink"
# Every non-alphanumeric character becomes a dash, not just the slashes. pwd -P first: an
# unexpanded ~ or a symlinked path slugifies to a directory that does not exist, and the
# mkdir + ln below would then succeed in the wrong place.
bf_slug_path() { printf '%s' "$1" | sed 's|[^A-Za-z0-9]|-|g'; }
# $ROOT is already physical (bf_primary_root resolves it), so these normally agree. They differ
# only when the repo itself sits under a symlink, and then it is not knowable from here which
# form Claude Code keyed its projects dir on -- so read whichever one actually has the memories,
# and write the worktree link under BOTH forms when they differ.
MAIN_SLUG=$(bf_slug_path "$(cd "$ROOT" && pwd -P)")
MAIN_SLUG_L=$(bf_slug_path "$ROOT")
WT_SLUG=$(bf_slug_path "$(cd "$WT" && pwd -P)")
WT_SLUG_L=$(bf_slug_path "$WT")
MEM_SRC=""
for cand in "$MAIN_SLUG" "$MAIN_SLUG_L"; do
  if [ -d "$HOME/.claude/projects/$cand/memory" ]; then MEM_SRC=$cand; break; fi
done
if [ -n "$MEM_SRC" ]; then
  for dest in "$WT_SLUG" "$WT_SLUG_L"; do
    if [ "$dest" = "$MEM_SRC" ]; then continue; fi
    mkdir -p "$HOME/.claude/projects/$dest"
    # A leftover link whose target is gone reads as ABSENT to -e, and ln then fails "File exists".
    if [ -L "$HOME/.claude/projects/$dest/memory" ] && [ ! -e "$HOME/.claude/projects/$dest/memory" ]; then
      rm "$HOME/.claude/projects/$dest/memory"
    fi
    [ -e "$HOME/.claude/projects/$dest/memory" ] || \
      ln -s "$HOME/.claude/projects/$MEM_SRC/memory" "$HOME/.claude/projects/$dest/memory"
    echo "    $dest/memory -> $MEM_SRC/memory"
    # a trailing `[ ... ] && break` here would leave the loop non-zero under set -e
    if [ "$WT_SLUG" = "$WT_SLUG_L" ]; then break; fi
  done
else
  # A mis-derived slug and a genuinely absent memory directory skip IDENTICALLY. Print what
  # does exist so the difference is visible, and say the builder started without memories
  # rather than letting silence read as success.
  echo "    WARNING: no memory dir at ~/.claude/projects/$MAIN_SLUG/memory" >&2
  echo "    builder starts WITHOUT curated memories. Projects matching this repo:" >&2
  found=0
  for d in "$HOME"/.claude/projects/*"$(basename "$ROOT")"*; do
    [ -d "$d" ] || continue
    echo "      $(basename "$d")" >&2; found=1
  done
  [ $found -eq 1 ] || echo "      (none)" >&2
fi

SPEC_DIR="$WT/$SPEC_DIR"
mkdir -p "$SPEC_DIR"
SPEC_IN_WT="$SPEC_DIR/spec-$SLUG.md"
cp "$SPEC" "$SPEC_IN_WT"
echo "==> spec at $SPEC_IN_WT"

cat > "$LEDGER" <<LEDGER
BF_SLUG=$SLUG
BF_ISSUE=$ISSUE
BF_BRANCH=$BRANCH
BF_WORKTREE=$WT
BF_SPEC=$SPEC_IN_WT
BF_ORCH_WS=$ORCH_WS
BF_ORCH_SURFACE=$ORCH_SURFACE
BF_MODEL=$MODEL
BF_MODE=$MODE
BF_MCP=$MCP
BF_STATUS=spawning
BF_PR=
BF_CREATED=$(bf_now)
BF_BUILDER_WS=
BF_BUILDER_SURFACE=
BF_MUX=$MUX
BF_HERDR_SOCKET=$HERDR_SOCK
BF_BUILDER_TAB=
BF_BUILDER_AGENT=
LEDGER
bf_logline "$SLUG" spawning "worktree=$WT branch=$BRANCH base=$BASE orch=$ORCH_WS"

# The builder skill reads BF_* from its environment; the ledger path lets report.sh find the rest.
# MCP servers are the builder's biggest fixed context cost (this repo's babaflow MCP alone is
# ~78k tokens per turn; a Haiku builder started at 86% context and an Opus one auto-compacted
# before its second report). Default: no MCP servers. --mcp full keeps the project's config.
MCPFLAG=""; [ "$MCP" = "none" ] && MCPFLAG="--strict-mcp-config"
# The builder's own tooling (report.sh, git, gh, node/npm/npx, cmux, read-only shell) is
# pre-approved through a settings file so routine work never stops on a permission prompt in
# ANY mode; force-push, hard reset, ssh and rm -rf stay denied there.
SETTINGS="$HOME/.claude/skills/cmux-builder/builder-settings.json"
case "$MODE" in
  yolo) MODEFLAG="--dangerously-skip-permissions";;   # trusted spec in its isolated worktree: no prompts at all
  *)    MODEFLAG="--permission-mode $MODE";;
esac
CLAUDE_CMD="claude --model '$MODEL' $MODEFLAG --settings $SETTINGS $MCPFLAG -- '/cmux-builder'"

# Gateway routing, PER PANE. A builder routes the way the pane that spawned it routes:
# the MP hives export their own ANTHROPIC_* (their gateway, their key, their model
# names) into each seat's shell, so if this shell carries them they are passed through
# verbatim. Only a shell with no routing of its own falls back to `cg env`, which prints
# this machine's stored key + pool as exports (no settings.json write). Nothing is
# written globally: an `env` block in ~/.claude/settings.json beats a shell export, so
# a global `cg on` on a box that also hosts hive seats would silently redirect them --
# which is why such a box runs `cg off` and relies on this instead. Values never reach
# the ledger or the log; the key must not end up in a file.
GW_VARS=(ANTHROPIC_BASE_URL ANTHROPIC_API_KEY ANTHROPIC_CUSTOM_HEADERS ANTHROPIC_MODEL
         ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL
         ANTHROPIC_DEFAULT_FABLE_MODEL CLAUDE_CODE_SUBAGENT_MODEL CG_ACTIVE CG_KEY_FILE)
GW_SRC=""
if [ -n "${ANTHROPIC_BASE_URL:-}" ]; then GW_SRC="this pane's exports"
elif GW_CG=$(command -v tpcg || command -v cg) && GW_OUT=$($GW_CG env); then eval "$GW_OUT"; GW_SRC="$GW_CG env"; fi   # cg env says on stderr why it refused (tpcg on a Mac where IPMedia's cg owns the name)
GW_ENVS=()
for v in "${GW_VARS[@]}"; do [ -n "${!v:-}" ] && GW_ENVS+=(--env "$v=${!v}"); done
[ -n "$GW_SRC" ] && echo "==> gateway env for the builder from $GW_SRC (${ANTHROPIC_BASE_URL%%/teamclaude*})" \
  || echo "==> no gateway env in this pane and no cg key: the builder uses its own login / global settings"

BUILDER_WS="" BUILDER_SURFACE="" GROUP_REF=""
if [ "$MUX" = herdr ]; then
  # The claude argv as an array: herdr agent start passes it through verbatim, no shell
  # quoting layer to get wrong. '/cmux-builder' is NOT in it -- it is submitted with
  # `agent prompt` once herdr has seen Claude reach its input box.
  CLAUDE_ARGS=(--model "$MODEL")
  if [ "$MODE" = yolo ]; then CLAUDE_ARGS+=(--dangerously-skip-permissions); else CLAUDE_ARGS+=(--permission-mode "$MODE"); fi
  CLAUDE_ARGS+=(--settings "$SETTINGS")
  [ -n "$MCPFLAG" ] && CLAUDE_ARGS+=("$MCPFLAG")
  ENVS=(--env "BF_SLUG=$SLUG" --env "BF_LEDGER=$LEDGER" --env "BF_ORCH_WS=$ORCH_WS" --env "BF_ORCH_SURFACE=$ORCH_SURFACE"
        --env "BF_WORKTREE=$WT" --env "BF_SPEC=$SPEC_IN_WT" --env "BF_BRANCH=$BRANCH" --env "BF_ISSUE=$ISSUE"
        --env "BF_MUX=herdr" --env "BF_HERDR_SOCKET=$HERDR_SOCK" ${GW_ENVS[@]+"${GW_ENVS[@]}"})
  FOCUSFLAG=--no-focus; [ "$FOCUS" = true ] && FOCUSFLAG=--focus
  case "$PLACE" in
    tab)       OUT=$(herdr tab create --workspace "$ORCH_WS" --cwd "$WT" --label "🔨 $SLUG" "${ENVS[@]}" "$FOCUSFLAG") ;;
    workspace) OUT=$(herdr workspace create --cwd "$WT" --label "🔨 $SLUG" "${ENVS[@]}" "$FOCUSFLAG") ;;
    *) bf_die "--place must be tab|workspace";;
  esac
  read -r BUILDER_WS BUILDER_TAB BUILDER_SURFACE < <(printf '%s' "$OUT" | python3 -c '
import json,sys
r=json.load(sys.stdin)["result"]; p=r["root_pane"]
print(p["workspace_id"], p["tab_id"], p["pane_id"])') || bf_die "could not parse herdr ids from: $OUT"
  bf_set "$SLUG" BF_BUILDER_WS "$BUILDER_WS"
  bf_set "$SLUG" BF_BUILDER_TAB "$BUILDER_TAB"
  bf_set "$SLUG" BF_BUILDER_SURFACE "$BUILDER_SURFACE"
  # herdr agent names: [a-z][a-z0-9_-]{0,31}, unique among live agents.
  AGENT=$(printf 'b-%s' "$SLUG" | cut -c1-32 | sed 's/-*$//')
  echo "==> herdr agent start $AGENT in $BUILDER_SURFACE (claude ${CLAUDE_ARGS[*]})"
  sleep 1   # let the new tab's shell reach its prompt
  if ! AOUT=$(herdr agent start "$AGENT" --kind claude --pane "$BUILDER_SURFACE" --timeout 90000 -- "${CLAUDE_ARGS[@]}" 2>&1); then
    case "$AOUT" in
      *agent_not_ready*) ;;   # started, but held at a startup dialog; handled below
      *name*|*exists*|*duplicate*)
        AGENT=$(printf 'b-%s' "$SLUG" | cut -c1-26 | sed 's/-*$//')-$((RANDOM % 9000 + 1000))
        herdr agent start "$AGENT" --kind claude --pane "$BUILDER_SURFACE" --timeout 90000 -- "${CLAUDE_ARGS[@]}" >/dev/null \
          || bf_die "herdr agent start failed twice: $AOUT";;
      *) bf_die "herdr agent start failed: $AOUT";;
    esac
  fi
  bf_set "$SLUG" BF_BUILDER_AGENT "$AGENT"
  # A startup dialog (folder trust, a settings warning) blocks the first prompt. Wait for
  # herdr to see an input-ready agent; if it never does, say exactly what to do.
  ready=0
  for i in $(seq 1 30); do
    st=$(herdr agent get "$AGENT" 2>/dev/null | python3 -c 'import json,sys; r=json.load(sys.stdin)["result"]; a=r.get("agent") or r; print(a.get("agent_status",""))' 2>/dev/null || true)
    case "$st" in idle|done) ready=1; break;; esac
    sleep 2
  done
  if [ $ready = 1 ] && herdr agent prompt "$AGENT" "/cmux-builder" >/dev/null 2>&1; then
    echo "==> /cmux-builder submitted to $AGENT"
  else
    echo "WARNING: $AGENT is not at an input prompt (state: ${st:-?}); /cmux-builder NOT submitted." >&2
    echo "         peek.sh $SLUG, clear the dialog (approve.sh $SLUG), then: herdr agent prompt $AGENT /cmux-builder" >&2
  fi
else
case "$PLACE" in
tab)
  # The builder is a TAB in this orchestrator's own workspace. cmux groups are flat --
  # a group's members are workspaces and a group cannot contain another group (verified:
  # passing a group ref where a workspace is expected returns not_found) -- so a builder
  # given its own workspace can never sit UNDER its orchestrator in the sidebar, only
  # beside it. As a tab it is inside the orchestrator's row, which is the nesting the
  # sidebar itself cannot express.
  #
  # `new-surface` has NO --env flag, unlike new-workspace, so the BF_* the builder skill
  # reads are inlined into the command instead. GW_ENVS deliberately are NOT: inlining
  # them would type the gateway key into the terminal, where it stays in scrollback. A
  # cmux tab builder routes through this machine's global settings (cg on), which is
  # the right answer on a box that hosts no hive seats. They must be quoted: a spec path or branch
  # with a space would otherwise split into stray argv and the builder would boot without
  # its ledger.
  ENVPFX="BF_SLUG='$SLUG' BF_LEDGER='$LEDGER' BF_ORCH_WS='$ORCH_WS' BF_ORCH_SURFACE='$ORCH_SURFACE' BF_WORKTREE='$WT'"
  ENVPFX="$ENVPFX BF_SPEC='$SPEC_IN_WT' BF_BRANCH='$BRANCH' BF_ISSUE='$ISSUE'"
  CMD="$ENVPFX $CLAUDE_CMD"
  echo "==> cmux new-surface in $ORCH_WS ($CLAUDE_CMD)"
  OUT=$(cmux new-surface --type terminal --workspace "$ORCH_WS" \
    --working-directory "$WT" --focus "$FOCUS")
  BUILDER_SURFACE=$(echo "$OUT" | sed -n 's/^OK \(surface:[0-9]*\).*/\1/p' | tail -1)
  [ -n "$BUILDER_SURFACE" ] || bf_die "could not parse surface ref from: $OUT"
  BUILDER_WS=$ORCH_WS   # the HOST workspace, not a workspace of the builder's own
  bf_set "$SLUG" BF_BUILDER_WS "$BUILDER_WS"
  bf_set "$SLUG" BF_BUILDER_SURFACE "$BUILDER_SURFACE"
  cmux tab-action --action rename --tab "$BUILDER_SURFACE" --workspace "$ORCH_WS" \
    --title "🔨 $SLUG" >/dev/null 2>&1 || true
  # Keep the orchestrator's own tab first, so builders accumulate to its right rather
  # than pushing the session you are talking to along the tab strip.
  FIRST=$(cmux list-pane-surfaces --workspace "$ORCH_WS" 2>/dev/null \
    | sed -n 's/^[* ]*\(surface:[0-9]*\) .*/\1/p' | head -1)
  [ -n "$FIRST" ] && [ "$FIRST" != "$BUILDER_SURFACE" ] \
    && cmux tab-action --action pin --tab "$FIRST" --workspace "$ORCH_WS" >/dev/null 2>&1 || true
  # A terminal surface takes text, not a --command: type it, then submit.
  sleep 0.5
  cmux send --workspace "$ORCH_WS" --surface "$BUILDER_SURFACE" -- "$CMD" >/dev/null
  sleep 0.7
  cmux send-key --workspace "$ORCH_WS" --surface "$BUILDER_SURFACE" enter >/dev/null
  ;;
workspace)
  echo "==> cmux new-workspace ($CLAUDE_CMD)"
  OUT=$(cmux new-workspace --name "🔨 $SLUG" --description "builder · $BRANCH" \
    --cwd "$WT" --focus "$FOCUS" \
    --env "BF_SLUG=$SLUG" --env "BF_LEDGER=$LEDGER" --env "BF_ORCH_WS=$ORCH_WS" --env "BF_ORCH_SURFACE=$ORCH_SURFACE" \
    --env "BF_WORKTREE=$WT" --env "BF_SPEC=$SPEC_IN_WT" --env "BF_BRANCH=$BRANCH" --env "BF_ISSUE=$ISSUE" \
    ${GW_ENVS[@]+"${GW_ENVS[@]}"} --command "$CLAUDE_CMD")
  BUILDER_WS=$(echo "$OUT" | sed -n 's/^OK \(workspace:[0-9]*\).*/\1/p' | tail -1)
  [ -n "$BUILDER_WS" ] || bf_die "could not parse workspace ref from: $OUT"
  bf_set "$SLUG" BF_BUILDER_WS "$BUILDER_WS"

  # Sidebar folder: keep every builder of this repo under one collapsible group.
  case "$GROUP" in
    repo) GROUP_REF=$(bf_group_join "$BUILDER_WS" "$ORCH_WS") || echo "WARNING: could not group $BUILDER_WS" >&2;;
    mine) GROUP_REF=$(cmux workspace-group list --json | jq -r --arg w "$ORCH_WS" '.groups[] | select(.member_workspace_refs[]==$w) | .ref' | head -1)
          [ -n "$GROUP_REF" ] && cmux workspace-group add --group "$GROUP_REF" --workspace "$BUILDER_WS" >/dev/null;;
    none) ;;
    *) bf_die "--group must be repo|mine|none";;
  esac
  ;;
*) bf_die "--place must be tab|workspace";;
esac
fi
bf_set "$SLUG" BF_GROUP "$GROUP_REF"
[ -n "$GROUP_REF" ] && echo "==> in sidebar group $GROUP_REF"
# If this orchestrator IS an org chat, record the builder in that org's sidecar. The
# sidecar is the org's only durable memory, and a tab-mode builder dies with the chat
# workspace -- without this, a /clear or a relaunch leaves no trace that it existed.
# Best-effort and never fatal: a non-org orchestrator simply has no org to infer.
ORG_FROM_CWD=$(basename "$ORCH_CWD" 2>/dev/null | sed -n 's/^[Bb]aba[Ff]low-\([A-Za-z][A-Za-z]\)$/\1/p' | tr '[:lower:]' '[:upper:]')
BLOG="$HOME/.claude/skills/babysit-chat/scripts/builder-log.sh"
if [ -n "$ORG_FROM_CWD" ] && [ -x "$BLOG" ] && [ -f "$HOME/.claude/skills/babysit-chat/state/$ORG_FROM_CWD.md" ]; then
  "$BLOG" "$ORG_FROM_CWD" "$SLUG" spawned \
    ${BUILDER_SURFACE:+--tab "$BUILDER_SURFACE"} \
    ${ISSUE:+--note "issue #$ISSUE"} >/dev/null 2>&1 \
    && echo "==> logged to $ORG_FROM_CWD sidecar" || true
fi

bf_set "$SLUG" BF_STATUS "started"
bf_logline "$SLUG" spawned "builder at ${BUILDER_SURFACE:-$BUILDER_WS}"

bf_pill "$SLUG" spawned "#8fbcbb" "$ORCH_WS"
bf_wslog "$ORCH_WS" "" orchestrator "spawned builder $SLUG at ${BUILDER_SURFACE:-$BUILDER_WS} ($BRANCH)"

echo "builder=${BUILDER_SURFACE:-$BUILDER_WS} place=$PLACE worktree=$WT branch=$BRANCH spec=$SPEC_IN_WT ledger=$LEDGER"
echo "${BUILDER_SURFACE:-$BUILDER_WS}"
