#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
COLLECT_SH="${COLLECT_SH:-$HERE/collect.sh}"
LIB="$HERE/../../cmux-orchestrator/scripts/lib.sh"
[ -f "$LIB" ] || { echo "FAIL lib.sh not found at $LIB"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home/.claude/skills/cmux-orchestrator/scripts"
ln -s "$LIB" "$TMP/home/.claude/skills/cmux-orchestrator/scripts/lib.sh"
for t in osascript pgrep; do printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/$t"; chmod +x "$TMP/bin/$t"; done
cat > "$TMP/bin/fakemux" <<'MUX'
#!/usr/bin/env bash
mux=$1; shift
[ -f "$CASE_DIR/state" ] || exit 1
state=$(cat "$CASE_DIR/state")
ev() {
  echo "$1" >> "$CASE_DIR/keys"
  local next; next=$(awk -v s="$state" -v e="$1" '$1 == s && $2 == e { print $3 }' "$CASE_DIR/rules")
  if [ -n "$next" ]; then echo "$next" > "$CASE_DIR/state"; fi
}
scr() { cat "$SCREENS/$state"; }
case "$mux $1 ${2:-}" in
  "cmux list-pane-surfaces"*) echo "  surface:9  builder";;
  "cmux read-screen"*) scr;;
  "cmux send-key"*)
    key=${*: -1}
    case "$key" in
      ctrl+u) ;;
      enter) if [ "$(cat "$CASE_DIR/typed" 2>/dev/null)" = /exit ]; then rm -f "$CASE_DIR/typed"; ev exit; else ev enter; fi;;
      *) ev "$key";;
    esac;;
  "cmux send "*) printf '%s' "${*: -1}" > "$CASE_DIR/typed";;
  "cmux close-surface"*) ev close;;
  "herdr pane get") ;;
  "herdr agent get")
    case "$state" in shell*) echo '{"error":{"code":"agent_not_found","message":"agent target not found"}}'; exit 1;; esac
    echo '{"result":{"agent":{"agent":"claude","agent_status":"idle"}}}';;
  "herdr agent prompt") if [ "$4" = /exit ]; then ev exit; else ev "text:$4"; fi;;
  "herdr pane read") scr;;
  "herdr pane send-keys") ev "$4";;
  "herdr tab close") ev close;;
  "herdr "*) ;;
  "orca terminal show") echo '{"ok":true,"result":{"terminal":{"connected":true}}}';;
  "orca terminal read") scr | python3 -c 'import json,sys; print(json.dumps({"ok":True,"result":{"terminal":{"tail":sys.stdin.read().splitlines()}}}))';;
  "orca terminal send")
    text= enter=0 retry=0
    while [ $# -gt 0 ]; do case "$1" in --text) text=$2; shift;; --enter) enter=1;; --retry-request) retry=1;; esac; shift; done
    if [ $retry = 0 ]; then
      case "$text:$enter" in
        /exit:1) ev exit;;
        :1) ev enter;;
        $'\e':0) ev esc;;
        *) ev "text:$text";;
      esac
    fi
    echo '{"ok":true,"result":{"send":{"prompt":{"stages":[],"requestId":"r1"}}}}';;
  "orca terminal close") ev close; echo '{"ok":true,"result":{}}';;
  "orca "*) echo '{"ok":true,"result":{}}';;
  *) exit 1;;
esac
MUX
for m in cmux herdr; do printf '#!/usr/bin/env bash\nexec "%s/bin/fakemux" %s "$@"\n' "$TMP" "$m" > "$TMP/bin/$m"; done
mkdir -p "$TMP/Orca.app/Contents/MacOS"
printf '#!/usr/bin/env bash\nshift\nexec "%s/bin/fakemux" orca "$@"\n' "$TMP" > "$TMP/Orca.app/Contents/MacOS/Orca"
chmod +x "$TMP/bin/fakemux" "$TMP/bin/cmux" "$TMP/bin/herdr" "$TMP/Orca.app/Contents/MacOS/Orca"
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$PWD $1 $2" >> "$CASE_DIR/gh.calls"
[ -f "$CASE_DIR/gh-fails" ] && { echo "error connecting to api.github.com" >&2; exit 1; }
jqx=. head= sub="$1 $2" num=${3:-}
while [ $# -gt 0 ]; do case "$1" in --jq) jqx=$2; shift;; --head) head=$2; shift;; esac; shift; done
case "$sub" in
  "pr list") jq -r --arg h "$head" "[.[] | select(.headRefName == \$h)] | $jqx" "$CASE_DIR/prs.json";;
  "pr view")
    jq -e --argjson n "$num" 'any(.[]; .number == $n)' "$CASE_DIR/prs.json" >/dev/null \
      || { echo "GraphQL: Could not resolve to a PullRequest with the number of $num. (repository.pullRequest)" >&2; exit 1; }
    jq -r --argjson n "$num" "[.[] | select(.number == \$n)][0] | $jqx" "$CASE_DIR/prs.json";;
  "run list") echo "[]" | jq -r "$jqx";;
  *) echo "stub gh: unexpected $sub" >&2; exit 9;;
