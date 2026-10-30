#!/usr/bin/env bash
# pr-watch.test.sh: replays pr-watch-runs.fixture.json through pr-watch.sh --no-review with a stub
# gh on PATH. The fixture is byte-identical to jahm2u/BabaFlow scripts/pr-watch-runs.fixture.json;
# both tests pin its sha256, so the two watchers are held to one verdict per state (BabaFlow#4746).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
FIXTURE="$HERE/pr-watch-runs.fixture.json"
WATCH="${PR_WATCH_SH:-$HERE/pr-watch.sh}"
FIXTURE_SHA256=872e116c3e9436f7472a752ac3f1f4d05baee7451871f09583abc842544bad32

got_sha=$(shasum -a 256 "$FIXTURE" | cut -d' ' -f1)
if [ "$got_sha" != "$FIXTURE_SHA256" ]; then
  echo "FAIL fixture sha256 $got_sha != pinned $FIXTURE_SHA256 (update both repos together)"; exit 1
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") cat "$CASE_DIR/pr.json";;
  "pr checks") cat "$CASE_DIR/checks.json";;
  api*) case "$2 $3" in "repos/{owner}/{repo}/actions/runs?head_sha="*" --jq") cat "$CASE_DIR/runs.json";; *) echo "stub gh: unexpected $*" >&2; exit 9;; esac;;
  *) echo "stub gh: unexpected $*" >&2; exit 9;;
esac
GH
chmod +x "$TMP/bin/gh"

count=$(python3 - "$FIXTURE" "$TMP" <<'PY'
import json, os, sys
fx = json.load(open(sys.argv[1])); out = sys.argv[2]
def bucket(c):
    if c.get("status") != "COMPLETED": return "pending"
    k = c.get("conclusion")
    if k == "SUCCESS": return "pass"
    if k in ("SKIPPED", "NEUTRAL"): return "skipping"
    if k == "CANCELLED": return "cancel"
    return "fail"
for i, c in enumerate(fx["cases"]):
    d = os.path.join(out, f"case{i}"); os.makedirs(d)
    base = {"rollup": [], "runs": []} if c.get("withoutBase") else fx["base"]
    rollup = base["rollup"] + (fx["ciJobs"][c["jobs"]] if c["jobs"] else [])
    runs = base["runs"] + [{**fx["ciRun"], **r} for r in c["ciRuns"]]
    json.dump({"headRefOid": fx["head"], "author": {"login": "jeff"}, "mergeable": "MERGEABLE",
               "state": "OPEN", "reviews": [], "statusCheckRollup": rollup}, open(f"{d}/pr.json", "w"))
    json.dump([{"name": r["name"], "bucket": bucket(r)} for r in rollup], open(f"{d}/checks.json", "w"))
    json.dump({"total_count": len(runs), "workflow_runs": runs}, open(f"{d}/runs.json", "w"))
    open(f"{d}/name", "w").write(c["name"]); open(f"{d}/expect", "w").write(c["expect"])
print(len(fx["cases"]))
PY
)
if [ "$count" -eq 0 ]; then echo "FAIL fixture has no cases"; exit 1; fi

# The fixture cases judge CI state only: switch the local-head comparison off for them.
export PR_WATCH_LOCAL_HEAD= PR_WATCH_LOCAL_BRANCH=
pass=0 fail=0
for ((i = 0; i < count; i++)); do
  d="$TMP/case$i"; expect=$(cat "$d/expect")
  set +e; out=$(CASE_DIR=$d PATH="$TMP/bin:$PATH" bash "$WATCH" 4743 --no-review 2>&1); rc=$?; set -e
  last=$(printf '%s\n' "$out" | tail -1)
  case "$expect" in
    CONVERGED) want_rc=0 want_re='^CONVERGED';;
    WAITING) want_rc=2 want_re='^WAITING';;
    CI_FAILED) want_rc=1 want_re='^NOT-CONVERGED failing checks'
  esac
  if [ "$rc" -eq "$want_rc" ] && printf '%s' "$last" | grep -Eq "$want_re"; then
    pass=$((pass + 1)); echo "ok   $(cat "$d/name") -> $expect"
  else
    fail=$((fail + 1)); echo "FAIL $(cat "$d/name") -> want $expect, got rc=$rc: $last"
  fi
