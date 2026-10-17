---
name: disk-cleanup
description: Diagnose a filling disk on this Mac and clean it up safely — dead git worktrees first (merged, abandoned, orphaned), then regenerable caches and Time Machine local snapshots. Use when the user says the disk is full or filling up, "clean up worktrees", "free some space", "disk-cleanup", or after the "Disk low" notification from the tm-snapshot-cleanup LaunchAgent.
---

# Disk cleanup

Worktrees hold work; caches and snapshots don't. So the scan never deletes, the user approves
every worktree removal, and only caches go without a per-item question.

## 1. Measure first

```bash
df -h /System/Volumes/Data
diskutil info /System/Volumes/Data | grep 'Container Free Space'
tmutil listlocalsnapshots / | grep -c TimeMachine
```

If `Container Free Space` is far above `df`'s free space, Time Machine local snapshots are
holding deleted files. That was 87 GB on 2026-10-17. Thin them before anything else, because
every later deletion also stays pinned until you do:

```bash
tmutil thinlocalsnapshots / 999999999999 4   # no sudo needed; tmutil keeps the newest few
```

Only do this when `tmutil latestbackup` is under a day old. If the backup drive has been away,
local snapshots are the only copy, so tell the user instead of thinning.

The hourly `com.user.tm-snapshot-cleanup` LaunchAgent normally does this. If snapshots pile up,
check it first: `launchctl list | grep tm-snapshot` and `tail ~/.config/sketchybar/logs/tm-cleanup.log`.

## 2. Triage worktrees

```bash
~/.claude/skills/disk-cleanup/scripts/scan.sh            # default roots: ~/repos ~/work
~/.claude/skills/disk-cleanup/scripts/scan.sh ~/elsewhere
```

It takes about a minute (`du` is slow on this disk). Output is one tab-separated row per
worktree with a verdict:

- **SAFE**: PR merged at exactly this HEAD (or HEAD is already in origin's default branch),
  nothing uncommitted, no process inside.
- **ASK**: recoverable, but a human decides: closed PR, no PR, untracked files, orphan dirs.
  "No PR and nothing ahead" is ASK on purpose. The baba-fleet liaison checkouts
  (`local/ex`, `local/mt`...) look exactly like that and are in use.
- **KEEP**: uncommitted changes, commits on no remote, an open PR, or a live process inside.
  Don't offer these for removal. Say why they stay.

Rows marked "cmux builder, use /cmux-trash-collector <slug>" belong to a cmux/herdr/Orca
builder. Hand those to `/cmux-trash-collector`, which also archives the spec and log.

Then the caches block, then disk totals.

## 3. Ask once, then remove

Show the SAFE and ASK rows grouped with sizes, plus the caches, in one `AskUserQuestion`
(multiSelect). Then:

```bash
~/.claude/skills/disk-cleanup/scripts/remove.sh <path> <path> ...
```

`remove.sh` refuses symlinks, tracked uncommitted changes and dirs a process runs in. It
unwatches the path in watchman, runs `git worktree remove`, deletes the local branch, and
prunes. Orphan dirs get `rm -rf` after the same checks. Never hand-roll `rm -rf` on a worktree:
`~/repos` was once a symlink to an external drive, and deleting through it lost unpushed repos.

Caches, when approved (all regenerate):

```bash
npm cache clean --force
uv cache clean
/bin/rm -rf ~/Library/Caches/CocoaPods ~/Library/Caches/ms-playwright ~/.cache/puppeteer \
  ~/Library/Developer/Xcode/DerivedData "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
```

Leave `~/.cache/chrome-devtools-mcp` (browser profile with logins), `~/.cache/sketchybar` and
`~/.cache/khal` (live state). Claude's `vm_bundles` re-downloads if Cowork is used again.
Ask before emptying the Trash.

## 4. Report

Free space before and after (`df`), what was removed, and what was kept and why. If
`df` barely moved, thin snapshots again (step 1): the deletions are pinned in them.

## Gotchas

- `ps` etime `05:47` is 5 minutes 47 seconds, not hours. Check it before calling a builder stale.
- A folder missing from `.claude/worktrees` while a builder runs may just be newer than your
  listing. Recheck before acting.
- Dev servers (next, vite) outlive their worktree. Kill them only when their cwd no longer exists.
