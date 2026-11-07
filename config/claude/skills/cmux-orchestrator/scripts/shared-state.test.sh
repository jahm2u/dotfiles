#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
LIB="${LIB_SH:-$HERE/lib.sh}"
[ -f "$LIB" ] || { echo "FAIL lib.sh not found at $LIB"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
mkdir -p "$TMP/bin" "$TMP/home/.local/state/cmux-orchestrator"
for t in herdr osascript gh pgrep cmux; do printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/$t"; chmod +x "$TMP/bin/$t"; done

G() { git -c user.email=t@t -c user.name=t "$@"; }

N=0 ROOT="" WT="" LD="" CLONE=""
fresh() {
  N=$((N + 1)); local d="$TMP/c$N"; mkdir -p "$d"
  git init -q --bare -b main "$d/origin.git"
  git init -q -b main "$d/root"
  ROOT="$d/root"; CLONE="$d/clone"
  printf 'node_modules/\n' > "$ROOT/.gitignore"
  echo a > "$ROOT/a.txt"
  G -C "$ROOT" add .gitignore a.txt; G -C "$ROOT" commit -q -m init
  git -C "$ROOT" remote add origin "$d/origin.git"
  git -C "$ROOT" push -q -u origin main 2>/dev/null
  git clone -q "$d/origin.git" "$CLONE" 2>/dev/null
  mkdir -p "$ROOT/node_modules/pkg"
  touch -t 202001010000 "$ROOT/node_modules"
  G -C "$ROOT" worktree add -q -b feat/me "$ROOT/.claude/worktrees/wt-me"
  WT="$ROOT/.claude/worktrees/wt-me"
  ln -s "$ROOT/node_modules" "$WT/node_modules"
  LD="$ROOT/_bmad/handoff/cmux"; mkdir -p "$LD"
  printf 'BF_SLUG=me\nBF_WORKTREE=%s\nBF_STATUS=implementing\n' "$WT" > "$LD/me.env"
  printf '%s\n' "$ROOT" > "$TMP/home/.local/state/cmux-orchestrator/roots"
}

lib() { # cwd script...
  local cwd=$1; shift
  (cd "$cwd" && env -i HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$TMP" \
    bash -c '. "$0"; '"$*" "$LIB")
}
snap() { lib "$ROOT" 'bf_shared_snapshot me "'"$WT"'" "'"$ROOT"'"'; }
drift() { lib "$ROOT" 'bf_shared_drift "'"$LD"'/me.shared" me'; }

pass=0 fail=0 count=0
check() { # name out assertions...
  local name=$1 out=$2 ok=1; shift 2
  count=$((count + 1))
  while [ $# -gt 0 ]; do
    case "$1" in
      empty) [ -z "$out" ] || ok=0;;
      has:*) printf '%s' "$out" | grep -qF -- "${1#has:}" || ok=0;;
      not:*) printf '%s' "$out" | grep -qF -- "${1#not:}" && ok=0;;
      lines=*) [ "$(printf '%s' "$out" | grep -c .)" = "${1#lines=}" ] || ok=0;;
    esac
    shift
  done
  if [ "$ok" = 1 ]; then pass=$((pass + 1)); echo "ok   $name"
  else fail=$((fail + 1)); echo "FAIL $name: [$out]"; fi
}
run() { set +e; out=$("$@" 2>&1); set -e; }

fresh; run snap; echo stray > "$WT/inside-wt.txt"; run drift
check "clean: nothing written to the primary -> no line" "$out" empty

fresh; run snap
echo '/secret.local' >> "$(git -C "$ROOT" rev-parse --absolute-git-dir)/info/exclude"
run drift
check "exclude append -> info/exclude +<line>" "$out" "has:shared-state: $ROOT: info/exclude +/secret.local" lines=1

fresh; run snap; echo x > "$ROOT/x.txt"; run drift
check "untracked in primary -> status +?? x.txt" "$out" "has:shared-state: $ROOT: status +?? x.txt" lines=1

fresh; run snap; echo y > "$ROOT/a.txt"; run drift
check "modified in primary -> status + M a.txt" "$out" "has:status + M a.txt"

fresh; run snap; mkdir -p "$ROOT/_bmad/handoff/cmux/archive/x" "$ROOT/.claude/worktrees/junk"; : > "$ROOT/.claude/worktrees/junk/f"; run drift
check "ledger dir and worktrees dir are not drift" "$out" empty

fresh; run snap
echo b > "$CLONE/b.txt"; G -C "$CLONE" add b.txt; G -C "$CLONE" commit -q -m b; git -C "$CLONE" push -q origin main 2>/dev/null
git -C "$ROOT" pull -q --ff-only 2>/dev/null
run drift
check "fast-forward of the primary -> no line" "$out" empty

fresh; run snap
echo a2 > "$CLONE/a.txt"; G -C "$CLONE" commit -q -am a2; git -C "$CLONE" push -q origin main 2>/dev/null
git -C "$ROOT" pull -q --ff-only 2>/dev/null
echo local >> "$ROOT/a.txt"; echo z > "$ROOT/z.txt"
run drift
check "status change on a path the fast-forward touched -> not attributable (fast-forward)" "$out" \
  "has:not attributable (fast-forward): $ROOT: status + M a.txt" "has:shared-state: $ROOT: status +?? z.txt" lines=1

