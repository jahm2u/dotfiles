#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
[ -f "$HERE/lib.sh" ] || { echo "FAIL lib.sh not found at $HERE/lib.sh"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
mkdir -p "$TMP/bin" "$TMP/home/.local/state/cmux-orchestrator"
for t in herdr osascript gh pgrep; do printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/$t"; chmod +x "$TMP/bin/$t"; done
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/cmux"; chmod +x "$TMP/bin/cmux"

for r in a b; do
  git init -q "$TMP/$r"
  git -C "$TMP/$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
done
printf '%s\n' "$TMP/b" > "$TMP/home/.local/state/cmux-orchestrator/roots"
A="$TMP/a/_bmad/handoff/cmux"; B="$TMP/b/_bmad/handoff/cmux"

ledger() { # dir slug
  mkdir -p "$1"
  printf 'BF_SLUG=%s\nBF_MUX=cmux\nBF_STATUS=implementing\nBF_BUILDER_WS=workspace:1\nBF_BUILDER_SURFACE=surface:9\n' "$2" > "$1/$2.env"
}

pass=0 fail=0 count=0
run_case() { # name cwd want_rc cmd... -- assertions...
  local name=$1 cwd=$2 want_rc=$3 ok=1 rc
  local -a cmd=()
  shift 3
  while [ $# -gt 0 ] && [ "$1" != -- ]; do cmd+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  count=$((count + 1))
  set +e
  out=$(cd "$cwd" && env -i HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$TMP" \
    bash "${cmd[@]}" 2>&1); rc=$?
  set -e
  [ "$rc" -eq "$want_rc" ] || ok=0
  while [ $# -gt 0 ]; do
    case "$1" in
      has:*) printf '%s' "$out" | grep -qF -- "${1#has:}" || ok=0;;
      not:*) printf '%s' "$out" | grep -qF -- "${1#not:}" && ok=0;;
      is:*) [ "$out" = "${1#is:}" ] || ok=0;;
      logged:*) grep -qF -- "|orchestrator|hi" "${1#logged:}" 2>/dev/null || ok=0;;
      absent:*) [ ! -e "${1#absent:}" ] || ok=0;;
    esac
    shift
  done
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1)); echo "ok   $name"
  else
    fail=$((fail + 1)); echo "FAIL $name (rc=$rc): $(printf '%s' "$out" | tail -1)"
  fi
}
reset() { rm -rf "$TMP/a/_bmad" "$TMP/b/_bmad"; }

reset; ledger "$B" sib
run_case "tell.sh --log-only finds a ledger in a sibling root" "$TMP/a" 0 "$HERE/tell.sh" sib --log-only hi -- \
  "has:logged for sib" "logged:$B/sib.log" "absent:$A/sib.log"

reset; ledger "$B" sib
run_case "tell.sh --log-only resolves from outside any git repo" "$TMP" 0 "$HERE/tell.sh" sib --log-only hi -- \
  "logged:$B/sib.log"

reset; ledger "$A" dup; ledger "$B" dup
run_case "same slug in two roots dies and names both" "$TMP/a" 1 "$HERE/tell.sh" dup --log-only hi -- \
  "has:$A/dup.env" "has:$B/dup.env" "absent:$A/dup.log" "absent:$B/dup.log"

reset; ledger "$A" here
run_case "unknown slug dies naming it" "$TMP/a" 1 "$HERE/tell.sh" nope --log-only hi -- \
  "has:nope" "absent:$A/nope.log"

reset; ledger "$B" sib
run_case "bf_primary_root is the cwd repo with no ledger loaded" "$TMP/a" 0 -c '. "$0"; bf_primary_root' "$HERE/lib.sh" -- \
  "is:$TMP/a"

reset; ledger "$B" sib
run_case "bf_primary_root follows a ledger loaded from a sibling root" "$TMP/a" 0 -c '. "$0"; bf_load sib; bf_primary_root' "$HERE/lib.sh" -- \
  "is:$TMP/b"

reset; ledger "$A" good; ledger "$B" sib
printf 'BF_STATUS=started\n' > "$A/broken.env"
run_case "ls.sh lists every root and skips a ledger without BF_SLUG" "$TMP/a" 0 "$HERE/ls.sh" -- \
  "has:broken.env" "has:good" "has:sib" "has:root=b " "not:unbound variable"

reset; ledger "$B" sib
run_case "ls.sh <slug> dumps a sibling-root builder" "$TMP/a" 0 "$HERE/ls.sh" sib -- \
  "has:slug=sib"

echo "$pass passed, $fail failed, $count cases"
[ "$fail" -eq 0 ] && [ "$pass" -eq "$count" ]
