#!/bin/bash
# send.sh <slug> <text> | send.sh <slug> --file <file>: submit a prompt to builder b-<slug> on the MBP.
# A file is copied to ~/builders/briefs/<slug>/msg-<time>.md and the builder is told to read it.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
slug=${1:?usage: send.sh <slug> <text>|--file <file>}; shift
[ $# -gt 0 ] || die "nothing to send"
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
if [ "$1" = --file ]; then
  f=${2:?--file needs a path}; [ -s "$f" ] || die "$f is empty or missing"
  name="msg-$(date +%Y%m%dT%H%M%S).md"
  push "$f" "builders/briefs/$slug/$name"
  printf 'Read ~/builders/briefs/%s/%s and act on it.\n' "$slug" "$name" > "$tmp"
else
  printf '%s\n' "$*" > "$tmp"
fi
push "$tmp" "builders/briefs/$slug/.prompt"
home=$(with_timeout 10 ssh -o ConnectTimeout=10 -o BatchMode=yes "$MBP_HOST" 'printf %s "$HOME"')
mbb 30 prompt "b-$slug" "$home/builders/briefs/$slug/.prompt"