fresh; run snap
G -C "$ROOT" worktree add -q -b feat/other "$ROOT/.claude/worktrees/wt-other"
printf 'BF_SLUG=other\nBF_WORKTREE=%s\n' "$ROOT/.claude/worktrees/wt-other" > "$LD/other.env"
echo o > "$ROOT/.claude/worktrees/wt-other/shared.txt"; echo o > "$ROOT/shared.txt"
echo '/apps/caio-web/api/node_modules' >> "$(git -C "$ROOT" rev-parse --absolute-git-dir)/info/exclude"
run drift
check "other live builder: same path and shared exclude -> not attributable (other)" "$out" \
  "has:not attributable (other): $ROOT: info/exclude +/apps/caio-web/api/node_modules, status +?? shared.txt" "not:shared-state: $ROOT:" lines=1

fresh; run snap
printf 'BF_SLUG=gone\nBF_WORKTREE=%s\n' "$ROOT/.claude/worktrees/wt-gone" > "$LD/gone.env"
echo o > "$ROOT/shared.txt"
run drift
check "a ledger whose worktree is gone does not excuse a path" "$out" "has:shared-state: $ROOT: status +?? shared.txt" "not:not attributable"

fresh; OLD=$(stat -f %m "$ROOT/node_modules"); run snap; mkdir "$ROOT/node_modules/newpkg"; run drift
check "node_modules target mtime moved -> node_modules <target> mtime a->b" "$out" \
  "has:shared-state: $ROOT: node_modules $ROOT/node_modules mtime $OLD->" lines=1

fresh
mkdir -p "$TMP/brain$N"; git init -q -b main "$TMP/brain$N"; G -C "$TMP/brain$N" commit -q --allow-empty -m init
BRAIN="$TMP/brain$N"
run lib "$ROOT" 'bf_shared_snapshot me "'"$WT"'" "'"$ROOT"'" "'"$BRAIN"'"'
echo w > "$BRAIN/written-by-builder.md"
run drift
check "untracked file in an --add-dir primary -> listed under that root" "$out" \
  "has:shared-state: $BRAIN: status +?? written-by-builder.md" lines=1

fresh; run snap; echo y > "$ROOT/a.txt"; G -C "$ROOT" commit -q -am local; run drift
check "a commit made in the primary itself is a fast-forward too -> no line" "$out" empty

fresh; run snap; G -C "$ROOT" checkout -q --orphan alt; G -C "$ROOT" commit -q -m alt
run drift
check "HEAD moved to a non-descendant -> reported" "$out" "has:(not a fast-forward)"

fresh; mkdir -p "$TMP/elsewhere$N/node_modules" "$WT/sub"; ln -s "$TMP/elsewhere$N/node_modules" "$WT/sub/node_modules"; touch -t 202001010000 "$TMP/elsewhere$N/node_modules"
run snap; mkdir "$TMP/elsewhere$N/node_modules/x"; run drift
check "a node_modules link pointing outside every primary is not tracked" "$out" empty

fresh; echo wip >> "$ROOT/a.txt"; run snap; echo builder-overwrote >> "$ROOT/a.txt"; run drift
check "a file already dirty at spawn, rewritten after -> status ~ M a.txt" "$out" "has:shared-state: $ROOT: status ~ M a.txt" lines=1

fresh; run snap; mkdir -p "$ROOT/_bmad-output/implementation-artifacts" "$LD/archive/me"
echo s > "$ROOT/_bmad-output/implementation-artifacts/spec-me.md"; run drift
check "own spec in the primary, own archive dir present -> still attributable" "$out" \
  "has:shared-state: $ROOT: status +?? _bmad-output/implementation-artifacts/spec-me.md" "not:not attributable"

fresh; run snap; mkdir -p "$ROOT/_bmad-output/implementation-artifacts" "$LD/archive/m"
echo s > "$ROOT/_bmad-output/implementation-artifacts/spec-me-2.md"; run drift
check "an archived slug that is a prefix does not excuse another spec" "$out" "not:not attributable"

fresh; run snap; mkdir -p "$ROOT/_bmad-output/implementation-artifacts" "$LD/archive/done-1"
echo s > "$ROOT/_bmad-output/implementation-artifacts/spec-done-1.md"; cp "$ROOT/_bmad-output/implementation-artifacts/spec-done-1.md" "$LD/archive/done-1/"
run drift
check "a spec the collector harvested for another builder -> not attributable (collector)" "$out" \
  "has:not attributable (collector): $ROOT: status +?? _bmad-output/implementation-artifacts/spec-done-1.md" lines=1

fresh; run snap
Y="$TMP/y$N"; git init -q -b main "$Y"; G -C "$Y" commit -q --allow-empty -m init; G -C "$Y" worktree add -q -b feat/b "$Y/.claude/worktrees/wt-b"
mkdir -p "$Y/_bmad/handoff/cmux"; printf 'BF_SLUG=b\nBF_WORKTREE=%s\n' "$Y/.claude/worktrees/wt-b" > "$Y/_bmad/handoff/cmux/b.env"
printf '%s\n%s\n' "$ROOT" "$Y" > "$TMP/home/.local/state/cmux-orchestrator/roots"
echo o > "$Y/.claude/worktrees/wt-b/same.txt"; echo o > "$ROOT/same.txt"
run drift
check "a builder in an unrelated repo with the same path does not excuse it" "$out" "has:shared-state: $ROOT: status +?? same.txt" "not:not attributable"

fresh; run lib "$ROOT" 'bf_shared_drift "'"$LD"'/me.shared" me'
check "no snapshot -> drift prints nothing" "$out" empty

echo "$pass passed, $fail failed, $count cases"
[ "$fail" -eq 0 ] && [ "$pass" -eq "$count" ]