esac
GH
chmod +x "$TMP/bin/gh"

git init -q "$TMP/repo"
git -C "$TMP/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
LEDGER_DIR="$TMP/repo/_bmad/handoff/cmux"; mkdir -p "$LEDGER_DIR"

pass=0 fail=0 count=0 BUILDER='' SCREEN='' RULES='' EXIT_WAIT=20
run_case() {
  local name=$1 prior=$2 prs=$3 gh_fails=$4 force=$5 want_rc=$6 slug d got ok=1
  shift 6
  count=$((count + 1)); slug="case$count"; d="$TMP/$slug"; mkdir -p "$d"
  printf '%s' "$prs" > "$d/prs.json"
  [ "$gh_fails" = 1 ] && : > "$d/gh-fails"
  if [ -n "$BUILDER" ]; then echo "$SCREEN" > "$d/state"; printf '%s\n' "$RULES" > "$d/rules"; : > "$d/keys"; fi
  { printf 'BF_SLUG=%s\nBF_BRANCH=fix/mine\nBF_WORKTREE=%s\nBF_SPEC=%s\nBF_ORCH_WS=workspace:test\nBF_MUX=cmux\nBF_STATUS=done\nBF_BUILDER_WS=\nBF_PR=%s\n' \
    "$slug" "$TMP/repo/.claude/worktrees/wt-$slug" "$TMP/repo/spec-$slug.md" "$prior"; printf '%s' "$BUILDER"; } > "$LEDGER_DIR/$slug.env"
  if [ -n "${PRE:-}" ]; then eval "$PRE" || true; fi
  set +e
  out=$(cd "$TMP/repo" && env -u BF_SLUG -u HERDR_ENV -u TERM_PROGRAM HOME="$TMP/home" PATH="$TMP/bin:$PATH" CASE_DIR="$d" \
    SCREENS="$TMP/screens" ORCA_APP="$TMP/Orca.app" BF_EXIT_WAIT="$EXIT_WAIT" \
    bash "$COLLECT_SH" "$slug" ${force:+--force} 2>&1); rc=$?
  set -e
  [ "$rc" -eq "$want_rc" ] || ok=0
  while [ $# -gt 0 ]; do
    case "$1" in
      has:*) printf '%s' "$out" | grep -qF -- "${1#has:}" || ok=0;;
      not:*) printf '%s' "$out" | grep -qF -- "${1#not:}" && ok=0;;
      pr=*) got=$(sed -n 's/^BF_PR=//p' "$LEDGER_DIR/$slug.env" 2>/dev/null || true); [ "$got" = "${1#pr=}" ] || ok=0;;
      ledger-kept) [ -f "$LEDGER_DIR/$slug.env" ] || ok=0;;
      arch:*) grep -qF -- "${1#arch:}" "$LEDGER_DIR/archive/$slug/shared-state.txt" 2>/dev/null || ok=0;;
      snap-archived) [ -f "$LEDGER_DIR/archive/$slug/$slug.shared" ] && [ ! -e "$LEDGER_DIR/$slug.shared" ] || ok=0;;
      keys=*) got=$(tr '\n' ' ' < "$d/keys" | sed 's/ $//'); [ "$got" = "${1#keys=}" ] || { ok=0; out="$out
keys sent: '$got', want '${1#keys=}'"; };;
    esac
    shift
  done
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1)); echo "ok   $name"
  else
    fail=$((fail + 1)); echo "FAIL $name (rc=$rc): $(printf '%s' "$out" | grep -v '^==>' | tail -1)"
  fi
}

