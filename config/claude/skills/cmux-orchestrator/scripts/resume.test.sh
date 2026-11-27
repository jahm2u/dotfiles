#!/usr/bin/env bash
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
RESUME_SH="${RESUME_SH:-$HERE/resume.sh}"
[ -f "$HERE/lib.sh" ] || { echo "FAIL lib.sh not found at $HERE/lib.sh"; exit 1; }
JQ=$(command -v jq) || { echo "FAIL jq not on PATH"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
SCRIPTS="$TMP/scripts"; mkdir -p "$SCRIPTS" "$TMP/bin"
cp "$RESUME_SH" "$SCRIPTS/resume.sh"; cp "$HERE/lib.sh" "$SCRIPTS/lib.sh"
ln -s "$JQ" "$TMP/bin/jq"
for t in gh tpcg cg herdr cmux; do printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/$t"; done
cat > "$TMP/bin/claude" <<'CLAUDE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CASE_DIR/claude.argv"
env > "$CASE_DIR/claude.env"
CLAUDE
APP="$TMP/Orca.app"; mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/MacOS/Orca" <<'ORCA'
#!/usr/bin/env bash
shift
while [ $# -gt 0 ]; do [ "$1" = --command ] && printf '%s' "$2" > "$CASE_DIR/orca.command"; shift; done
echo '{"ok":true,"result":{"terminal":{"handle":"term_t1","paneKey":"tab1:leaf1"}}}'
ORCA
chmod +x "$TMP/bin/"* "$APP/Contents/MacOS/Orca"

HOME_T="$TMP/home"
mkdir -p "$HOME_T/.claude/skills/cmux-builder" "$HOME_T/.claude/skills/ux-video-review/scripts"
echo '{}' > "$HOME_T/.claude/skills/cmux-builder/builder-settings.json"
AGENTS='{"ux-evidence": {"description": "d", "prompt": "p"}}'
printf 'print(%s)\n' "'$AGENTS'" > "$HOME_T/.claude/skills/ux-video-review/scripts/agents_json.py"

git init -q -b main "$TMP/repo"
git -C "$TMP/repo" remote add origin "https://github.com/someone/repo.git"
WT="$TMP/repo/.claude/worktrees/wt-x"; mkdir -p "$WT"
CM="$TMP/repo/_bmad/handoff/cmux"; mkdir -p "$CM"
SID=4379477a-0000-4000-8000-000000000001
PD="$HOME_T/.claude/projects/$(printf '%s' "$WT" | sed 's#[/._]#-#g')"; mkdir -p "$PD"; : > "$PD/$SID.jsonl"

pass=0 fail=0 count=0
check() { # name want got
  count=$((count + 1))
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "ok   $1"; else fail=$((fail + 1)); printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$1" "$2" "$3"; fi
}
after() { grep -A1 -xF -- "$1" "$2" 2>/dev/null | sed -n 2p; }

D="$TMP/case-orca"; mkdir -p "$D"
printf 'BF_SLUG=x\nBF_BRANCH=feat/x\nBF_WORKTREE=%s\nBF_SPEC=%s\nBF_MODEL=opus[1m]\nBF_MODE=yolo\nBF_MCP=none\nBF_MUX=orca\n' \
  "$WT" "$WT/_bmad-output/spec-x.md" > "$CM/x.env"
out=$(cd "$TMP/repo" && env -i HOME="$HOME_T" PATH="$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$TMP" CASE_DIR="$D" \
  ORCA_APP="$APP" TERM_PROGRAM=Orca ORCA_TERMINAL_HANDLE=term_orch ORCA_WORKTREE_ID='repo1::/orch' ORCH_PEER=orch-1 \
  bash "$SCRIPTS/resume.sh" x "$SID" 2>&1); rc=$?
check "resume.sh under Orca exits 0" "0" "$rc"
[ "$rc" = 0 ] || printf '%s\n' "$out" | tail -3
check "resume.sh handed Orca a command" "yes" "$([ -s "$D/orca.command" ] && echo yes)"
( cd "$TMP" && env -i HOME="$HOME_T" PATH="$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin" CASE_DIR="$D" \
    CLAUDE_CODE_PLUGIN_DIRS="/orca/claude-agent-view/h/orca-agent-view" \
    bash -c "$(cat "$D/orca.command" 2>/dev/null)" ) >/dev/null 2>&1
check "the Orca tab's command started claude" "yes" "$([ -s "$D/claude.argv" ] && echo yes)"
check "claude resumed the builder's own session" "$SID" "$(after --resume "$D/claude.argv")"
check "claude got the helper agents through --agents" "$AGENTS" "$(after --agents "$D/claude.argv")"
check "the env file was sourced (BF_SLUG reached claude)" "BF_SLUG=x" "$(grep -x 'BF_SLUG=x' "$D/claude.env" 2>/dev/null)"
check "Orca's CLAUDE_CODE_PLUGIN_DIRS did not reach claude (it drops every --agents definition)" "" \
  "$(grep '^CLAUDE_CODE_PLUGIN_DIRS=' "$D/claude.env" 2>/dev/null)"

echo "$pass passed, $fail failed, $count cases"
[ "$fail" -eq 0 ] && [ "$pass" -eq "$count" ]
