#!/usr/bin/env bash
# Launch a JEFF BOX babysit session for one org with a scoped MCP set.
#
# Why the flags: a babysit session's cost is dominated by re-reading its own
# context on every turn, and chat traffic makes turns frequent. Measured in the
# PD checkout on 2026-09-06 with `claude -p 'Reply with exactly: ok'`:
#
#   all MCP servers loaded ......... 172,862 tok floor
#   babaflow only (these flags) .... 144,605 tok floor   <- 28,257 saved/turn
#   no MCP servers at all ...........  66,840 tok floor
#
# So pal + chrome-devtools + context-mode cost 28k a turn, and babaflow's 101
# tools cost 77,765. A babysitter uses ~12 babaflow tools and none of the
# others. Dropping the others is free; trimming babaflow needs a server-side
# tool profile (see #TODO issue) and is worth another ~66k a turn.
#
# Usage:
#   babysit.sh PD                 # launch in this terminal / cmux pane
#   babysit.sh PD --model sonnet  # cheaper model for pure chat-sitting
#   babysit.sh --print            # show the command for every org
#   babysit.sh --check            # branch state of every org checkout, launch nothing
#   babysit.sh --check PD MT      # ...or just these; exit 1 if any would refuse
#
# Every launch runs preflight() first: it REFUSES a checkout that is on `main`
# or whose git admin dir is gone, and warns on a detached or badly stale one.
#
# Defaults to `--permission-mode auto` and `--model opus[1m]`. Without an
# explicit --model these sessions silently launched on claude-fable-5-1.
#
# The 1M variant is NOT a luxury here, it is forced: the floor is ~163k (skill +
# sidecar + babaflow's 101 tool schemas) and boot reads push a session to ~195k
# before it has answered anything -- measured 2026-09-06, EX reached 199,969
# tokens in 17 calls. A 200k window would leave no working headroom at all.
# Plain `opus` only becomes viable once #3374 trims the MCP tool set; revisit
# this default then, because above 200k the 1M variant is priced at a premium.
set -euo pipefail

SKILL_DIR="$HOME/.claude/skills/babysit-chat"
MCP_CONFIG="$HOME/.claude/babysit/mcp.json"
REPO_ROOT="$HOME/repos/01_business/tp"
ORGS=(TP PD EX MT OH)
MODEL="opus[1m]"

resolve_dir() {   # checkout names vary in case (Babaflow-TP vs BabaFlow-MT)
  local org="$1" d
  for d in "$REPO_ROOT"/[Bb]aba[Ff]low-"$org"; do
    [ -d "$d" ] && { printf '%s\n' "$d"; return 0; }
  done
  return 1
}

# Refuse to launch into a checkout that cannot do the work, and never let an org
# worktree squat `main`. See BabaFlow CLAUDE.md Rule 20b. Both failures are real:
#
#   2026-09-08  BabaFlow-PD was parked on `main`. Git allows one worktree per
#               branch, so the PRIMARY checkout could not check out main and was
#               left detached 25 commits behind -- every tool that renders a
#               branch name rendered nothing and the repo read as having no git.
#   BabaFlow-MT  its worktree admin dir was deleted. `git` fails in it entirely,
#               it is absent from `git worktree list`, and `git worktree repair`
#               cannot fix it. Tracked tree frozen at v4.54.2 (checked out
#               2026-08-20) while sessions kept launching there and writing
#               untracked state through 2026-09-07 -- so a session lands on a
#               three-week-old tree and is told nothing.
#
# Returns 1 to block the launch; prints warnings and returns 0 otherwise.
preflight() {
  local org="$1" dir="$2" branch behind
  if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    cat >&2 <<EOF
ERROR: $dir is not a working git checkout.

  Its .git pointer references a worktree admin dir that no longer exists, so
  git cannot read it and 'git worktree repair' will not help. The files are
  frozen at whatever commit it held when the admin dir was deleted.

  Recreating it DELETES the directory, and its uncommitted state is unreadable
  by git -- so nobody can see what would be lost. Confirm with Jeff first:

    git -C $REPO_ROOT/BabaFlow worktree add $dir -b local/$(echo "$org" | tr '[:upper:]' '[:lower:]') origin/main
EOF
    return 1
  fi

  branch="$(git -C "$dir" branch --show-current 2>/dev/null || true)"

  if [ "$branch" = "main" ]; then
    cat >&2 <<EOF
REFUSING: $dir is on 'main'.

  Git allows one worktree per branch, so this locks the PRIMARY checkout out of
  its own default branch -- it ends up detached and silently drifting behind.
  Org worktrees park on local/$(echo "$org" | tr '[:upper:]' '[:lower:]') (CLAUDE.md Rule 20b). Fix:

    git -C $dir switch local/$(echo "$org" | tr '[:upper:]' '[:lower:]') 2>/dev/null || \\
      git -C $dir switch -c local/$(echo "$org" | tr '[:upper:]' '[:lower:]')
EOF
    return 1
  fi

  if [ -z "$branch" ]; then
    echo "WARNING: $dir is on a detached HEAD. It should park on local/$(echo "$org" | tr '[:upper:]' '[:lower:]') (Rule 20b)," >&2
    echo "         or the next session to 'fix' it may put it on main." >&2
  fi

  # Staleness is measured against the last fetch, not the remote -- cheap, and a
  # big number is directionally right even if the fetch is old.
  behind="$(git -C "$dir" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
  if [ "${behind:-0}" -gt 50 ]; then
    echo "WARNING: $dir is $behind commits behind origin/main (as of its last fetch)." >&2
    echo "         Refresh before trusting anything you read here:" >&2
    echo "           git -C $dir fetch origin && git -C $dir rebase origin/main" >&2
  fi

  return 0
}

