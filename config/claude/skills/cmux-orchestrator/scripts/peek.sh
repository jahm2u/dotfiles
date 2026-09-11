#!/usr/bin/env bash
# peek.sh <slug> [lines] — read the last N lines of the builder's terminal (default 40).
# Use it to see what the builder is doing right now; use the ledger log for history.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"
[ $# -ge 1 ] || bf_die "usage: peek.sh <slug> [lines]"
bf_load "$1"
bf_builder_alive || bf_die "builder $(bf_builder_where) is gone"
cmux read-screen $(bf_target) --lines "${2:-40}"
