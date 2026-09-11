#!/usr/bin/env bash
# Relaunch every Org Chat workspace with the scoped-MCP babysitter.
#
# Each org chat currently runs a plain `claude`, which loads pal +
# chrome-devtools + context-mode on top of babaflow: 172,862 tokens of context
# re-read on EVERY turn. babysit.sh drops the three a babysitter never uses and
# starts at 144,605 (measured 2026-09-06). Over a day of chat traffic that is
# tens of millions of tokens.
#
# For each org this creates a REPLACEMENT workspace inside the same "Org Chats"
# folder, then closes the old one -- closing is what quits the running claude.
#
#   ./relaunch-org-chats.sh            # do it
#   ./relaunch-org-chats.sh --dry-run  # show what it would do
#   ./relaunch-org-chats.sh PD OH      # only these orgs
#   ./relaunch-org-chats.sh --force-main   # ALSO discard local commits/edits to reach main
#
# An org with no chat workspace is CREATED from scratch (nothing to replace); an org that
# already has one is replaced and its old session closed.
#
# An org whose checkout would refuse to launch (on `main`, or git-broken) is
# SKIPPED with its running session left intact -- see babysit.sh preflight().
#
# WARNING: closing a workspace kills that session with no chance to save state.
# The replacement reads the org's sidecar, so anything not written there is
# lost -- have each session checkpoint its sidecar first.
set -euo pipefail

LAUNCH="$HOME/.claude/skills/babysit-chat/scripts/babysit.sh"
STATE_DIR="$HOME/.claude/skills/babysit-chat/state"
DRY=0; ORGS=(); SKIPPED=0; FORCE_MAIN=0

for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --force-main) FORCE_MAIN=1 ;;
    -*) echo "unknown option: $a" >&2; exit 2 ;;
    *) ORGS+=("$(printf '%s' "$a" | tr '[:lower:]' '[:upper:]')") ;;
  esac
