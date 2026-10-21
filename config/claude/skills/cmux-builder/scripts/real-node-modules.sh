#!/usr/bin/env bash
# real-node-modules.sh -- give a worktree real node_modules folders, cloned from the primary checkout.
#
#   real-node-modules.sh [worktree]      default: $BF_WORKTREE, else the current git toplevel
#
# spawn.sh symlinks node_modules into the worktree so tests run without an install. Bundlers that
# only see files inside the project (Metro/Expo, also Vite's watcher) cannot follow that link out:
# 2026-10-21, builder 660 sat 30 min on Metro's red "Unable to resolve module
# react-native-shared-group-preferences" because apps/duda-mobile/node_modules pointed into the
# primary. Run this before starting Metro/Expo in a worktree.
#
# Every node_modules the primary has (root and per app, not nested ones) that is a symlink or missing
# in the worktree becomes an APFS clone (`cp -c`): real folders, copy-on-write, so almost no extra
# disk, and an install in the worktree no longer rewrites the primary's tree. ~1 min for 127k files.
set -euo pipefail

WT="${1:-${BF_WORKTREE:-$(git rev-parse --show-toplevel)}}"
WT="$(cd "$WT" && pwd -P)"
ROOT="$(git -C "$WT" worktree list --porcelain | sed -n '1s/^worktree //p')"
[ -n "$ROOT" ] && [ "$ROOT" != "$WT" ] || { echo "$WT is not a linked worktree (primary: ${ROOT:-?})" >&2; exit 2; }

n=0
while IFS= read -r src; do
  rel="${src#"$ROOT"/}"
  dst="$WT/$rel"
  [ -d "$(dirname "$dst")" ] || continue          # the app does not exist on this branch
  if [ -L "$dst" ]; then
    rm "$dst"
  elif [ -e "$dst" ]; then
    continue                                      # already a real folder: leave it
  fi
  s=$(date +%s)
  cp -c -R "$src" "$dst.cloning" && mv "$dst.cloning" "$dst"
  echo "cloned $rel ($(( $(date +%s) - s ))s)"
  n=$((n + 1))
done < <(find "$ROOT" -maxdepth 4 -type d -name node_modules -not -path '*/node_modules/*' \
           -not -path '*/.claude/worktrees/*' -not -path '*/.git/*' 2>/dev/null | sort)

echo "real-node-modules: $n cloned in $WT"
[ $n = 0 ] || echo "restart Metro/Expo with --clear so it drops the cached failed lookups"
