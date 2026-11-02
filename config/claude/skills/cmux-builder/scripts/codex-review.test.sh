#!/usr/bin/env bash
# codex-review.test.sh: runs codex-review.sh --no-tab against a throwaway repo with a stub codex
# on PATH and HOME pointed at a temp dir (so no cg/tpcg is found), and checks the exit code and
# output per case: watchman cookies are not worktree changes, a review that did not go through
# the gateway provider is no verdict, and a real tracked change warns without deciding the exit.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REVIEW_SH="${CODEX_REVIEW_SH:-$HERE/codex-review.sh}"
LIB="$HERE/../../cmux-orchestrator/scripts/lib.sh"
[ -f "$LIB" ] || { echo "FAIL lib.sh not found at $LIB"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home/.claude/skills/cmux-orchestrator/scripts"
ln -s "$LIB" "$TMP/home/.claude/skills/cmux-orchestrator/scripts/lib.sh"
mkdir -p "$TMP/home/.config/claude-gateway"; echo https://gateway.invalid > "$TMP/home/.config/claude-gateway/base"
cat > "$TMP/bin/codex" <<'CODEX'
#!/usr/bin/env bash
provider=claude-gateway
case "$FAKE_MODE" in
  cookie) : > .watchman-cookie-x;;
  other-provider) provider=openai;;
  shim) provider=teamclaude;;
  tracked-clean|tracked-finding) echo changed >> README;;
esac
printf 'OpenAI Codex v0.160.0\n--------\nworkdir: %s\nmodel: gpt-6-astra\nprovider: %s\napproval: never\n--------\n' "$PWD" "$provider" >&2
case "$FAKE_MODE" in
  tracked-finding) printf 'Full review comments:\n\n- [P1] Off by one -- %s/README:1-1\n  The loop skips the last item.\n' "$PWD";;
  *) echo 'The change is small and correct; nothing to flag.';;
esac
CODEX
chmod +x "$TMP/bin/codex"

new_repo() {
  local d="$TMP/$1"
  git init -q --bare "$d/origin.git"
  git clone -q "$d/origin.git" "$d/wt" 2>/dev/null
  git -C "$d/wt" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$d/wt" push -q origin HEAD:main 2>/dev/null
  git -C "$d/wt" fetch -q origin
  git -C "$d/wt" checkout -q -b feature
  echo hello > "$d/wt/README"
  git -C "$d/wt" add README
  git -C "$d/wt" -c user.email=t@t -c user.name=t commit -q -m change
  printf '%s' "$d/wt"
}

pass=0 fail=0 count=0
check() {
  local name=$1 mode=$2 want_rc=$3 want_re=$4 warn=$5 wt rc out
  count=$((count + 1))
  wt=$(new_repo "case$count")
  set +e
  out=$(cd "$wt" && env -u CG_ACTIVE -u CG_KEY -u CG_URL -u CG_CODEX_URL -u ANTHROPIC_BASE_URL -u ANTHROPIC_API_KEY \
        -u BF_SLUG -u BF_LEDGER -u HERDR_ENV -u TERM_PROGRAM \
        ${SHIM:+CG_ACTIVE=1 CG_KEY=fake} HOME="$TMP/home" TMPDIR="$TMP/out$count" FAKE_MODE=$mode PATH="$TMP/bin:$PATH" \
        bash "$REVIEW_SH" --no-tab --timeout 30 2>&1)
  rc=$?
  set -e
  local ok=1
  [ "$rc" -eq "$want_rc" ] || ok=0
  printf '%s\n' "$out" | grep -Eq "$want_re" || ok=0
  if [ "$warn" = yes ]; then
    printf '%s\n' "$out" | grep -q 'WARNING: codex changed the worktree' || ok=0
    printf '%s\n' "$out" | grep -q '^   M README$' || ok=0
  else
    ! printf '%s\n' "$out" | grep -q 'WARNING: codex changed the worktree' || ok=0
  fi
  if [ $ok = 1 ]; then
    pass=$((pass + 1)); echo "ok   $name -> rc=$rc"
  else
    fail=$((fail + 1)); echo "FAIL $name -> want rc=$want_rc /$want_re/ warning=$warn, got rc=$rc:"
    printf '%s\n' "$out" | tail -8 | sed 's/^/       /'
  fi
}

check "watchman cookie + clean review" cookie 0 '^== codex round 1: P0=0 P1=0 P2=0 P3=0 -> CLEAN' no
check "log names another provider" other-provider 2 'review did not reach the gateway' no
check "tracked file changed + clean review" tracked-clean 0 '^== codex round 1: .* -> CLEAN' yes
check "tracked file changed + P1 finding" tracked-finding 1 '^== codex round 1: P0=0 P1=1 P2=0 P3=0 -> 1 to address' yes
SHIM=1 check "cg.sh shim provider (teamclaude) + clean review" shim 0 '^== codex round 1: .* -> CLEAN' no

echo "$pass passed, $fail failed, $count cases"
[ "$fail" -eq 0 ] && [ "$pass" -eq "$count" ]
