#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SPAWN_SH="${SPAWN_SH:-$HERE/spawn.sh}"
[ -f "$HERE/lib.sh" ] || { echo "FAIL lib.sh not found at $HERE/lib.sh"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
mkdir -p "$TMP/bin" "$TMP/home/.local/state/cmux-orchestrator"
SCRIPTS="$TMP/scripts"; mkdir -p "$SCRIPTS"
cp "$SPAWN_SH" "$SCRIPTS/spawn.sh"; cp "$HERE/lib.sh" "$SCRIPTS/lib.sh"
for t in herdr osascript gh tpcg cg; do printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/$t"; chmod +x "$TMP/bin/$t"; done
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
cat > "$TMP/bin/cmux" <<'CMUX'
#!/usr/bin/env bash
echo "$*" >> "$CASE_DIR/cmux.calls"
case "$1" in
  identify) echo '{"caller":{"workspace_ref":"workspace:1","surface_ref":"surface:1"}}';;
  list-pane-surfaces) cat "$CASE_DIR/surfaces";;
  new-surface) echo "OK surface:99 pane:1 workspace:1";;
esac
exit 0
CMUX
cat > "$TMP/bin/sysctl" <<'SYSCTL'
#!/usr/bin/env bash
case "$*" in
  "-n vm.loadavg") echo "{ $(cat "$CASE_DIR/load") 1.00 1.00 }";;
  "-n hw.ncpu") echo 4;;
  *) exit 1;;