MINE_OPEN='{"number":50,"state":"OPEN","headRefName":"fix/mine"}'
MINE_MERGED='{"number":50,"state":"MERGED","headRefName":"fix/mine"}'
OTHER_MERGED='{"number":77,"state":"MERGED","headRefName":"fix/other"}'
run_case "BF_PR is another branch's merged PR -> refuses with both branches" 77 "[$MINE_OPEN,$OTHER_MERGED]" 0 "" 1 \
  "has:fix/other" "has:fix/mine" "has:BF_PR=77" "not:DONE:" ledger-kept
run_case "--force does not override a PR/branch mismatch" 77 "[$MINE_OPEN,$OTHER_MERGED]" 0 1 1 \
  "has:fix/other" "has:fix/mine" "not:DONE:" ledger-kept
run_case "BF_PR is an issue number (gh pr view fails) -> refuses, lookup failed" 363 "[$MINE_OPEN]" 0 "" 1 \
  "has:gh lookup failed" "has:retry" "not:DONE:" ledger-kept
run_case "gh unreachable with BF_PR set -> lookup failed, not a mismatch" 50 "[$MINE_MERGED]" 1 "" 1 \
  "has:gh lookup failed" "has:retry" "not:not this builder's branch" "not:DONE:" ledger-kept
run_case "gh unreachable with BF_PR unset -> lookup failed" "" "[$MINE_MERGED]" 1 1 1 \
  "has:gh lookup failed" "has:retry" "not:DONE:" ledger-kept pr=
run_case "BF_PR matches the branch -> passes the check, stops at not MERGED" 50 "[$MINE_OPEN,$OTHER_MERGED]" 0 "" 1 \
  "has:==> PR 50: OPEN" "has:not MERGED" "not:gh lookup failed" "not:not this builder's branch" ledger-kept
run_case "BF_PR unset -> found by branch and recorded" "" "[$OTHER_MERGED,$MINE_OPEN]" 0 "" 1 \
  "has:==> PR 50: OPEN" "has:not MERGED" ledger-kept pr=50
run_case "BF_PR unset, no PR on the branch -> state none" "" "[$OTHER_MERGED]" 0 "" 1 \
  "has:==> PR none: none" "has:not MERGED" ledger-kept pr=
run_case "BF_PR matches a merged PR -> collects the sandbox" 50 "[$MINE_MERGED,$OTHER_MERGED]" 0 "" 0 \
  "has:==> PR 50: MERGED" "has:DONE: case9 collected. PR 50 (MERGED)"

REPO_P=$(cd "$TMP/repo" && pwd -P)
SNAP='(cd "$TMP/repo" && env -i HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin" bash -c ". \"\$0\"; bf_shared_snapshot \"\$1\" \"\$2\" \"\$3\"" "$LIB" "$slug" "$TMP/repo/.claude/worktrees/wt-$slug" "$TMP/repo")'
PRE="$SNAP; echo x > \"\$TMP/repo/drift-\$slug.txt\"" run_case "drift since spawn -> printed, archived, and still collects" 50 "[$MINE_MERGED]" 0 "" 0 \
  "has:shared-state: $REPO_P: status +?? drift-case$((count + 1)).txt" "arch:shared-state: $REPO_P: status +?? drift-case$((count + 1)).txt" snap-archived "has:DONE:"
rm -f "$TMP/repo"/drift-*.txt
PRE="$SNAP" run_case "clean since spawn -> no shared-state line, snapshot archived" 50 "[$MINE_MERGED]" 0 "" 0 \
  "not:shared-state:" "arch:clean: no shared-state drift" snap-archived "has:DONE:"
run_case "ledger older than the guard -> not checked (no snapshot), still collects" 50 "[$MINE_MERGED]" 0 "" 0 \
  "has:shared-state: not checked (no snapshot)" "arch:shared-state: not checked (no snapshot)" "has:DONE:"
PRE='mkdir -p "$LEDGER_DIR/archive/$slug"; : > "$LEDGER_DIR/archive/$slug/$slug.shared"; echo "shared-state: earlier run: status +?? lost.txt" > "$LEDGER_DIR/archive/$slug/shared-state.txt"' \
  run_case "retry after the snapshot was archived -> keeps the archived report" 50 "[$MINE_MERGED]" 0 "" 0 \
  "has:shared-state: earlier run: status +?? lost.txt" "arch:shared-state: earlier run: status +?? lost.txt" "not:not checked (no snapshot)" "has:DONE:"

