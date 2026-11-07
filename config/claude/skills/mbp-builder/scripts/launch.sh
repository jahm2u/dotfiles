#!/bin/bash
# launch.sh: start a builder on the MBP in herdr session `builders`, in its own worktree of a separate clone.
# usage: launch.sh --repo owner/repo --slug <slug> --branch <branch> --brief <file>
#                  [--orchestrator <name>] [--model claude-opus-5-5] [--report-term <orca handle>]
#                  [--report-repo <tell-mini repo>] [--report-host <mbp's ssh alias for this Mac>]
#                  [--rules <file>] [--min-free 20] [--no-venv]
set -euo pipefail
. "$(dirname "$0")/lib.sh"

repo="" slug="" branch="" brief="" orch="the orchestrator" model="claude-opus-5-5"
term="${ORCA_TERMINAL_HANDLE:-}" report_repo="" report_host="" rules="" min_free=20 venv=1
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo=$2; shift 2 ;;
    --slug) slug=$2; shift 2 ;;
    --branch) branch=$2; shift 2 ;;
    --brief) brief=$2; shift 2 ;;
    --orchestrator) orch=$2; shift 2 ;;
    --model) model=$2; shift 2 ;;
    --report-term) term=$2; shift 2 ;;
    --report-repo) report_repo=$2; shift 2 ;;
    --report-host) report_host=$2; shift 2 ;;
    --rules) rules=$2; shift 2 ;;
    --min-free) min_free=$2; shift 2 ;;
    --no-venv) venv=0; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) die "unknown argument $1" ;;
  esac
done
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "--repo owner/repo is required"
[[ "$slug" =~ ^[a-z0-9][a-z0-9-]{1,40}$ ]] || die "--slug must match ^[a-z0-9][a-z0-9-]{1,40}$"
[[ "$branch" =~ ^[A-Za-z0-9._/-]+$ ]] && [ "$branch" != main ] || die "--branch is required and is not main"
[ -s "$brief" ] && [ "$(wc -c < "$brief")" -ge 100 ] || die "--brief must be a file of at least 100 bytes"
if [ -z "$report_repo" ]; then
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  report_repo=$(basename "${common%/.git}")
  [ -n "$report_repo" ] && [ "$report_repo" != . ] || die "--report-repo is required outside a git checkout"
fi
if [ -z "$rules" ] && [ -f orchestrator/fixes/_rules.md ]; then rules=orchestrator/fixes/_rules.md; fi
agent="b-$slug"
[ -n "$report_host" ] || report_host=$(default_report_host)
[[ "$report_host" =~ ^[A-Za-z0-9._-]+$ ]] || die "--report-host must be an ssh alias"
tell="~/.claude/skills/mbp-builder/scripts/tell-mini"
[ -x "$SKILL_DIR/scripts/tell-mini" ] || die "missing $SKILL_DIR/scripts/tell-mini"

install_remote
seen=$(with_timeout 20 ssh -o ConnectTimeout=10 -o BatchMode=yes "$MBP_HOST" \
  "ssh -o ConnectTimeout=8 -o BatchMode=yes $report_host 'test -x $tell && hostname'" 2>/dev/null || true)
[ "$seen" = "$(hostname)" ] || die "$MBP_HOST cannot run $tell on '$report_host' (got '${seen:-nothing}', expected $(hostname)); pass --report-host"
echo "report path: $MBP_HOST -> ssh $report_host ($seen)"
free=$(mbb 20 mem | sed -n 's/^free=//p')
[[ "$free" =~ ^[0-9]+$ ]] || die "could not read MBP memory ($free)"
[ "$free" -ge "$min_free" ] || die "MBP has only ${free}% memory free (minimum ${min_free}%): not launching"
echo "mbp memory free: ${free}%"
mbb 30 server
mbb 300 clone "$repo"
mbb 60 worktree "$repo" "$slug" "$branch"
wt="builders/wt/$slug"
home=$(with_timeout 10 ssh -o ConnectTimeout=10 -o BatchMode=yes "$MBP_HOST" 'printf %s "$HOME"')
wt_abs="$home/$wt"
if [ "$venv" = 1 ]; then mbb 900 venv "$wt_abs"; fi
dir="builders/briefs/$slug"
push "$brief" "$dir/brief.md"
[ -n "$rules" ] && push "$rules" "$dir/_rules.md"

