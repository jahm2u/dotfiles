#!/usr/bin/env bash
# pr-watch.sh <N> [--wait] [--timeout-min M] [--reviewer LOGIN]
#
# Repo-agnostic convergence check for the builder's review loop (BabaFlow keeps its own
# scripts/pr-watch.js, which imports BabaFlow's reviewer service; use that one there).
#
# A PR is CONVERGED for its CURRENT head when all three hold:
#   1. every check on the head is green (pass or skipping; none pending, none failing), and
#      the latest run of each workflow (per workflow and event) for the head sha has finished:
#      a run queued with no jobs yet is pending, a finished one with no jobs that did not
#      succeed is failing, a finished one with jobs is decided by its jobs (jahm2u/BabaFlow#4746).
#      "Performance budget" is advisory, as in BabaFlow's pr-watch.js; both share one fixture.
#   2. the newest review from the reviewer bot is ON the head commit and reports
#      critical=0 and high=0 (the fleet panel's "critical=N high=N medium=N low=N" line)
#   3. GitHub does not report the PR as CONFLICTING
# Medium/low findings do not block; they are printed so the builder dispositions them.
#
# Reviewer: newest review whose author matches --reviewer, else $PR_WATCH_REVIEWER, else any
# author ending in "-reviewer" or "[bot]" that is not the PR author.
# Output: one status block; last line is CONVERGED, NOT-CONVERGED <why> or WAITING <why>.
# --no-review (or PR_WATCH_NO_REVIEW=1): skip gate 2; CI green + no conflict converges. Jeff,
# 2026-10-19: Codex reviews locally are the review; don't wait on the GitHub review bot.
# Exit: 0 converged, 1 not converged, 2 still waiting (only without --wait, or on timeout).
set -euo pipefail
N=${1:?usage: pr-watch.sh <N> [--wait] [--timeout-min M] [--reviewer LOGIN]}; shift
WAIT=0 TIMEOUT_MIN=60 REVIEWER=${PR_WATCH_REVIEWER:-}
while [ $# -gt 0 ]; do case "$1" in
  --wait) WAIT=1; shift;;
  --timeout-min) TIMEOUT_MIN=$2; shift 2;;
  --reviewer) REVIEWER=$2; shift 2;;
  --no-review) NO_REVIEW=1; shift;;
  *) echo "unknown arg $1" >&2; exit 64;;
esac; done