cmd_for() {
  local org="$1" dir; dir="$(resolve_dir "$org")" || { echo "no checkout for $org" >&2; return 1; }
  printf 'cd %q && claude --mcp-config %q --strict-mcp-config --permission-mode auto%s %q\n' \
    "$dir" "$MCP_CONFIG" "${MODEL:+ --model $MODEL}" "$(prompt_for "$org")"
}

prompt_for() {
  cat <<EOF
Use the babysit-chat skill to sit in the $1 partner Telegram channel as JEFF BOX.

Read $SKILL_DIR/state/$1.md first, then arm the watches per the skill.

This session is cost-constrained: its context is re-read on every turn and chat
traffic makes turns frequent. Follow the skill's "Keep the window small" section
without being reminded -- investigations go to subagents, raw output goes through
a script, and you ask me to /clear after each closed loop.

DO NOT IMPLEMENT SHIPPABLE WORK IN THIS CONTEXT. You are the org's chat presence,
not its developer. Answer the partner, fix what is fixable now through the
platform, and for anything that needs a code change spawn a cmux builder with
/cmux-orchestrator -- write the spec, spawn it, supervise it, let it own the PR
and the review loop (CLAUDE.md Rule 21). A builder gets its own git worktree and its
own context window; implementing here instead spends the one window that has to stay
live for the chat, and this session is the most expensive place in the fleet to
burn context.

Builders you spawn run as TABS in THIS workspace, so they die when this workspace
closes -- and relaunch-org-chats.sh closes it. spawn.sh records each one in your
sidecar automatically; YOU must keep that row current, or a fresh session inherits a
builder it cannot account for:

  ~/.claude/skills/babysit-chat/scripts/builder-log.sh $1 <slug> "<status>" [--pr N] [--note ...]
  ~/.claude/skills/babysit-chat/scripts/builder-log.sh $1 --list

Update it when the PR opens, when it converges, and when it merges. It upserts by slug,
so calling it repeatedly is correct and never duplicates a row.

Your worktree is parked on local/$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]'). Never check out main here -- git allows one
worktree per branch, so doing that locks the primary checkout out of its own
default branch (CLAUDE.md Rule 20b). Builders branch off origin/main themselves.
EOF
}

[ $# -ge 1 ] || { echo "usage: babysit.sh <ORG|--print> [--model NAME]" >&2; exit 2; }
[ -f "$MCP_CONFIG" ] || { echo "missing $MCP_CONFIG" >&2; exit 1; }

TARGET="$1"; shift

if [ "$TARGET" = "--check" ]; then
  rc=0
  CHECK=("$@"); [ ${#CHECK[@]} -gt 0 ] || CHECK=("${ORGS[@]}")
  for o in "${CHECK[@]}"; do
    o="$(printf '%s' "$o" | tr '[:lower:]' '[:upper:]')"
    d="$(resolve_dir "$o")" || { echo "$o  -- NO CHECKOUT under $REPO_ROOT"; rc=1; continue; }
    b="$(git -C "$d" branch --show-current 2>/dev/null || true)"
    git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || b="BROKEN (admin dir deleted)"
    printf '%-4s %-24s %s\n' "$o" "$(basename "$d")" "${b:-DETACHED}"
    preflight "$o" "$d" >/dev/null 2>&1 || rc=1
  done
  echo
  [ "$rc" = 0 ] && echo "All org checkouts launchable." \
                || echo "At least one org would REFUSE to launch. Re-run: babysit.sh <ORG>  for the reason."
  exit "$rc"
fi

# Expose the resolver so other scripts never hardcode checkout paths (the names vary in
# case: Babaflow-TP vs BabaFlow-MT). relaunch-org-chats.sh uses this to sync a checkout.
if [ "$TARGET" = "--dir" ]; then
  o="$(printf '%s' "${1:?--dir needs an ORG}" | tr '[:lower:]' '[:upper:]')"
  resolve_dir "$o" || { echo "no checkout for org '$o' under $REPO_ROOT" >&2; exit 1; }
  exit 0
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --model) MODEL="${2:?--model needs a value}"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ "$TARGET" = "--print" ]; then
  for o in "${ORGS[@]}"; do echo "### $o"; cmd_for "$o"; echo; done
  exit 0
fi

ORG="$(printf '%s' "$TARGET" | tr '[:lower:]' '[:upper:]')"
DIR="$(resolve_dir "$ORG")" || { echo "no checkout for org '$ORG' under $REPO_ROOT" >&2; exit 1; }

preflight "$ORG" "$DIR" || exit 1

cd "$DIR"
exec claude --mcp-config "$MCP_CONFIG" --strict-mcp-config \
     --permission-mode auto ${MODEL:+--model "$MODEL"} \
     "$(prompt_for "$ORG")"