done
d="$TMP/no-checks"; mkdir -p "$d"
printf '%s' '{"headRefOid":"abc","author":{"login":"jeff"},"mergeable":"MERGEABLE","state":"OPEN","reviews":[],"statusCheckRollup":[]}' > "$d/pr.json"
printf '[]' > "$d/checks.json"; printf '{"total_count":0,"workflow_runs":[]}' > "$d/runs.json"
set +e; out=$(CASE_DIR=$d PATH="$TMP/bin:$PATH" bash "$WATCH" 4743 --no-review 2>&1); rc=$?; set -e
last=$(printf '%s\n' "$out" | tail -1); count=$((count + 1))
if [ "$rc" -eq 2 ] && [ "$last" = "WAITING no checks registered on the head yet" ]; then
  pass=$((pass + 1)); echo "ok   no check and no run registered on the head (#877) -> WAITING"
else
  fail=$((fail + 1)); echo "FAIL no check and no run registered on the head (#877) -> want WAITING, got rc=$rc: $last"
fi

# A green, finished stale head while the pushed head is local (#966, 2026-10-30) -> WAITING.
d="$TMP/stale-head"; mkdir -p "$d"
printf '%s' '{"headRefOid":"aaaa1111","headRefName":"fix/x","author":{"login":"jeff"},"mergeable":"MERGEABLE","state":"OPEN","reviews":[],"statusCheckRollup":[{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"SUCCESS"}]}' > "$d/pr.json"
printf '%s' '[{"name":"test","bucket":"pass"}]' > "$d/checks.json"; printf '{"total_count":0,"workflow_runs":[]}' > "$d/runs.json"
set +e; out=$(CASE_DIR=$d PR_WATCH_LOCAL_HEAD=bbbb2222 PR_WATCH_LOCAL_BRANCH=fix/x PATH="$TMP/bin:$PATH" bash "$WATCH" 966 --no-review 2>&1); rc=$?; set -e
last=$(printf '%s\n' "$out" | tail -1); count=$((count + 1))
if [ "$rc" -eq 2 ] && printf '%s' "$last" | grep -q '^WAITING PR head aaaa1111 is not the local HEAD bbbb2222'; then
  pass=$((pass + 1)); echo "ok   PR head lags the local pushed head (#966) -> WAITING"
else
  fail=$((fail + 1)); echo "FAIL PR head lags the local pushed head (#966) -> want WAITING, got rc=$rc: $last"
fi
# Same state from another branch's checkout: no comparison, so the finished checks converge.
set +e; out=$(CASE_DIR=$d PR_WATCH_LOCAL_HEAD=bbbb2222 PR_WATCH_LOCAL_BRANCH=main PATH="$TMP/bin:$PATH" bash "$WATCH" 966 --no-review 2>&1); rc=$?; set -e
last=$(printf '%s\n' "$out" | tail -1); count=$((count + 1))
if [ "$rc" -eq 0 ] && printf '%s' "$last" | grep -q '^CONVERGED'; then
  pass=$((pass + 1)); echo "ok   other branch's checkout does not compare heads -> CONVERGED"
else
  fail=$((fail + 1)); echo "FAIL other branch's checkout -> want CONVERGED, got rc=$rc: $last"
fi
# gh pr checks empty while the rollup has finished entries: a lagging read, never a pass.
d="$TMP/empty-checks"; mkdir -p "$d"
cp "$TMP/stale-head/pr.json" "$d/pr.json"; printf '[]' > "$d/checks.json"; printf '{"total_count":0,"workflow_runs":[]}' > "$d/runs.json"
set +e; out=$(CASE_DIR=$d PATH="$TMP/bin:$PATH" bash "$WATCH" 966 --no-review 2>&1); rc=$?; set -e
last=$(printf '%s\n' "$out" | tail -1); count=$((count + 1))
if [ "$rc" -eq 2 ] && [ "$last" = "WAITING gh pr checks lists no checks for the head yet" ]; then
  pass=$((pass + 1)); echo "ok   gh pr checks empty, rollup finished -> WAITING"
else
  fail=$((fail + 1)); echo "FAIL gh pr checks empty, rollup finished -> want WAITING, got rc=$rc: $last"
fi

echo "$pass passed, $fail failed, $count cases"
[ "$fail" -eq 0 ] && [ "$pass" -eq "$count" ]
