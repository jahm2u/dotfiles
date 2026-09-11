#!/usr/bin/env bash
# Record a builder in an org's babysit sidecar, so the work survives the session.
#
# WHY: an org chat spawns builders and then may be /clear'd, closed, or relaunched
# (relaunch-org-chats.sh closes the workspace outright). The builder keeps running --
# since builders became TABS it lives in the chat's own workspace and dies with it --
# but nothing recorded that it existed. The sidecar is the org's only durable memory
# (~/.claude/skills/babysit-chat/state/<ORG>.md, outside the repo), so the record
# belongs there, next to everything else a fresh session reads on boot.
#
# Usage:
#   builder-log.sh OH 3490-silent-packing-deferral spawned
#   builder-log.sh OH 3490-silent-packing-deferral "in review" --pr 3493 --tab surface:93
#   builder-log.sh OH 3490-silent-packing-deferral merged --pr 3493 --note "margin untouched"
#   builder-log.sh OH --list
#
# Upsert by slug: calling it again for the same slug updates that row in place rather
# than appending a second one, so it is safe to call on every status change.
set -euo pipefail

STATE_DIR="$HOME/.claude/skills/babysit-chat/state"
ORG="" SLUG="" STATUS="" PR="" TAB="" NOTE="" LIST=0

[ $# -ge 1 ] || { echo "usage: builder-log.sh <ORG> <slug> <status> [--pr N] [--tab surface:N] [--note text]" >&2; exit 2; }
ORG="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"; shift

while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST=1; shift;;
    --pr)   PR="${2:?--pr needs a value}"; shift 2;;
    --tab)  TAB="${2:?--tab needs a value}"; shift 2;;
    --note) NOTE="${2:?--note needs a value}"; shift 2;;
    -*)     echo "unknown option: $1" >&2; exit 2;;
    *)      if [ -z "$SLUG" ]; then SLUG=$1; else STATUS="${STATUS:+$STATUS }$1"; fi; shift;;
  esac
done

SIDECAR="$STATE_DIR/$ORG.md"
[ -f "$SIDECAR" ] || { echo "no sidecar at $SIDECAR" >&2; exit 1; }

if [ "$LIST" = 1 ]; then
  awk '/^## Builders/{f=1} f&&/^## /&&!/^## Builders/{exit} f{print}' "$SIDECAR"
  exit 0
fi

[ -n "$SLUG" ] && [ -n "$STATUS" ] || { echo "need <slug> and <status>" >&2; exit 2; }

SLUG="$SLUG" STATUS="$STATUS" PR="$PR" TAB="$TAB" NOTE="$NOTE" SIDECAR="$SIDECAR" python3 <<'PY'
import os, re, datetime, pathlib

p = pathlib.Path(os.environ['SIDECAR'])
slug, status = os.environ['SLUG'], os.environ['STATUS']
pr, tab, note = os.environ['PR'], os.environ['TAB'], os.environ['NOTE']
now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%MZ')

HEAD = "## Builders"
COLS = "| slug | status | PR | tab | updated | note |"
SEP  = "|---|---|---|---|---|---|"
BLURB = ("_Builders this org spawned. Written by `builder-log.sh` so the record outlives the\n"
         "session — a builder runs as a TAB in this chat's workspace and dies with it._\n")

text = p.read_text()

def cell(v): return (v or '').replace('|', '\\|').strip() or '-'

# Preserve whatever the row already knows when this call does not restate it: a
# status update that omits --pr must not blank a PR recorded earlier.
existing = {}
if HEAD in text:
    body = text.split(HEAD, 1)[1]
    for line in body.splitlines():
        if line.startswith('|') and not line.startswith(('|---', '| slug')):
            parts = [c.strip() for c in line.strip().strip('|').split('|')]
            if parts and parts[0] == slug and len(parts) >= 6:
                existing = {'pr': parts[2], 'tab': parts[3], 'note': parts[5]}
                break

def keep(new, old):
    return new if new else (old if old and old != '-' else '')

row = "| {} | {} | {} | {} | {} | {} |".format(
    cell(slug), cell(status),
    cell(keep(pr and ('#' + pr.lstrip('#')), existing.get('pr'))),
    cell(keep(tab, existing.get('tab'))),
    now,
    cell(keep(note, existing.get('note'))),
)

if HEAD not in text:
    text = text.rstrip('\n') + f"\n\n{HEAD}\n\n{BLURB}\n{COLS}\n{SEP}\n{row}\n"
    action = 'created section +'
else:
    lines = text.splitlines()
    out, replaced, in_sec = [], False, False
    for line in lines:
        if line.strip() == HEAD:
            in_sec = True
        elif in_sec and line.startswith('## '):
            if not replaced:
                # section ends before we found the slug -> append before the next heading
                while out and not out[-1].strip():
                    out.pop()
                out.append(row); out.append(''); replaced = True
            in_sec = False
        if in_sec and line.startswith('|') and not line.startswith(('|---', '| slug')):
            parts = [c.strip() for c in line.strip().strip('|').split('|')]
            if parts and parts[0] == slug:
                out.append(row); replaced = True; continue
        out.append(line)
    if not replaced:
        while out and not out[-1].strip():
            out.pop()
        out.append(row)
    text = '\n'.join(out).rstrip('\n') + '\n'
    action = 'updated'

p.write_text(text)
print(f"{action} {slug}: {status}" + (f" (PR #{pr.lstrip('#')})" if pr else ''))
PY
