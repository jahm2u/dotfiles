#!/usr/bin/env bash
# tell.sh <slug> "<message>" — type a message into the builder's Claude prompt and submit it.
# Keep it to one line. For answers to quick-dev checkpoints send just the letter, e.g. tell.sh my-slug A
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"
[ $# -ge 2 ] || bf_die "usage: tell.sh <slug> <message>"
SLUG=$1; shift
bf_load "$SLUG"
[ -n "${BF_BUILDER_WS:-}" ] || bf_die "ledger has no builder workspace"
bf_builder_alive || bf_die "builder $(bf_builder_where) is gone"
MSG="[orchestrator] $*"
bf_say_to_builder "$MSG"
bf_logline "$SLUG" orchestrator "$*"
echo "sent to $(bf_builder_where): $MSG"
