#!/bin/bash
# Shared by the Mini-side mbp-builder scripts. Sourced, never run.
MBP_HOST="${MBP_HOST:-mbp}"
MBB_SESSION="${MBB_SESSION:-builders}"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { echo "mbp-builder: $*" >&2; exit 1; }

# default_report_host: the MBP's ssh alias for the Mac running this script (MBP_REPORT_HOST overrides).
default_report_host() {
  if [ -n "${MBP_REPORT_HOST:-}" ]; then echo "$MBP_REPORT_HOST"; return; fi
  case "$(hostname -s)" in
    Mini-2024) echo mini-2024 ;;
    ws-Mac-mini) echo mini ;;
    *) hostname -s | tr '[:upper:]' '[:lower:]' ;;
  esac
}

# with_timeout SECS cmd...: the Mini may lack coreutils timeout; then run without one.
with_timeout() {
  local secs=$1; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; else "$@"; fi
}

# mbb SECS sub args...: run ~/builders/bin/mbb on the MBP with every argument shell-quoted, so the MBP's
# zsh never word-splits or globs them.
mbb() {
  local secs=$1; shift
  local q=""
  for a in "$@"; do q+=" $(printf '%q' "$a")"; done
  with_timeout "$secs" ssh -o ConnectTimeout=10 -o BatchMode=yes "$MBP_HOST" \
    "MBB_SESSION=$(printf '%q' "$MBB_SESSION") bash \$HOME/builders/bin/mbb$q"
}

# push LOCAL HOME_RELATIVE_PATH: copy a file to the MBP over stdin (ssh lands in $HOME).
push() {
  local src=$1 dst=$2
  with_timeout 30 ssh -o ConnectTimeout=10 -o BatchMode=yes "$MBP_HOST" \
    "mkdir -p $(printf '%q' "$(dirname "$dst")") && cat > $(printf '%q' "$dst")" < "$src"
}

install_remote() {
  with_timeout 20 ssh -o ConnectTimeout=10 -o BatchMode=yes "$MBP_HOST" 'mkdir -p "$HOME/builders/bin"' \
    || die "cannot reach $MBP_HOST over ssh"
  # A per-launch suffix: two launches at once used to race on one mbb.tmp, and the second mv failed.
  local t="tmp.$(hostname -s).$$"
  push "$SKILL_DIR/scripts/remote/mbb" "builders/bin/mbb.$t"
  push "$SKILL_DIR/scripts/remote/claude-builder.sh" "builders/bin/claude-builder.sh.$t"
  with_timeout 20 ssh -o ConnectTimeout=10 -o BatchMode=yes "$MBP_HOST" \
    "cd \"\$HOME/builders/bin\" && chmod 755 mbb.$t claude-builder.sh.$t && mv -f mbb.$t mbb && mv -f claude-builder.sh.$t claude-builder.sh"
}
