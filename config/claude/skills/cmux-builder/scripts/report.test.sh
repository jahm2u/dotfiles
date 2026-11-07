#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPORT_SH="${REPORT_SH:-$HERE/report.sh}"
LIB="$HERE/../../cmux-orchestrator/scripts/lib.sh"
[ -f "$LIB" ] || { echo "FAIL lib.sh not found at $LIB"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home/.claude/skills/cmux-orchestrator/scripts"
ln -s "$LIB" "$TMP/home/.claude/skills/cmux-orchestrator/scripts/lib.sh"
for t in cmux herdr osascript pgrep; do printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/$t"; chmod +x "$TMP/bin/$t"; done
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
[ -f "$CASE_DIR/gh-fails" ] && { echo "error connecting to api.github.com" >&2; exit 1; }
echo "$*" >> "$CASE_DIR/gh.calls"
jqx=. head= sub="$1 $2"
while [ $# -gt 0 ]; do case "$1" in --jq) jqx=$2; shift;; --head) head=$2; shift;; esac; shift; done
case "$sub" in
  "pr list") jq -r --arg h "$head" "[.[] | select(.headRefName == \$h)] | $jqx" "$CASE_DIR/prs.json";;
  *) echo "stub gh: unexpected $sub" >&2; exit 9;;
esac
GH
chmod +x "$TMP/bin/gh"

git init -q "$TMP/repo"
git -C "$TMP/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
LEDGER_DIR="$TMP/repo/_bmad/handoff/cmux"; mkdir -p "$LEDGER_DIR"

pass=0 fail=0 count=0
run_case() {
  local name=$1 phase=$2 msg=$3 prior=$4 prs=$5 gh_fails=$6 want=$7 slug d got
  count=$((count + 1)); slug="case$count"; d="$TMP/$slug"; mkdir -p "$d"
  printf '%s' "$prs" > "$d/prs.json"
  [ "$gh_fails" = 1 ] && : > "$d/gh-fails"
  printf 'BF_SLUG=%s\nBF_BRANCH=fix/mine\nBF_WORKTREE=%s\nBF_ORCH_WS=workspace:test\nBF_ORCH_PEER=test-orch\nBF_MUX=cmux\nBF_STATUS=implementing\nBF_PR=%s\n' \
    "$slug" "$TMP/repo" "$prior" > "$LEDGER_DIR/$slug.env"
  set +e
  out=$(cd "$TMP/repo" && env -u HERDR_ENV -u TERM_PROGRAM -u BF_PR -u BF_BRANCH HOME="$TMP/home" PATH="$TMP/bin:$PATH" CASE_DIR="$d" \
    BF_SLUG="$slug" BF_LEDGER="$LEDGER_DIR/$slug.env" bash "$REPORT_SH" "$phase" "$msg" 2>&1); rc=$?
  set -e
  got=$(sed -n 's/^BF_PR=//p' "$LEDGER_DIR/$slug.env")
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
    pass=$((pass + 1)); echo "ok   $name -> BF_PR='$got'"
  else
    fail=$((fail + 1)); echo "FAIL $name -> want BF_PR='$want', got '$got' rc=$rc: $(printf '%s' "$out" | tail -1)"
  fi
}

OTHER='{"number":99,"state":"MERGED","headRefName":"fix/other"}'
run_case "report text naming #1234 and PR 99, no PR on the branch" pr-open "opened #1234; PR 99 still OPEN" "" "[$OTHER]" 0 ""
run_case "report text naming #1234 while the branch's PR is 4242" pr-open "opened #1234; PR 99 still OPEN" "" "[$OTHER,{\"number\":4242,\"state\":\"OPEN\",\"headRefName\":\"fix/mine\"}]" 0 4242
run_case "gh finds the branch's merged PR" merged "merged" "" '[{"number":4758,"state":"MERGED","headRefName":"fix/mine"}]' 0 4758
run_case "stale ledger PR replaced by the branch's PR" "done" "done, see PR 4753" 4753 '[{"number":4758,"state":"MERGED","headRefName":"fix/mine"}]' 0 4758
run_case "ledger PR already the branch's PR stays" merged "merged" 4758 '[{"number":4758,"state":"MERGED","headRefName":"fix/mine"}]' 0 4758
run_case "stale ledger PR cleared when gh finds none for the branch" pr-open "PR 4753" 4753 "[$OTHER]" 0 ""
run_case "a closed PR on the branch is not the branch's PR" pr-open "PR 4000" "" '[{"number":4000,"state":"CLOSED","headRefName":"fix/mine"}]' 0 ""
run_case "open PR wins over an older closed one on the branch" pr-open "PR 4000" "" '[{"number":4000,"state":"CLOSED","headRefName":"fix/mine"},{"number":4001,"state":"OPEN","headRefName":"fix/mine"}]' 0 4001
run_case "gh lookup failure keeps the ledger PR" converged "PR 1" 4758 '[]' 1 4758
run_case "progress phase never sets BF_PR" implementing "PR 99 and #1234" "" '[{"number":4242,"state":"OPEN","headRefName":"fix/mine"}]' 0 ""