mkdir -p "$TMP/screens"
cat > "$TMP/screens/claude" <<'SCR'
⏺ PR 50 merged. Reported done to the orchestrator.

✻ Crunched for 15s · done 11:44 PM

────────────────────────────────────────────────────────────────────────────────
❯
────────────────────────────────────────────────────────────────────────────────
  wt-fix-mine | ⎇ fix/mine(+0,-0)
  Opus 5.5 | 21.9% | 3hr 44m
  ⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents
SCR
cat > "$TMP/screens/claude-pct" <<'SCR'
⏺ PR 50 merged. Reported done to the orchestrator.

────────────────────────────────────────────────────────────────────────────────
❯
────────────────────────────────────────────────────────────────────────────────
  wt-fix-mine | ctx 21%
SCR
cat > "$TMP/screens/typed" <<'SCR'
⏺ PR 50 merged. Reported done to the orchestrator.

────────────────────────────────────────────────────────────────────────────────
❯ /exit
────────────────────────────────────────────────────────────────────────────────
  Opus 5.5 | 21.9% | 3hr 44m
  ⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents
SCR
cat > "$TMP/screens/tasks" <<'SCR'
⏺ PR 50 merged. Reported done to the orchestrator.

❯ /exit

   Background work is running
   The following will stop when you exit:

   scheduled task · 17 8-21 * * 1-5 · Bug bounty interim pulse (chief-of-staff covers u…
   scheduled task · Runs once in 1d · WED 07/10 Dev HQ prep: re-open the Dev HQ prep or…

   ❯ 1. Exit and stop tasks
     2. Move to background and exit
     3. Stay

   Enter to confirm · Esc to cancel
SCR
cat > "$TMP/screens/tasks-narrow" <<'SCR'
 Background work is running
 The following will stop when y…

 scheduled task · */20 * * * * · Pul…

 ❯ 1. Exit and stop tas…
   2. Move to backgroun…
   3. Stay
SCR
sed -e 's/❯ 1\. Exit/  1. Exit/' -e 's/  3\. Stay/❯ 3. Stay/' "$TMP/screens/tasks" > "$TMP/screens/tasks-stay"
cat > "$TMP/screens/drafts" <<'SCR'
⏺ PR 50 merged. Reported done to the orchestrator.

❯ /exit

You have 1 unsent feedback draft
Enter to review & send · Esc to discard and exit
SCR
cat > "$TMP/screens/shell" <<'SCR'
⏺ PR 50 merged. Reported done to the orchestrator.

❯ /exit
  ⎿  Goodbye!

v@mbp wt-fix-mine %
SCR

builder_case() { # name mux start-screen rules want-keys [assertions...]
  local name=$1 mux=$2 keys=$5
  SCREEN=$3 RULES=$4
  case "$mux" in
    cmux) BUILDER=$'BF_MUX=cmux\nBF_BUILDER_WS=workspace:test\nBF_BUILDER_SURFACE=surface:9\n';;
    herdr) BUILDER=$'BF_MUX=herdr\nBF_BUILDER_WS=w9\nBF_BUILDER_SURFACE=w9:p1\nBF_BUILDER_TAB=w9:t1\n';;
    orca) BUILDER=$'BF_MUX=orca\nBF_BUILDER_WS=repo::/tmp/x\nBF_BUILDER_SURFACE=term_x\nBF_BUILDER_TAB=t1:l1\n';;
  esac
  shift 5
  run_case "$name" 50 "[$MINE_MERGED]" 0 "" 0 "keys=$keys" "has:DONE:" "$@"
  BUILDER='' SCREEN='' RULES='' EXIT_WAIT=20
}
CLEAN=$'claude exit shell'
TASKS=$'claude exit tasks\ntasks enter shell'
DRAFTS=$'claude exit drafts\ndrafts esc shell'
DRAFTS_TASKS=$'claude exit drafts\ndrafts esc tasks\ntasks enter shell'
for mux in cmux herdr orca; do
  builder_case "$mux: clean exit -> /exit, then closes the tab" $mux claude "$CLEAN" "exit close" "has:builder exited"
  builder_case "$mux: 'Background work is running' -> Enter on 1. Exit and stop tasks" $mux claude "$TASKS" "exit enter close" "has:Exit and stop tasks"
  builder_case "$mux: unsent feedback draft -> Esc, discard and exit" $mux claude "$DRAFTS" "exit esc close" "has:unsent feedback draft"
  builder_case "$mux: already back at its shell -> no /exit, closes the tab" $mux shell "" "close" "has:skipping /exit"
