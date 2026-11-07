#!/bin/bash
# Starts claude in a builders pane on a Claude pool, set for this process only. The MBP's interactive shell
# pins another pool through the cg wrapper; this never edits ~/.config/claude-gateway/base (the live crews read it).
#   pool mp: IPMedia's pool, key ~/.config/claude-gateway/key (MP repos).
#   pool tp: the TP pool, key ~/.config/claude-gateway/tp-key (jahm2u / BabaFlow work; spec-660 says the fleet
#            belongs there). TP_POOL_URL overrides the address.
set -euo pipefail
model="${1:-claude-opus-5-5}"
slug="${2:?usage: claude-builder.sh <model> <slug> [mp|tp]}"
pool="${3:-mp}"
case "$pool" in
  mp) base=https://claude.ipmedia.com.br; keyfile="$HOME/.config/claude-gateway/key" ;;
  tp) base="${TP_POOL_URL:-http://100.127.163.81:3456}"; keyfile="$HOME/.config/claude-gateway/tp-key" ;;
  *) echo "claude-builder.sh: pool must be mp or tp" >&2; exit 2 ;;
esac
key=$(tr -d '[:space:]' < "$keyfile")
unset CG_KIMI_PINNED CG_KIMI_NATURAL_MODEL CG_CLAUDE_PINNED CG_ACTIVE ANTHROPIC_AUTH_TOKEN || true
export ANTHROPIC_BASE_URL="$base"
export ANTHROPIC_API_KEY="$key" CG_KEY="$key"
export ANTHROPIC_CUSTOM_HEADERS="x-api-key: $key"
export ANTHROPIC_MODEL="$model" CLAUDE_CODE_SUBAGENT_MODEL="$model"
export ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-5-5 ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-5-5
export ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-5-5 ANTHROPIC_DEFAULT_FABLE_MODEL=claude-fable-5-1
export IPM_WORKER_SLUG="$slug" MBP_BUILDER="$slug" MBP_BUILDER_POOL="$pool"
unset key
exec "$(command -v claude)" --dangerously-skip-permissions
