#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
COLLECT_SH="${COLLECT_SH:-$HERE/collect.sh}"
LIB="$HERE/../../cmux-orchestrator/scripts/lib.sh"
[ -f "$LIB" ] || { echo "FAIL lib.sh not found at $LIB"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home/.claude/skills/cmux-orchestrator/scripts"
ln -s "$LIB" "$TMP/home/.claude/skills/cmux-orchestrator/scripts/lib.sh"
for t in cmux herdr osascript; do printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/$t"; chmod +x "$TMP/bin/$t"; done
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
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

pass=0 fail=0 count=0
run_case() {
  local name=$1 prior=$2 prs=$3 gh_fails=$4 force=$5 want_rc=$6 slug d got ok=1
  shift 6
  count=$((count + 1)); slug="case$count"; d="$TMP/$slug"; mkdir -p "$d"
  printf '%s' "$prs" > "$d/prs.json"
  [ "$gh_fails" = 1 ] && : > "$d/gh-fails"
  printf 'BF_SLUG=%s\nBF_BRANCH=fix/mine\nBF_WORKTREE=%s\nBF_SPEC=%s\nBF_ORCH_WS=workspace:test\nBF_MUX=cmux\nBF_STATUS=done\nBF_BUILDER_WS=\nBF_PR=%s\n' \
    "$slug" "$TMP/repo/.claude/worktrees/wt-$slug" "$TMP/repo/spec-$slug.md" "$prior" > "$LEDGER_DIR/$slug.env"
  set +e
  out=$(cd "$TMP/repo" && env -u BF_SLUG -u HERDR_ENV -u TERM_PROGRAM HOME="$TMP/home" PATH="$TMP/bin:$PATH" CASE_DIR="$d" \
    bash "$COLLECT_SH" "$slug" ${force:+--force} 2>&1); rc=$?
  set -e
  [ "$rc" -eq "$want_rc" ] || ok=0
  while [ $# -gt 0 ]; do
    case "$1" in
      has:*) printf '%s' "$out" | grep -qF -- "${1#has:}" || ok=0;;
      not:*) printf '%s' "$out" | grep -qF -- "${1#not:}" && ok=0;;
      pr=*) got=$(sed -n 's/^BF_PR=//p' "$LEDGER_DIR/$slug.env" 2>/dev/null || true); [ "$got" = "${1#pr=}" ] || ok=0;;
      ledger-kept) [ -f "$LEDGER_DIR/$slug.env" ] || ok=0;;
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

echo "$pass passed, $fail failed, $count cases"
[ "$fail" -eq 0 ] && [ "$pass" -eq "$count" ]