check_once() {
  local pr checks head runs
  pr=$(gh pr view "$N" --json headRefOid,author,mergeable,state,reviews,statusCheckRollup)
  checks=$(gh pr checks "$N" --json name,bucket 2>/dev/null || echo '[]')
  head=$(PR_JSON=$pr python3 -c 'import json, os; print(json.loads(os.environ["PR_JSON"])["headRefOid"])')
  runs=$(gh api "repos/{owner}/{repo}/actions/runs?head_sha=$head&per_page=100" \
    --jq '{total_count, workflow_runs: [.workflow_runs[] | {id, workflow_id, event, name, status, conclusion, run_attempt}]}') \
    || { echo "WAITING could not read the workflow runs for $head"; return 2; }
  PR_JSON=$pr CHECKS_JSON=$checks RUNS_JSON=$runs REVIEWER=$REVIEWER NO_REVIEW=${NO_REVIEW:-${PR_WATCH_NO_REVIEW:-}} python3 - <<'PY'
import json, os, re, sys
pr = json.loads(os.environ["PR_JSON"]); checks = json.loads(os.environ["CHECKS_JSON"] or "[]")
head = pr["headRefOid"]; author = (pr.get("author") or {}).get("login", "")
want = os.environ.get("REVIEWER", "").strip().lower()
print(f"PR #{os.environ.get('N','')} head {head[:8]} state={pr.get('state')} mergeable={pr.get('mergeable')}")
if pr.get("state") != "OPEN":
    print(f"NOT-CONVERGED pr is {pr.get('state')}"); sys.exit(1)

pending = [c["name"] for c in checks if c.get("bucket") == "pending"]
# gh pr checks can omit runs still QUEUED behind the runner backlog (#535 merged with its gate
# unrun, 2026-10-19). The rollup lists them, so anything there without a conclusion is pending too.
for r in pr.get("statusCheckRollup") or []:
    name = r.get("name") or r.get("context") or "?"
    unfinished = (r.get("__typename") == "StatusContext" and r.get("state") in ("PENDING", "EXPECTED")) or \
                 (r.get("__typename") != "StatusContext" and r.get("status") != "COMPLETED")
    if unfinished and name not in pending: pending.append(name)
ADVISORY = {"Performance budget"}
advisory = [c["name"] for c in checks if c.get("bucket") in ("fail", "cancel") and c["name"] in ADVISORY]
failing = [c["name"] for c in checks if c.get("bucket") in ("fail", "cancel") and c["name"] not in ADVISORY]

runs_doc = json.loads(os.environ["RUNS_JSON"] or "{}")
all_runs = runs_doc.get("workflow_runs")
if not isinstance(all_runs, list):
    print("WAITING workflow_runs missing from the actions/runs response"); sys.exit(2)
if int(runs_doc.get("total_count") or 0) > len(all_runs):
    print(f"WAITING {runs_doc.get('total_count')} workflow runs on the head, only {len(all_runs)} read: refusing a partial list"); sys.exit(2)
latest = {}
for r in all_runs:
    k = (r.get("workflow_id"), r.get("event"))
    if k not in latest or int(r.get("id") or 0) > int(latest[k].get("id") or 0): latest[k] = r
with_jobs = set()
for r in pr.get("statusCheckRollup") or []:
    m = re.search(r"/actions/runs/(\d+)(?:/|$)", r.get("detailsUrl") or "")
    if m: with_jobs.add(m.group(1))
for r in latest.values():
    name = f"{r.get('name')} (run)"
    if (r.get("status") or "").lower() != "completed":
        if name not in pending: pending.append(name)
    elif str(r.get("id")) not in with_jobs and (r.get("conclusion") or "").lower() not in ("success", "neutral", "skipped"):
        failing.append(name)

print(f"  checks: {len(checks)} total, {len(pending)} pending, {len(failing)} failing; runs: {len(latest)} latest")
for n in failing: print(f"    failing: {n}")
for n in advisory: print(f"    advisory failing (does not block): {n}")

def is_reviewer(login):
    l = (login or "").lower()
    if want: return l == want
    return l != author.lower() and (l.endswith("-reviewer") or l.endswith("[bot]"))
revs = [r for r in pr.get("reviews", []) if is_reviewer((r.get("author") or {}).get("login"))]
latest = revs[-1] if revs else None
counts = None
if latest:
    on = (latest.get("commit") or {}).get("oid", "")
    m = {k: re.search(rf"{k}=(\d+)", latest.get("body") or "") for k in ("critical", "high", "medium", "low")}
    if all(m.values()): counts = {k: int(v.group(1)) for k, v in m.items()}
    print(f"  review: {(latest.get('author') or {}).get('login')} on {on[:8]}"
          + (f" critical={counts['critical']} high={counts['high']} medium={counts['medium']} low={counts['low']}" if counts else " (no severity line; read the body)"))
else:
    on = ""; print("  review: none yet from the reviewer")

if failing: print("NOT-CONVERGED failing checks: " + ", ".join(failing)); sys.exit(1)
if pr.get("mergeable") == "CONFLICTING": print("NOT-CONVERGED merge conflict with the base: merge origin/main"); sys.exit(1)
if pending: print("WAITING checks pending: " + ", ".join(pending)); sys.exit(2)
# Zero checks right after a push means none has registered yet, not that all passed (#877, 2026-10-27).
if not checks and not (pr.get("statusCheckRollup") or []): print("WAITING no checks registered on the head yet"); sys.exit(2)
if os.environ.get("NO_REVIEW"): print("CONVERGED (review bot skipped: --no-review)"); sys.exit(0)
if not latest or on != head: print("WAITING no review on the current head yet"); sys.exit(2)
if counts is None: print("NOT-CONVERGED review on head has no severity line: read it and decide"); sys.exit(1)
if counts["critical"] or counts["high"]:
    print(f"NOT-CONVERGED blocking findings: critical={counts['critical']} high={counts['high']}"); sys.exit(1)
print("CONVERGED"); sys.exit(0)
PY
}

export N
deadline=$(( $(date +%s) + TIMEOUT_MIN * 60 ))
while :; do
  set +e; out=$(check_once 2>&1); rc=$?; set -e
  if [ $rc -ne 2 ] || [ $WAIT -eq 0 ]; then echo "$out"; exit $rc; fi
  if [ "$(date +%s)" -ge "$deadline" ]; then echo "$out"; echo "(timed out after ${TIMEOUT_MIN} min)"; exit 2; fi
  sleep 30
done
