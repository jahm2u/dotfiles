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

Only do this when the last backup is under a day old. `tmutil latestbackup` needs Full Disk
Access, which Claude's shell lacks; read `ReferenceLocalSnapshotDate` (UTC) from
`defaults read /Library/Preferences/com.apple.TimeMachine.plist` instead, and check the backup
volume is mounted (`tmutil destinationinfo`). If the backup drive has been away, local
snapshots are the only copy, so tell the user instead of thinning.

The gap between the two numbers understates what the snapshots hold. On 2026-11-12 it was 7 GB
before cleanup; 60 GB of deletions then left `df` unmoved until a thin freed all of it at once.
So also thin after deleting, not only when the gap looks large.

The hourly `com.user.tm-snapshot-cleanup` LaunchAgent normally does this. If snapshots pile up,
check it first: `launchctl print gui/$(id -u)/com.user.tm-snapshot-cleanup | grep -E 'runs|interval'`
(`runs = 0` or no `run interval` means it never fires) and `tail ~/.config/sketchybar/logs/tm-cleanup.log`.
A loaded agent can still be the old plist: on 2026-11-12 this Mac had run the WatchPaths version
for a month. `scripts/install.sh` now reinstalls any agent whose plist differs from the repo.

## 2. Triage worktrees

```bash
~/.claude/skills/disk-cleanup/scripts/scan.sh            # default roots: ~/repos ~/work ~/orca/workspaces
~/.claude/skills/disk-cleanup/scripts/scan.sh ~/elsewhere
```

It takes a few minutes (`du` is slow on this disk). It lists every worktree of every checkout
under the roots, wherever the worktree lives (`~/.cache/discus-gate`, `~/orca/workspaces`,
`/private/tmp`...). Roots may be symlinks (`~/repos` points at the external `/Volumes/Workspace`).
**Exit 2 with "no git checkout found" means the scan saw nothing**: an unmounted drive or a
wrong root, never a clean disk. Output is one tab-separated row per worktree with a verdict:

- **SAFE**: PR merged at exactly this HEAD (or HEAD is already in origin's default branch),
  nothing uncommitted, no process inside.
- **ASK**: recoverable, but a human decides: closed PR, no PR, untracked files, orphan dirs.
  "No PR and nothing ahead" is ASK on purpose. The baba-fleet liaison checkouts
  (`local/ex`, `local/mt`...) look exactly like that and are in use.
- **KEEP**: uncommitted changes, commits on no remote, an open PR, or a live process inside.
  Don't offer these for removal. Say why they stay.

Changes confined to an installed BMAD module (`_bmad/<m>/` with a tracked
`.bmad-modules-version`) are a module refresh, not work: the row says "N BMAD module files
refreshed (not work)" and they do not count toward KEEP. `remove.sh` applies the same rule.

Rows marked "cmux builder, use /cmux-trash-collector <slug>" belong to a cmux/herdr/Orca
builder. Hand those to `/cmux-trash-collector`, which also archives the spec and log. If the
collector says "no ledger for slug", the builder is long gone: the worktree is an ordinary
SAFE row, so offer it to `remove.sh` instead.

Check where a worktree lives before promising space: anything under `/Volumes/Workspace`
frees the external drive, not the internal disk.

Then the caches block, the BIG DEV DATA block, then disk totals. BIG DEV DATA lists each
item with its size and what clearing it costs: iOS simulators (each device over 500 MB with
its `simctl erase` line), Android AVDs and system images, Gradle, Xcode archives, `~/Movies`
review captures, per-builder caches (`~/.cache/{ai,console,uxs}-*`), discus-gate, Orca
workspaces and OrbStack. **Store/marketing imagery** (`widget-art`, `*store*`, `*marketing*`
under `~/Movies`) is chosen artwork: it gets its own line and its own question, never bundled
with the captures.

## 3. Ask once, then remove

Show the SAFE and ASK rows grouped with sizes, plus the caches and BIG DEV DATA, in one
`AskUserQuestion` (multiSelect). Never offer the baba-fleet liaison checkouts (`local/ex`, `mt`,
`oh`, `pd`, `tp`) or anything KEEP. Before clearing simulators or emulators, check none is running:
`xcrun simctl list devices booted` and `pgrep -fl qemu-system`. Then:

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

Per-builder caches: `find ~/.cache -maxdepth 1 -type d \( -name 'ai-*' -o -name 'console-*' \) -mtime +3`,
skipping any that holds a `.git` (a worktree: that one goes through `remove.sh`).

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
- Daily `com.user.mac-autoclean` (04:15) prunes uv/npm, Docker images, old builder transcripts
  and dev build caches by itself; its log is `~/.local/share/mac-autoclean/autoclean.log`.
  `DRY_RUN=1 bash ~/.config/sketchybar/helpers/mac-autoclean.sh` shows what it would remove.
