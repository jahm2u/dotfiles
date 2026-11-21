#!/usr/bin/env bash
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
[ -f "$HERE/lib.sh" ] || { echo "FAIL lib.sh not found at $HERE/lib.sh"; exit 1; }
# shellcheck disable=SC1091
. "$HERE/lib.sh"

pass=0 fail=0
check() { # name want got
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$1" "$2" "$3"; fi
}
drift() { local want=$1 mode=$2; shift 2; printf '%s\n' "$@" | bf_launch_drift "$want" "$mode" | paste -sd ';' -; }

check "a builder launched as spawn.sh launches it does not drift" "" \
  "$(drift 'opus[1m]' yolo claude --model 'opus[1m]' --dangerously-skip-permissions --settings /x.json ANTHROPIC_BASE_URL=http://100.127.163.81:3456 ANTHROPIC_MODEL=)"
check "the 2026-11-20 herdr restore drifts on every count" \
  "model expected opus[1m], running default;bypass expected on, missing;gateway expected a Claude pool, running https://claude.ipmedia.com.br/kimi;env ANTHROPIC_MODEL=k3.1-pro[1m];env CG_KIMI_PINNED=k3.1-pro[1m]" \
  "$(drift 'opus[1m]' yolo claude --resume 4379477a ANTHROPIC_BASE_URL=https://claude.ipmedia.com.br/kimi 'ANTHROPIC_MODEL=k3.1-pro[1m]' 'CG_KIMI_PINNED=k3.1-pro[1m]')"
check "--model=value is read like --model value" "" "$(drift sonnet yolo claude --model=sonnet --dangerously-skip-permissions)"
check "another Claude model is drift" "model expected opus[1m], running sonnet" "$(drift 'opus[1m]' yolo claude --model sonnet --dangerously-skip-permissions)"
check "a non-yolo mode must be the one passed" "permission-mode expected auto, running default" "$(drift 'opus[1m]' auto claude --model 'opus[1m]')"
check "a non-yolo mode that matches does not drift" "" "$(drift 'opus[1m]' auto claude --model 'opus[1m]' --permission-mode auto)"
check "a pinned default of another vendor is drift" "env ANTHROPIC_DEFAULT_OPUS_MODEL=k3.1-pro[1m]" \
  "$(drift 'opus[1m]' yolo claude --model 'opus[1m]' --dangerously-skip-permissions 'ANTHROPIC_DEFAULT_OPUS_MODEL=k3.1-pro[1m]')"
check "a builder asked to run on Kimi is not judged by the Claude route" "" \
  "$(drift 'k3.1-pro[1m]' yolo claude --model 'k3.1-pro[1m]' --dangerously-skip-permissions ANTHROPIC_BASE_URL=https://claude.ipmedia.com.br/kimi 'ANTHROPIC_MODEL=k3.1-pro[1m]')"

# The watchdog itself: one poll against stubbed processes and a stubbed herdr pane.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
WT="$TMP/repo/.claude/worktrees/wt-x"; CM="$TMP/repo/_bmad/handoff/cmux"
mkdir -p "$TMP/bin" "$WT" "$CM" "$TMP/home/.local/state/cmux-orchestrator"
git init -q "$TMP/repo"
printf 'BF_SLUG=x\nBF_MUX=herdr\nBF_MODEL=opus[1m]\nBF_MODE=yolo\nBF_BUILDER_WS=w9\nBF_BUILDER_SURFACE=w9:p1\nBF_WORKTREE=%s\n' "$WT" > "$CM/x.env"
cat > "$TMP/bin/herdr" <<'H'
#!/usr/bin/env bash
case "$*" in *"pane read"*) printf '⏺ waiting\n❯ \n';; esac
exit 0
H
printf '#!/usr/bin/env bash\necho 4242\n' > "$TMP/bin/pgrep"
printf '#!/usr/bin/env bash\necho p4242; echo "n%s"\n' "$WT" > "$TMP/bin/lsof"
cat > "$TMP/bin/ps" <<'P'
#!/usr/bin/env bash
cat "$PS_LINE"
P
chmod +x "$TMP/bin/"*
poll() { # ps-line -> what one watchdog poll printed
  printf '%s\n' "$1" > "$TMP/ps.line"; rm -rf "$CM/.watchdog"
  ( cd "$TMP/repo" && PATH="$TMP/bin:$PATH" HOME="$TMP/home" PS_LINE="$TMP/ps.line" \
      "$HERE/watchdog.sh" --interval 30 > "$TMP/out" 2>/dev/null & echo $! > "$TMP/pid" )
  for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q . "$TMP/out" 2>/dev/null && break; sleep 0.3; done
  sleep 1; kill "$(cat "$TMP/pid")" 2>/dev/null; wait 2>/dev/null
  grep DRIFT "$TMP/out" || true
}
got=$(poll "claude --resume 4379477a ANTHROPIC_BASE_URL=https://claude.ipmedia.com.br/kimi ANTHROPIC_MODEL=k3.1-pro[1m]")
case "$got" in
  "[watchdog] x DRIFT -- pid 4242 is not the builder its ledger launched: model expected opus[1m], running default;bypass expected on, missing;gateway expected a Claude pool"*"Relaunch it: resume.sh x")
    pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); printf 'FAIL watchdog emits DRIFT for a Kimi-restored builder\n  got: %s\n' "$got" ;;
esac
got=$(poll "claude --model opus[1m] --dangerously-skip-permissions ANTHROPIC_BASE_URL=http://100.127.163.81:3456")
check "watchdog stays silent for a builder on its ledger's launch" "" "$got"

echo "drift.test.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && [ "$pass" -eq 10 ]