R2=$(mkdir -p "$TMP/r2" && cd "$TMP/r2" && pwd -P); OTHER=$(mkdir -p "$TMP/other" && cd "$TMP/other" && pwd -P)
for r in "$R2" "$OTHER"; do git init -q "$r"; git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init; done
L2="$R2/_bmad/handoff/cmux"; mkdir -p "$L2" "$TMP/home/.local/state/cmux-orchestrator"
printf '%s\n' "$R2" > "$TMP/home/.local/state/cmux-orchestrator/roots"
rep() { # name cwd ledger-env(set|unset|missing) want_rc phase msg -- assertions...
  local name=$1 cwd=$2 mode=$3 want_rc=$4 phase=$5 msg=$6 slug ok=1 rc d
  shift 6; [ "${1:-}" = -- ] && shift
  count=$((count + 1)); slug="rcase$count"; d="$TMP/$slug"; mkdir -p "$d"; printf '[]' > "$d/prs.json"
  printf 'BF_SLUG=%s\nBF_BRANCH=fix/r\nBF_WORKTREE=%s\nBF_ORCH_WS=workspace:test\nBF_ORCH_PEER=test-orch\nBF_MUX=cmux\nBF_STATUS=implementing\nBF_PR=\n' \
    "$slug" "$TMP/nowhere" > "$L2/$slug.env"
  [ -z "${SNAP_BEFORE:-}" ] || (cd "$R2" && HOME="$TMP/home" PATH="$TMP/bin:$PATH" bash -c '. "$0"; bf_shared_snapshot "$1" "$2" "$3"' "$LIB" "$slug" "$TMP/nowhere" "$R2") || true
  [ -z "${SEED:-}" ] || echo seeded > "$R2/$SEED"
  [ -z "${BADSNAP:-}" ] || echo '{' > "$L2/$slug.shared"
  local -a e=(BF_LEDGER="$L2/$slug.env")
  case "$mode" in unset) e=();; missing) e=(BF_LEDGER="$L2/nope-$slug.env");; esac
  [ "$mode" = missing-unknown ] && { e=(BF_LEDGER="$L2/nope-$slug.env"); rm "$L2/$slug.env"; }
  set +e
  out=$(cd "$cwd" && env -u HERDR_ENV -u TERM_PROGRAM -u BF_LEDGER HOME="$TMP/home" PATH="$TMP/bin:$PATH" CASE_DIR="$d" \
    BF_SLUG="$slug" ${e[@]+"${e[@]}"} bash "$REPORT_SH" "$phase" "$msg" 2>&1); rc=$?
  set -e
  [ "$rc" -eq "$want_rc" ] || ok=0
  while [ $# -gt 0 ]; do
    case "$1" in
      has:*) printf '%s' "$out" | grep -qF -- "${1#has:}" || ok=0;;
      not:*) printf '%s' "$out" | grep -qF -- "${1#not:}" && ok=0;;
      status=*) grep -qx "BF_STATUS=${1#status=}" "$L2/$slug.env" || ok=0;;
      logged:*) grep -qF -- "${1#logged:}" "$L2/$slug.log" 2>/dev/null || ok=0;;
      nostub) [ ! -e "$OTHER/_bmad" ] && [ ! -e "$L2/nope-$slug.env" ] && [ ! -e "$L2/nope-$slug.log" ] || ok=0;;
    esac
    shift
  done
  if [ "$ok" = 1 ]; then pass=$((pass + 1)); echo "ok   $name"
  else fail=$((fail + 1)); echo "FAIL $name (rc=$rc): $(printf '%s' "$out" | tail -1)"; fi
}
rep "report from another repo's cwd writes only to BF_LEDGER's dir" "$OTHER" set 0 implementing "working" -- \
  status=implementing "logged:|implementing|working" nostub
rep "BF_LEDGER unset -> ledger resolved by slug" "$R2" unset 0 testing "t" -- status=testing "logged:|testing|t"
rep "BF_LEDGER names a missing file -> ledger resolved by slug, no stub" "$OTHER" missing 0 testing "t" -- status=testing nostub
rep "BF_LEDGER missing and no root has the slug -> dies, no stub" "$R2" missing-unknown 1 testing "t" -- "has:no ledger for slug" nostub
SNAP_BEFORE=1 rep "pr-open with a snapshot and a clean primary -> no shared-state" "$R2" set 0 pr-open "opened" -- \
  "not:shared-state" "logged:|pr-open|opened"
SNAP_BEFORE=1 SEED=seeded.txt rep "pr-open after an untracked write to the primary -> shared-state line appended" "$R2" set 0 pr-open "opened" -- \
  "has:opened; shared-state: $R2: status +?? seeded.txt" "logged:|pr-open|opened; shared-state: $R2: status +?? seeded.txt"
rep "pr-open without a snapshot -> nothing appended" "$R2" set 0 pr-open "opened" -- "not:shared-state"
SNAP_BEFORE=1 rep "a progress phase never checks drift" "$R2" set 0 implementing "x" -- "not:shared-state"
BADSNAP=1 rep "pr-open with an unreadable snapshot -> says the check failed" "$R2" set 0 pr-open "opened" -- \
  "has:opened; shared-state: check failed" "logged:shared-state: check failed"
rm -f "$R2/seeded.txt"

echo "$pass passed, $fail failed, $count cases"
[ "$fail" -eq 0 ] && [ "$pass" -eq "$count" ]
