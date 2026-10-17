#!/bin/bash
# Remove worktrees a human approved from scan.sh output. Usage: remove.sh <worktree-path> ...
# Refuses symlinks, dirs with uncommitted tracked changes, and dirs a process is running in.
# For a registered worktree: unwatch in watchman, git worktree remove, delete the local branch.
# For an orphan (not registered anywhere): rm -rf, after the same checks.

set -u
rc=0
for wt in "$@"; do
    wt=${wt%/}
    if [[ -L "$wt" ]]; then echo "REFUSE $wt: symlink (would delete through it)"; rc=1; continue; fi
    if [[ ! -d "$wt" ]]; then echo "SKIP   $wt: not a directory"; continue; fi
    real=$(cd "$wt" && pwd -P)
    if lsof -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | grep -qE "^${real}(/|$)"; then
        echo "REFUSE $wt: a process is running inside it"; rc=1; continue
    fi

    watchman watch-del "$real" >/dev/null 2>&1

    # A worktree has a .git FILE pointing at <primary>/.git/worktrees/<name>
    if [[ -f "$real/.git" ]] && common=$(git -C "$real" rev-parse --git-common-dir 2>/dev/null); then
        if git -C "$real" status --porcelain | grep -v '^??' | grep -q .; then
            echo "REFUSE $wt: uncommitted changes"; rc=1; continue
        fi
        primary=$(cd "$real" && cd "$common/.." && pwd -P)
        branch=$(git -C "$real" branch --show-current)
        # --force only clears untracked files (watchman cookies, build output); tracked changes were refused above
        if git -C "$primary" worktree remove --force "$real"; then
            [[ -n "$branch" ]] && git -C "$primary" branch -D "$branch" >/dev/null 2>&1
            echo "OK     $wt${branch:+ (branch $branch deleted)}"
        else
            echo "FAIL   $wt"; rc=1
        fi
        git -C "$primary" worktree prune
    else
        /bin/rm -rf "$real" && echo "OK     $wt (orphan dir removed)"
    fi
done
exit $rc