done
[ ${#ORGS[@]} -gt 0 ] || ORGS=(TP PD EX MT OH)
[ -x "$LAUNCH" ] || { echo "missing or non-executable $LAUNCH" >&2; exit 1; }

# ONE pinned sidebar folder, "Org Chats", holding every org chat. cmux groups are flat
# -- a group cannot contain another group (verified: passing a group ref where a workspace
# is expected returns not_found) -- so per-org folders would sit BESIDE each other, not
# nested. The nesting that actually works is tabs: builders an org spawns are surfaces
# inside that org's own chat workspace.
#
# Resolved by NAME and created on demand. An earlier version hardcoded the group UUID;
# that id stopped resolving, `new-workspace` silently fell back to the CALLER's group,
# and a run scattered PD and OH into the builders folder. Never hardcode a cmux id.
ORG_FOLDER="Org Chats"

group_ref_for() {
  local g
  g=$(bf_group_by_name "$ORG_FOLDER")
  if [ -z "$g" ]; then
    cmux workspace-group create --name "$ORG_FOLDER" >/dev/null 2>&1 || return 1
    sleep 0.6
    g=$(bf_group_by_name "$ORG_FOLDER") || return 1
    [ -n "$g" ] && cmux workspace-group pin "$g" >/dev/null 2>&1
  fi
  printf '%s\n' "$g"
}

# Number of surfaces (tabs) in a workspace. A chat has exactly one: its own Claude
# session. Anything beyond that is a BUILDER running as a tab.
ws_tab_count() {
  CMUX_QUIET=1 cmux list-pane-surfaces --workspace "$1" 2>/dev/null \
    | grep -c '^[* ]*surface:'
}

bf_group_by_name() {
  CMUX_QUIET=1 cmux workspace-group list --json 2>/dev/null \
    | python3 -c "
import json,sys
want=sys.argv[1]
for g in json.load(sys.stdin).get('groups',[]):
    if g.get('name')==want:
        print(g['ref']); break
" "$1"
}

# Capture the outgoing session's final screen into the org's sidecar BEFORE closing it.
#
# WHY: a babysitter killed mid-loop leaves the operator unanswered with no trace, and the
# replacement cannot tell a deliberate action from a stray one. On 2026-09-09 the TP
# predecessor fired a real purge_campaign_queue on campaign 2691 (130 rows) seconds before
# a relaunch killed it; it never reported, Jeff had to ask a second time two days after his
# first request, and the replacement had to reconstruct the whole thing by cross-session
# message. The screen is the one artefact available WITHOUT the dying session's cooperation
# -- it shows what it had just done, which is exactly what was missing.
capture_outgoing() {  # org, workspace-ref
  # Two statements on purpose: bash expands every word on a `local` line BEFORE it makes
  # any of the assignments, so a one-liner would build the path from an empty $org, get
  # "$STATE_DIR/.md", find no such file and return 0 -- capturing nothing, silently.
  local org="$1" ws="$2" screen stamp sidecar
  sidecar="$STATE_DIR/$org.md"
  [ -f "$sidecar" ] || return 0
  screen=$(CMUX_QUIET=1 cmux read-screen --workspace "$ws" --scrollback --lines 60 2>/dev/null) || return 0
  [ -n "$screen" ] || return 0
  stamp=$(date -u +%Y-%m-%dT%H:%MZ)
  ORG="$org" WS="$ws" STAMP="$stamp" SIDECAR="$sidecar" SCREEN="$screen" python3 <<'EOP'
import os, pathlib, re
p = pathlib.Path(os.environ['SIDECAR'])
head = "## Last session before relaunch"
block = (f"{head}\n\n"
         f"_Closed {os.environ['STAMP']} by relaunch-org-chats.sh (was {os.environ['WS']}). "
         f"Final screen of the session that was terminated -- read it before assuming nothing\n"
         f"was in flight. Anything it did but never reported is visible here and NOWHERE else._\n\n"
         "```\n" + os.environ['SCREEN'].rstrip() + "\n```\n")
text = p.read_text()
if head in text:                      # replace the previous capture, never accumulate
    text = re.sub(re.escape(head) + r".*?(?=\n## |\Z)", block, text, count=1, flags=re.S)
else:
    text = text.rstrip('\n') + "\n\n" + block
p.write_text(text)
print("  captured final screen -> sidecar")
EOP
}

ws_ref_for() {   # resolve "PD Chat" -> workspace:12 by NAME, refs shift over time
  CMUX_QUIET=1 cmux workspace list 2>/dev/null \
    | sed 's/^[* ]*//' \
    | awk -v want="$1 Chat" '{ref=$1; $1=""; sub(/^ +/,""); if ($0==want) {print ref; exit}}'
}

# Bring an org's checkout back to origin/main before its new session starts.
#
# WHY: a chat is only as good as the tree under it. Every org checkout was found between
# 21 and 291 commits behind origin/main on 2026-09-10, and one (MT) had been serving
# sessions from a three-week-old tree while telling them nothing. A relaunch is the one
# moment nothing is running in the checkout, so it is the moment to resync.
#
# Fast-forward ONLY by default. Untracked files survive (specs, scratch); anything git
# would have to DESTROY -- tracked modifications, local commits -- blocks the sync and
# says so, and the session still launches on the stale tree for the human to sort out.
# --force-main is the human explicitly asking for the destructive version (Rule 9).
sync_to_main() {  # dir
  local dir="$1" dirty counts behind ahead
  git -C "$dir" fetch -q origin 2>/dev/null || { echo "     sync: fetch failed -- tree left as is"; return 0; }
  dirty="$(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null || true)"
  counts="$(git -C "$dir" rev-list --left-right --count origin/main...HEAD 2>/dev/null || printf '0\t0')"
  behind="$(printf '%s' "$counts" | awk '{print $1}')"
  ahead="$(printf '%s' "$counts" | awk '{print $2}')"
  if [ "$FORCE_MAIN" = 1 ] && { [ -n "$dirty" ] || [ "${ahead:-0}" -gt 0 ]; }; then
    echo "     sync: --force-main, DISCARDING:"
    [ -n "$dirty" ] && echo "$dirty" | sed 's/^/       modified: /'
    [ "${ahead:-0}" -gt 0 ] && git -C "$dir" log --oneline origin/main..HEAD | sed 's/^/       commit:   /'
    git -C "$dir" reset --hard origin/main >/dev/null && echo "     sync: hard reset to origin/main"
    return 0
  fi
  if [ -n "$dirty" ]; then
    echo "     sync: SKIPPED -- tracked files modified, a sync would destroy them:"
    echo "$dirty" | sed 's/^/       /'
    return 0
  fi
  if [ "${ahead:-0}" -gt 0 ]; then
    echo "     sync: SKIPPED -- $ahead local commit(s) not on origin/main:"
    git -C "$dir" log --oneline origin/main..HEAD | sed 's/^/       /'
    return 0
  fi
  if [ "${behind:-0}" -eq 0 ]; then echo "     sync: already at origin/main"; return 0; fi
  if git -C "$dir" merge --ff-only origin/main -q 2>/dev/null; then
    echo "     sync: fast-forwarded $behind commit(s) to origin/main"
  else
    echo "     sync: could not fast-forward (diverged) -- tree left as is"
  fi
}

for org in "${ORGS[@]}"; do
  old="$(ws_ref_for "$org")" || true
  # A missing workspace is not an error. The org's chat was closed (or never existed), so
  # there is nothing to replace, nothing to capture and nothing to close -- create it fresh.
  # Preflight still runs below, so a checkout that would refuse to launch never gets an
  # empty pane. Before this, a wiped sidebar left every org "skipped" and the script could
  # not rebuild what it had just torn down.
  fresh=0
  if [ -z "${old:-}" ]; then
    echo "== $org: no '$org Chat' workspace -- creating one from scratch"
    fresh=1
  fi

  # Preflight BEFORE touching the running session. This script creates the
  # replacement and only then closes the old workspace, so an org whose checkout
  # cannot launch would have its live session killed and replaced by a pane that
  # exits immediately. BabaFlow-MT has been in exactly that state since
  # 2026-08-20 (worktree admin dir deleted).
  if ! "$LAUNCH" --check "$org" >/dev/null 2>&1; then
    echo "!! $org: checkout would REFUSE to launch -- leaving the running session ALONE."
    # `|| true` inside the group: --check exits 1 here by definition, and under
    # `set -e -o pipefail` a failing pipeline would abort the whole loop, silently
    # skipping every org after this one.
    { "$LAUNCH" --check "$org" 2>&1 || true; } | sed 's/^/     /'
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # A builder spawned by this chat runs as a TAB in this very workspace, so closing it
  # KILLS that builder. This is not hypothetical: on 2026-09-08 a relaunch closed OH's
  # chat and took two live builders with it (#3490 mid-review on PR #3493, #3492 with an
  # unpushed commit). Their worktrees survived -- the sessions did not.
  tabs=1
  if [ "$fresh" = 0 ]; then tabs="$(ws_tab_count "$old")"; fi
  if [ "${tabs:-1}" -gt 1 ]; then
    echo "!! $org: workspace $old is hosting $((tabs - 1)) builder tab(s) -- NOT relaunching."
    echo "     Closing it would kill them mid-flight. Finish or retire them first:"
    echo "       cmux list-pane-surfaces --workspace $old"
    echo "     Then re-run. Override only if you accept losing those sessions."
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  dir="$("$LAUNCH" --dir "$org" 2>/dev/null || true)"
  if [ -n "$dir" ]; then
    if [ "$DRY" = 1 ]; then echo "     would sync $dir to origin/main"; else sync_to_main "$dir"; fi
  fi

  if [ "$DRY" = 1 ]; then
    echo "would: new-workspace '$org Chat' at the top of folder '$ORG_FOLDER' running: $LAUNCH $org"
    [ "$fresh" = 0 ] && echo "       then close $old" || true
    continue
  fi

  grp="$(group_ref_for "$org")" || true
  if [ -z "${grp:-}" ]; then
    echo "!! $org: could not resolve or create its sidebar folder -- leaving the running session ALONE."
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if [ "$fresh" = 1 ]; then echo "== $org: creating in $ORG_FOLDER ($grp)..."
  else echo "== $org: creating replacement in $ORG_FOLDER ($grp)..."; fi
  CMUX_QUIET=1 cmux new-workspace \
      --name "$org Chat" \
      --command "$LAUNCH $org" \
      --group "$grp" --group-placement top \
      --focus false
  if [ "$fresh" = 0 ]; then
    echo "== $org: closing old $old (quits its claude)"
    capture_outgoing "$org" "$old" || true
    CMUX_QUIET=1 cmux close-workspace --workspace "$old"
  fi
done

echo
[ "$SKIPPED" -gt 0 ] && echo "$SKIPPED org(s) SKIPPED with their sessions left running -- see above."
echo "Done. Each new pane runs: $LAUNCH <ORG>"
echo "Floor per turn: 172,862 -> 144,605 tokens."