done
builder_case "cmux: feedback draft, then background work -> Esc, then Enter" cmux claude "$DRAFTS_TASKS" "exit esc enter close"
builder_case "cmux: narrow 'Background work is running' -> Enter" cmux claude $'claude exit tasks-narrow\ntasks-narrow enter shell' "exit enter close"
builder_case "cmux: dialog already up before collect -> no /exit, answers it" cmux tasks $'tasks enter shell' "enter close"
builder_case "cmux: /exit typed but its Enter lost -> Enter again" cmux claude $'claude exit typed\ntyped enter shell' "exit enter close"
builder_case "cmux: statusline ending in % is not a shell" cmux claude-pct $'claude-pct exit shell' "exit close" "not:skipping /exit"
EXIT_WAIT=3
builder_case "cmux: Stay selected -> never pressed, tab closed after the wait" cmux claude $'claude exit tasks-stay' "exit close" "has:WARNING"

count=$((count + 1)); d="$TMP/case$count"; mkdir -p "$d" "$TMP/home/.local/state/cmux-orchestrator"
SIB=$(cd "$TMP" && mkdir -p sib && cd sib && pwd -P); REPO=$(cd "$TMP/repo" && pwd -P)
git init -q "$SIB"
git -C "$SIB" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$SIB" worktree add -q -b fix/mine "$SIB/.claude/worktrees/wt-xroot"
git -C "$REPO" branch fix/mine
printf '%s\n' "$SIB" > "$TMP/home/.local/state/cmux-orchestrator/roots"
mkdir -p "$SIB/_bmad/handoff/cmux"
printf 'BF_SLUG=xroot\nBF_BRANCH=fix/mine\nBF_WORKTREE=%s\nBF_SPEC=%s\nBF_ORCH_WS=workspace:test\nBF_MUX=cmux\nBF_STATUS=done\nBF_BUILDER_WS=\nBF_PR=50\n' \
  "$SIB/.claude/worktrees/wt-xroot" "$SIB/spec-xroot.md" > "$SIB/_bmad/handoff/cmux/xroot.env"
printf '[%s]' "$MINE_MERGED" > "$d/prs.json"
set +e
out=$(cd "$REPO" && env -u BF_SLUG -u HERDR_ENV -u TERM_PROGRAM HOME="$TMP/home" PATH="$TMP/bin:$PATH" CASE_DIR="$d" \
  SCREENS="$TMP/screens" ORCA_APP="$TMP/Orca.app" bash "$COLLECT_SH" xroot 2>&1); rc=$?
set -e
ok=1 why=""
[ "$rc" -eq 0 ] || { ok=0; why="rc=$rc"; }
[ ! -d "$SIB/.claude/worktrees/wt-xroot" ] || { ok=0; why="$why; sibling worktree still there"; }
git -C "$SIB" show-ref --verify --quiet refs/heads/fix/mine && { ok=0; why="$why; sibling branch kept"; }
git -C "$REPO" show-ref --verify --quiet refs/heads/fix/mine || { ok=0; why="$why; cwd repo's fix/mine deleted"; }
grep -q "^$SIB pr view" "$d/gh.calls" 2>/dev/null || { ok=0; why="$why; gh not run in the sibling"; }
grep -qv "^$SIB " "$d/gh.calls" 2>/dev/null && { ok=0; why="$why; gh run outside the sibling"; }
[ -f "$SIB/_bmad/handoff/cmux/archive/xroot/ledger.env" ] || { ok=0; why="$why; not archived in the sibling"; }
if [ "$ok" = 1 ]; then pass=$((pass + 1)); echo "ok   collect from a sibling cwd targets the ledger's repo"
else fail=$((fail + 1)); echo "FAIL collect from a sibling cwd targets the ledger's repo ($why): $(printf '%s' "$out" | tail -1)"; fi

echo "$pass passed, $fail failed, $count cases"
[ "$fail" -eq 0 ] && [ "$pass" -eq "$count" ]