esac
SYSCTL
cat > "$TMP/bin/pgrep" <<'PGREP'
#!/usr/bin/env bash
[ -f "$CASE_DIR/pids" ] || exit 1
cut -d' ' -f1 "$CASE_DIR/pids"
PGREP
cat > "$TMP/bin/lsof" <<'LSOF'
#!/usr/bin/env bash
pid=; while [ $# -gt 0 ]; do [ "$1" = -p ] && pid=$2; shift; done
out=$(sed -n "s|^$pid |n|p" "$CASE_DIR/pids"); [ -n "$out" ] || exit 1
echo "$out"
LSOF
chmod +x "$TMP/bin/"*

git init -q --bare "$TMP/origin.git"
git init -q -b main "$TMP/repo"
git -C "$TMP/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$TMP/repo" remote add origin "$TMP/origin.git"
git -C "$TMP/repo" push -q origin main
mkdir -p "$TMP/repo/_bmad/scripts" "$TMP/repo/.agents/skills/bmad-build"
: > "$TMP/repo/_bmad/scripts/render_skill.py"
printf -- '---\nstatus: draft\n---\n# spec\n' > "$TMP/spec.md"
LEDGER_DIR="$TMP/repo/_bmad/handoff/cmux"; mkdir -p "$LEDGER_DIR"
OTHER_DIR="$TMP/other/_bmad/handoff/cmux"; mkdir -p "$OTHER_DIR"
THIRD_DIR="$TMP/third/_bmad/handoff/cmux"; mkdir -p "$THIRD_DIR" "$TMP/third/.claude/worktrees/wt-x"
printf '%s\n' "$TMP/other" "$TMP/gone" > "$TMP/home/.local/state/cmux-orchestrator/roots"

ledger() { # dir slug surface
  printf 'BF_SLUG=%s\nBF_MUX=cmux\nBF_STATUS=implementing\nBF_BUILDER_WS=workspace:1\nBF_BUILDER_SURFACE=%s\n' "$2" "$3" > "$1/$2.env"
}

pass=0 fail=0 count=0
run_case() {
  local name=$1 load=$2 alive=$3 force=$4 want_rc=$5 slug d ok=1 owner="" model=""
  local -a extra=()
  shift 5
  count=$((count + 1)); slug="case$count"; d="$TMP/$slug"; mkdir -p "$d"
  printf '%s\n' "$load" > "$d/load"; : > "$d/cmux.calls"; : > "$d/surfaces"
  for s in $alive; do printf '  surface:%s  🔨 x\n' "$s" >> "$d/surfaces"; done
  rm -f "$LEDGER_DIR"/*.env "$OTHER_DIR"/*.env "$THIRD_DIR"/*.env
  while [ $# -gt 0 ]; do
    case "$1" in
      here:*) ledger "$LEDGER_DIR" "${1#here:}" "surface:${1##*-}";;
      other:*) ledger "$OTHER_DIR" "${1#other:}" "surface:${1##*-}";;
      third:*) ledger "$THIRD_DIR" "${1#third:}" "surface:${1##*-}";;
      pid) printf '4242 %s\n4243\n' "$TMP/third/.claude/worktrees/wt-x" > "$d/pids";;
      env:*) extra+=("${1#env:}");;
      owner:*) owner=${1#owner:};;
      model:*) model=${1#model:};;
      *) break;;
    esac
    shift
  done
  [ -z "$owner" ] || git -C "$TMP/repo" remote set-url origin "https://github.com/$owner/repo.git"
  set +e
  out=$(cd "$TMP/repo" && env -i HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$TMP" CASE_DIR="$d" ${extra[@]+"${extra[@]}"} \
    bash "$SCRIPTS/spawn.sh" --slug "$slug" --spec "$TMP/spec.md" ${force:+--force} ${model:+--model "$model"} 2>&1); rc=$?
  set -e
  git -C "$TMP/repo" remote set-url origin "$TMP/origin.git"
  [ "$rc" -eq "$want_rc" ] || ok=0
  while [ $# -gt 0 ]; do
    case "$1" in
      has:*) printf '%s' "$out" | grep -qF -- "${1#has:}" || ok=0;;
      ledger:*) grep -qx -- "${1#ledger:}" "$LEDGER_DIR/$slug.env" 2>/dev/null || ok=0;;
      snapshot) python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); sys.exit(0 if [r["root"] for r in s["roots"]] == [sys.argv[2]] and s["worktree"] == sys.argv[3] else 1)' \
        "$LEDGER_DIR/$slug.shared" "$TMP/repo" "$TMP/repo/.claude/worktrees/wt-$slug" 2>/dev/null || ok=0;;
      untouched)
        [ ! -e "$LEDGER_DIR/$slug.env" ] || ok=0
        [ ! -e "$TMP/repo/.claude/worktrees/wt-$slug" ] || ok=0
        git -C "$TMP/repo" show-ref --verify --quiet "refs/heads/feat/$slug" && ok=0
        grep -q '^new-surface' "$d/cmux.calls" && ok=0;;
      spawned) [ -d "$TMP/repo/.claude/worktrees/wt-$slug" ] && grep -q '^new-surface' "$d/cmux.calls" || ok=0;;
    esac
    shift
  done
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1)); echo "ok   $name"
  else
    fail=$((fail + 1)); echo "FAIL $name (rc=$rc): $(printf '%s' "$out" | grep -v '^==>' | grep -v '^    ' | tail -1)"
  fi
}

run_case "3 live builders (2 here, 1 in another repo) refuses" 1.00 "11 12 13" "" 1 \
  here:a-11 here:b-12 other:c-13 -- \
  "has:3 live builders" "has:BF_MAX_BUILDERS=3" "has:repo/a-11" "has:repo/b-12" "has:other/c-13" "has:load 1.00" "has:BF_MAX_LOAD=8" "has:--force" untouched
run_case "2 live builders passes the gate" 1.00 "11 12" "" 0 \
  here:a-11 other:b-12 -- \
  "has:2/3 live builders" spawned "ledger:BF_FORCED=0" snapshot
run_case "3 ledgers but only 2 alive passes" 1.00 "11 12" "" 0 \
  here:a-11 here:b-12 other:c-13 -- \
  "has:2/3 live builders" spawned
run_case "load above the ceiling refuses" 9.50 "" "" 1 \
  -- \
  "has:0 live builders" "has:load 9.50" "has:BF_MAX_LOAD=8" "has:--force" untouched
run_case "--force passes over both and records BF_FORCED=1" 9.50 "11 12 13" 1 0 \
  here:a-11 here:b-12 other:c-13 -- \
  "has:--force" spawned "ledger:BF_FORCED=1"
run_case "a live builder in a repo found only by its process counts" 1.00 "11 12 13" "" 1 \
  here:a-11 here:b-12 third:x-13 pid -- \
  "has:3 live builders" "has:third/x-13" untouched
run_case "a sibling root holding the same slug refuses and names it" 1.00 "" "" 1 \
  other:case7 -- \
  "has:in another repo" "has:other/_bmad/handoff/cmux/case7.env" untouched
run_case "a sibling root holding another slug still spawns into the cwd repo" 1.00 "" "" 0 \
  other:z-14 -- \
  spawned "ledger:BF_SLUG=case8"

KIMI=env:ANTHROPIC_BASE_URL=https://gw.example/kimi
run_case "a jahm2u repo refuses a Claude builder on a /kimi route before creating anything" 1.00 "" "" 1 \
  owner:jahm2u "$KIMI" has:"refusing to spawn" has:"ANTHROPIC_BASE_URL=https://gw.example/kimi" untouched
run_case "a jahm2u repo refuses a Claude builder whose inherited model is not Claude" 1.00 "" "" 1 \
  owner:jahm2u env:ANTHROPIC_BASE_URL=https://gw.example env:ANTHROPIC_MODEL=k3.1-pro[1m] has:"ANTHROPIC_MODEL=k3.1-pro[1m]" untouched
run_case "another owner's repo is warned, not refused, and spawns" 1.00 "" "" 0 \
  "$KIMI" has:"WARNING: 'case" spawned
run_case "a Claude route spawns" 1.00 "" "" 0 \
  env:ANTHROPIC_BASE_URL=https://gw.example spawned
run_case "a Kimi model asked for on purpose spawns on the /kimi route" 1.00 "" "" 0 \
  "$KIMI" model:k3.1-pro[1m] spawned

orca_case() {
  local name="an Orca tab keeps --agents: CLAUDE_CODE_PLUGIN_DIRS from Orca never reaches claude" slug d ok=1 app agents argv
  count=$((count + 1)); slug="case$count"; d="$TMP/$slug"; mkdir -p "$d"
  printf '1.00\n' > "$d/load"; : > "$d/cmux.calls"; : > "$d/surfaces"
  rm -f "$LEDGER_DIR"/*.env "$OTHER_DIR"/*.env "$THIRD_DIR"/*.env
  app="$TMP/Orca.app"; mkdir -p "$app/Contents/MacOS" "$TMP/home/.claude/skills/ux-video-review/scripts"
  cat > "$app/Contents/MacOS/Orca" <<'ORCA'
#!/usr/bin/env bash
shift
while [ $# -gt 0 ]; do [ "$1" = --command ] && printf '%s' "$2" > "$CASE_DIR/orca.command"; shift; done
echo '{"ok":true,"result":{"terminal":{"handle":"term_t1","paneKey":"tab1:leaf1"}}}'
ORCA
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$CASE_DIR/claude.argv"\nenv > "$CASE_DIR/claude.env"\n' > "$TMP/bin/claude"
  chmod +x "$app/Contents/MacOS/Orca" "$TMP/bin/claude"
  agents='{"ux-evidence": {"description": "d", "prompt": "p"}}'
  printf 'print(%s)\n' "'$agents'" > "$TMP/home/.claude/skills/ux-video-review/scripts/agents_json.py"
  set +e
  out=$(cd "$TMP/repo" && env -i HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$TMP" CASE_DIR="$d" \
    ORCA_APP="$app" TERM_PROGRAM=Orca ORCA_TERMINAL_HANDLE=term_orch ORCA_WORKTREE_ID='repo1::/orch' \
    bash "$SCRIPTS/spawn.sh" --slug "$slug" --spec "$TMP/spec.md" 2>&1); rc=$?
  ( cd "$TMP" && env -i HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin" CASE_DIR="$d" \
      CLAUDE_CODE_PLUGIN_DIRS="/orca/claude-agent-view/h/orca-agent-view" \
      bash -c "$(cat "$d/orca.command" 2>/dev/null)" ) >/dev/null 2>&1
  set -e
  argv=$(grep -A1 -xF -- --agents "$d/claude.argv" 2>/dev/null | sed -n 2p)
  [ "$rc" -eq 0 ] || ok=0
  [ -s "$d/orca.command" ] || ok=0
  [ -s "$d/claude.argv" ] || ok=0
  [ "$argv" = "$agents" ] || ok=0
  grep -qx "BF_SLUG=$slug" "$d/claude.env" 2>/dev/null || ok=0
  ! grep -q '^CLAUDE_CODE_PLUGIN_DIRS=' "$d/claude.env" 2>/dev/null || ok=0
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1)); echo "ok   $name"
  else
    fail=$((fail + 1)); echo "FAIL $name (rc=$rc, agents=${argv:-none}, $(grep '^CLAUDE_CODE_PLUGIN_DIRS=' "$d/claude.env" 2>/dev/null || echo 'no PLUGIN_DIRS')): $(printf '%s' "$out" | grep -v '^==>' | tail -1)"
  fi
}
orca_case

echo "$pass passed, $fail failed, $count cases"
[ "$fail" -eq 0 ] && [ "$pass" -eq "$count" ]
