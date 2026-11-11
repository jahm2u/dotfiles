#!/bin/bash
# peek.sh <slug|agent|pane> [lines]: read the tail of a builder's pane on the MBP (read-only).
set -euo pipefail
. "$(dirname "$0")/lib.sh"
t=${1:?usage: peek.sh <slug> [lines]}; lines=${2:-40}
case "$t" in b-*|*:p*) ;; *) t="b-$t" ;; esac
mbb 30 read "$t" "$lines"
