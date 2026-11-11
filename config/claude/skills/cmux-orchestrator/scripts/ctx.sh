#!/usr/bin/env bash
# ctx.sh [--json] [slug ...]          context use of each builder, read from its transcript
# ctx.sh --path <dir> [--model M]     same, for any Claude session whose cwd was <dir>
#
# WHY THIS EXISTS
# ---------------
# The builder skill told builders to hand off "if context passes ~70%". It never fired:
# on 2026-11-11 an ajudaduda builder (support-inbox) was at 97% after five rounds and
# still taking new work. A builder deep in a task does not watch its own meter, so the
# limit has to be enforced from OUTSIDE, by the orchestrator, from a number it can read.
#
# The number: the last main-thread assistant turn in the session's transcript
# (~/.claude/projects/<cwd, every non-alphanumeric as ->/<session>.jsonl) carries `usage`; the
# context in use is input + cache_creation + cache_read tokens. Subagent turns
# (isSidechain) are skipped, they have their own window. Window = 1,000,000 when the
# ledger model has [1m] (or the usage already exceeds 200k), else 200,000;
# BF_CTX_WINDOW overrides.
#
# Output, one line per builder:  <slug> <pct> <tokens> <window> <transcript>
# pct is an integer; "?" when there is no transcript yet (a builder still starting).
set -uo pipefail
# lib.sh is only needed for ledger mode. --path mode stays self-contained, so mbp-builder can
# stream this file over ssh (`ssh mbp bash -s -- --path <dir> < ctx.sh`) with nothing installed there.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo .)
# shellcheck disable=SC1091
[ -f "$HERE/lib.sh" ] && . "$HERE/lib.sh"

JSON=0; PATH_ARG=""; MODEL_ARG=""; SLUGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json)  JSON=1; shift ;;
    --path)  PATH_ARG="$2"; shift 2 ;;
    --model) MODEL_ARG="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) SLUGS="$SLUGS $1"; shift ;;
  esac
done

measure() { # label cwd model
  local label="$1" cwd="$2" model="$3" proj
  proj="$HOME/.claude/projects/$(printf '%s' "$cwd" | sed 's#[^A-Za-z0-9]#-#g')"
  python3 - "$label" "$proj" "$model" "${BF_CTX_WINDOW:-}" "$JSON" <<'PY'
import glob, json, os, sys
label, proj, model, override, as_json = sys.argv[1:6]
files = sorted(glob.glob(os.path.join(proj, "*.jsonl")), key=os.path.getmtime)
def out(pct, tok, win, path):
    if as_json == "1":
        print(json.dumps({"slug": label, "pct": pct, "tokens": tok, "window": win, "transcript": path}))
    else:
        print(f"{label} {pct} {tok} {win} {path}")
if not files:
    out("?", 0, 0, "-"); sys.exit(0)
path = files[-1]
tok = None
with open(path, "rb") as f:
    f.seek(0, 2); size = f.tell(); f.seek(max(0, size - 4_000_000))
    lines = f.read().splitlines()
for raw in reversed(lines):
    try: e = json.loads(raw)
    except Exception: continue
    if e.get("type") != "assistant" or e.get("isSidechain"): continue
    u = (e.get("message") or {}).get("usage") or {}
    if not u: continue
    tok = sum(int(u.get(k) or 0) for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
    break
if tok is None:
    out("?", 0, 0, path); sys.exit(0)
win = int(override) if override else (1_000_000 if ("[1m]" in model or tok > 200_000) else 200_000)
out(round(100 * tok / win), tok, win, path)
PY
}

if [ -n "$PATH_ARG" ]; then
  measure "$(basename "$PATH_ARG")" "$PATH_ARG" "${MODEL_ARG:-}"
  exit 0
fi

LEDGER_DIR="$(bf_ledger_dir 2>/dev/null || echo "$(pwd)/_bmad/handoff/cmux")"
if [ -z "${SLUGS// /}" ]; then
  for f in "$LEDGER_DIR"/*.env; do [ -e "$f" ] && SLUGS="$SLUGS $(basename "$f" .env)"; done
fi
[ -n "${SLUGS// /}" ] || { echo "ctx.sh: no builders (no ledgers in $LEDGER_DIR)" >&2; exit 1; }
for slug in $SLUGS; do
  wt=$(sed -n "s/^BF_WORKTREE=//p" "$LEDGER_DIR/$slug.env" 2>/dev/null | head -1 | sed "s/^'//; s/'$//")
  model=$(sed -n "s/^BF_MODEL=//p" "$LEDGER_DIR/$slug.env" 2>/dev/null | head -1 | sed "s/^'//; s/'$//")
  [ -n "$wt" ] || { echo "$slug ? 0 0 no-worktree-in-ledger"; continue; }
  measure "$slug" "$wt" "${model:-opus[1m]}"
done
