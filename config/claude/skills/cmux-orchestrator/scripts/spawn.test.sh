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
  local name=$1 load=$2 alive=$3 force=$4 want_rc=$5 slug d ok=1
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
      *) break;;
    esac
    shift
  done
  set +e
  out=$(cd "$TMP/repo" && env -i HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$TMP" CASE_DIR="$d" \
    bash "$SCRIPTS/spawn.sh" --slug "$slug" --spec "$TMP/spec.md" ${force:+--force} 2>&1); rc=$?
  set -e
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

echo "$pass passed, $fail failed, $count cases"
[ "$fail" -eq 0 ] && [ "$pass" -eq "$count" ]
