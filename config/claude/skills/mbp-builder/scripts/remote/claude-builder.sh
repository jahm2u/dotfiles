#!/bin/bash
# Starts claude in a builders pane on the Claude pool. The MBP's interactive shell pins the Kimi pool
# (~/.config/claude-gateway/base is /kimi) through the cg wrapper; this sets the Claude-pool env for this
# process only and never edits the gateway base file.
set -euo pipefail
model="${1:-claude-opus-5-5}"
slug="${2:?usage: claude-builder.sh <model> <slug>}"
key=$(tr -d '[:space:]' < "$HOME/.config/claude-gateway/key")
unset CG_KIMI_PINNED CG_KIMI_NATURAL_MODEL CG_CLAUDE_PINNED CG_ACTIVE ANTHROPIC_AUTH_TOKEN || true
export ANTHROPIC_BASE_URL=https://claude.ipmedia.com.br
export ANTHROPIC_API_KEY="$key" CG_KEY="$key"
export ANTHROPIC_CUSTOM_HEADERS="x-api-key: $key"
export ANTHROPIC_MODEL="$model" CLAUDE_CODE_SUBAGENT_MODEL="$model"
export ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-5-5 ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-5-5
export ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-5-5 ANTHROPIC_DEFAULT_FABLE_MODEL=claude-fable-5-1
export IPM_WORKER_SLUG="$slug" MBP_BUILDER="$slug"
unset key
exec "$(command -v claude)" --dangerously-skip-permissions
