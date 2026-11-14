#!/bin/bash
# ctx.sh [slug ...]: context use of each b-* builder on the MBP, read from its transcript.
# Prints: <slug> <pct> <tokens> <window> <transcript>. MBP builders run claude-opus-5-5
# (remote/claude-builder.sh), a 1M window. ctx.sh divides by 80% of it so its percent matches
# Claude Code's own meter (measured 2026-11-11: 780,019 tokens = 97%, 88,386 = 11.0%).
#
# The 60% rotation rule (SKILL.md "Context rotation") is enforced from here: on 2026-11-11
# b-1235-support-inbox reached 97% after five rounds and was still being handed questions.
# The measuring code is cmux-orchestrator's ctx.sh, streamed over ssh so nothing needs
# installing on the MBP.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
CTX="$HOME/.claude/skills/cmux-orchestrator/scripts/ctx.sh"
[ -f "$CTX" ] || die "missing $CTX"
want=" $* "
mbb 30 list | while IFS=$'\t' read -r agent _status _pane cwd; do
  case "$agent" in b-*) ;; *) continue ;; esac
  slug=${agent#b-}
  [ "$want" = "  " ] || case "$want" in *" $slug "*) ;; *) continue ;; esac
  out=$(with_timeout 20 ssh -o ConnectTimeout=10 -o BatchMode=yes "$MBP_HOST" "bash -s -- --path '$cwd' --model claude-opus-5-5" <"$CTX" 2>/dev/null || true)
  [ -n "$out" ] || { echo "$slug ? 0 0 unreadable"; continue; }
  echo "$slug ${out#* }"
done