pin=""; [ -n "$term" ] && pin="MINI_TERM=$term "
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
{
  echo "# Kickoff: $slug (MBP builder)"
  echo
  echo "You are a builder running on the MBP in herdr session \`$MBB_SESSION\` as agent \`$agent\`."
  echo "Your worktree is \`~/$wt\` (branch \`$branch\`), a worktree of the separate clone \`~/builders/${repo##*/}\`."
  echo "It is NOT a live checkout: never touch \`~/repos/...\`, the herdr sessions mkt-crew or dev-crew, or any seat."
  echo
  echo "Your orchestrator is \`$orch\`, on the Mac \`$report_host\` ($(hostname)). SendMessage cannot reach it. To report"
  echo "(your design or plan before code, being blocked, a finding that changes the plan, anything outward-facing,"
  echo "done), write the message to a file and run:"
  echo
  echo "    ssh -o ConnectTimeout=10 $report_host '${pin}$tell $report_repo mbp:$MBB_SESSION/$agent' < <file>"
  echo
  echo "Also append each report to \`~/$dir/log.md\`. Answers arrive typed into your pane. Never ask the human directly."
  echo "Push only with the explicit refspec \`git push origin HEAD:$branch\`. Open PRs with"
  echo "\`GH_CONFIG_DIR=~/.config/gh-mp gh pr create ...\`; if gh answers 401 here, push and tell the orchestrator,"
  echo "which opens the PR from the Mini."
  echo
  [ -n "$rules" ] && echo "Read \`~/$dir/_rules.md\` first, then the brief: \`~/$dir/brief.md\`." \
                  || echo "Read the brief: \`~/$dir/brief.md\`."
} > "$tmp"
push "$tmp" "$dir/kickoff.md"
printf 'Read ~/%s/kickoff.md and follow it. Report through the channel it names.\n' "$dir" > "$tmp"
push "$tmp" "$dir/kickoff-line.txt"

panes=$(mbb 30 pane "$slug" "$wt_abs")
ws=$(sed -n 's/.*ws=\([^ ]*\).*/\1/p' <<< "$panes"); pane=$(sed -n 's/.*pane=\([^ ]*\).*/\1/p' <<< "$panes")
[ -n "$ws" ] && [ -n "$pane" ] || die "could not create a herdr workspace ($panes)"
mbb 20 ledger-set "$slug" "REPO=$repo" "BRANCH=$branch" "WT=$wt_abs" "CLONE=$home/builders/${repo##*/}" \
  "WS=$ws" "PANE=$pane" "AGENT=$agent" "ORCH=$orch" "REPORT_HOST=$report_host" "REPORT_TERM=$term" "MODEL=$model" >/dev/null
mbb 20 start "$pane" "$model" "$slug" >/dev/null

ready=0
for _ in $(seq 1 45); do
  sleep 2
  screen=$(mbb 20 read "$pane" 30 2>/dev/null || true)
  if grep -q -i "trust this folder" <<< "$screen"; then mbb 20 keys "$pane" Enter >/dev/null; continue; fi
  if grep -q "Bypass Permissions mode" <<< "$screen" && grep -q "Yes, I accept" <<< "$screen"; then
    mbb 20 keys "$pane" Down Enter >/dev/null; continue
  fi
  if grep -q -E "bypass permissions|\? for shortcuts|❯" <<< "$screen"; then ready=1; break; fi
done
[ "$ready" = 1 ] || die "claude did not reach its prompt in $pane within 90 s (peek.sh $slug)"
mbb 70 rename "$pane" "$agent"
mbb 20 prompt "$agent" "$home/$dir/kickoff-line.txt" >/dev/null

working=0
for _ in $(seq 1 45); do
  sleep 2
  if mbb 20 read "$pane" 80 2>/dev/null | grep -q -E "⏺ [A-Za-z]+\(|(Read|Listed|Searched|Wrote|Updated|Edited|ran|Ran) [0-9]+ |shell command"; then
    working=1; break
  fi
done
echo "agent: $agent  pane: $pane  workspace: $ws  worktree: ~/$wt"
echo "attach: herdr --remote $MBP_HOST --session $MBB_SESSION"
echo "reports: ~/.local/state/from-mbp/ on $(hostname) via ssh $report_host (tell-mini $report_repo${term:+, pinned to $term})"
[ "$working" = 1 ] && echo "verified: a tool call within 90 s" \
                   || { echo "NOT verified: no tool call within 90 s; run peek.sh $slug" >&2; exit 3; }
