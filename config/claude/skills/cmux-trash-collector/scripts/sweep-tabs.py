#!/usr/bin/env python3
"""sweep-tabs.py -- close cmux tabs stranded inside a builder worktree, and nothing else.

  sweep-tabs.py --dir <worktree> [--dry-run]   tabs working inside this worktree
                                               (collect.sh runs this before removing it)
  sweep-tabs.py --deleted [--dry-run]          tabs stuck in a worktree under
                                               <primary>/.claude/worktrees/ that no longer
                                               exists -- trash left by collections that
                                               predate this sweep

WHY: collect.sh closed the builder's own tab and nothing else, so any other tab opened in the
worktree (an interactive `codex`, a shell) outlived it with its cwd deleted -- on 2026-09-24 a
codex tab in wt-3877 answered "failed to reload config: No such file or directory" 26s after
the collector removed its directory.

HOW A TAB IS IDENTIFIED -- by processes, never by title. Titles are set by whatever runs in
the tab and drift (that same tab read "Run tests | wt-3877..." and minutes later
"Run tests | BabaFlow"). `lsof -d cwd` lists every process whose cwd is inside the target,
and it still reports the path after the directory is deleted. Their ttys are mapped to tabs
through `cmux tree --json`, which reports each terminal's tty.

WHAT MAY BE CLOSED -- a tab is closed only if ALL of these hold, else it is reported and left:
  * cmux maps its tty to a tab, and that tab is not the caller's, the orchestrator's
    (BF_ORCH_SURFACE) or the builder's (BF_BUILDER_SURFACE -- collect.sh closes that one
    itself, after typing /exit);
  * no process on its tty is a Claude session: those are real sessions, whoever opened them;
  * every process on its tty is disposable -- a shell, login, sleep, codex, or a descendant
    of codex (its tool runs) -- and any codex on it works inside the target. Anything else
    (an editor, `top`, a dev server) means a human is using it: reported, left open.
A codex conversation survives its tab: `codex resume` reopens it.
"""
import argparse, json, os, subprocess, sys

SHELLS = {"zsh", "bash", "sh", "fish", "dash", "login"}


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def base(comm):
    # ps shows a process that is exiting as "(name)"; the shell-integration sleep does it
    # every second, so an unwrapped "(sleep)" would read as a foreign program.
    return os.path.basename(comm.strip().strip("()")).lstrip("-")


def primary_root():
    common = run("git", "rev-parse", "--git-common-dir").strip()
    if not common:
        sys.exit("ERROR: not inside a git repo (needed to locate .claude/worktrees)")
    return os.path.dirname(os.path.realpath(common))


def cwd_table():
    """pid -> cwd for every process of this user (one lsof call, ~0.25s)."""
    out, pid, table = run("lsof", "-a", "-u", str(os.getuid()), "-d", "cwd", "-Fpn"), None, {}
    for line in out.splitlines():
        if line.startswith("p"):
            pid = int(line[1:])
        elif line.startswith("n") and pid is not None:
            table[pid] = line[1:]
    return table


def proc_table():
    """pid -> (ppid, tty, comm) for every process."""
    t = {}
    for line in run("ps", "-A", "-o", "pid=,ppid=,tty=,comm=").splitlines():
        parts = line.split(None, 3)
        if len(parts) == 4:
            t[int(parts[0])] = (int(parts[1]), parts[2], parts[3])
    return t


def tab_table():
    """tty -> (surface ref, workspace ref, title) for every cmux terminal, from cmux itself.
    cmux knows each terminal's tty authoritatively, so no tab is ever identified by its title
    or by scraping a process environment (a login shell does not expose one)."""
    t = {}
    try:
        tree = json.loads(run("cmux", "tree", "--all", "--json"))
    except Exception:
        return t
    for win in tree.get("windows", []):
        for ws in win.get("workspaces", []):
            for pane in ws.get("panes", []):
                for sf in pane.get("surfaces", []):
                    if sf.get("tty") and sf.get("type") == "terminal":
                        t[sf["tty"]] = (sf.get("ref"), ws.get("ref"), sf.get("title") or "")
    return t


def my_ref():
    try:
        return json.loads(run("cmux", "identify", "--json"))["caller"].get("surface_ref")
    except Exception:
        return None


def has_codex_ancestor(pid, procs):
    seen = set()
    while pid in procs and pid not in seen:
        seen.add(pid)
        pid = procs[pid][0]
        if pid in procs and base(procs[pid][2]) == "codex":
            return True
    return False


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--dir")
    g.add_argument("--deleted", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    if a.dir:
        target = os.path.realpath(a.dir).rstrip("/")
        # Only ever ONE builder worktree: a parent directory (the primary checkout, say) would
        # sweep every worktree nested under it and every shell sitting in the repo.
        wts = os.path.join(primary_root(), ".claude", "worktrees")
        if os.path.dirname(target) != wts:
            sys.exit(f"ERROR: --dir must be a worktree directly under {wts}/ (got {target})")
        def inside(p):
            return p == target or p.startswith(target + "/")
        label = target
    else:
        wts = os.path.join(primary_root(), ".claude", "worktrees") + "/"
        def inside(p):
            if not p.startswith(wts):
                return False
            top = wts + p[len(wts):].split("/", 1)[0]
            return not os.path.isdir(top)          # only worktrees that are GONE
        label = wts + "<deleted>"

    cwds, procs = cwd_table(), proc_table()
    hits = [pid for pid, c in cwds.items() if inside(c)]
    ttys = sorted({procs[p][1] for p in hits if p in procs and procs[p][1] not in ("??", "")})
    orphans = [p for p in hits if p in procs and procs[p][1] in ("??", "")]

    tabs = tab_table()
    protected = {r for r in (my_ref(), os.environ.get("BF_ORCH_SURFACE"), os.environ.get("BF_BUILDER_SURFACE")) if r}
    closed = left = 0
    for tty in ttys:
        on_tty = [p for p, (_, t, _) in procs.items() if t == tty]
        ref, wsref, _title = tabs.get(tty, (None, None, None))
        comms = sorted({base(procs[p][2]) for p in on_tty})
        why = None
        if not ref:
            why = "cmux has no tab on this terminal (not a cmux tab)"
        elif ref in protected:
            why = "it is the caller's, the orchestrator's or the builder's tab"
        elif "claude" in comms:
            why = "a Claude session is running in it -- a real session"
        else:
            for p in on_tty:
                c = base(procs[p][2])
                if c in SHELLS or c == "sleep":
                    # Shells and cmux's integration `sleep` may sit anywhere: that subshell
                    # keeps the directory the tab OPENED in, not where the user cd'ed to.
                    continue
                if c != "codex" and not has_codex_ancestor(p, procs):
                    why = f"it is running `{c}`"
                    break
                if c == "codex" and p in cwds and not inside(cwds[p]):
                    why = f"its codex works outside {label}: {cwds[p]}"
                    break
        where = f"{tty} {ref or '?'} [{', '.join(comms)}]"
        if why:
            left += 1
            print(f"LEFT   {where}: {why}")
            continue
        closed += 1
        if a.dry_run:
            print(f"WOULD CLOSE {where}")
        else:
            run("cmux", "close-surface", "--workspace", wsref, "--surface", ref)
            note = " (its codex conversation: `codex resume`)" if "codex" in comms else ""
            print(f"CLOSED {where}{note}")
    for p in orphans:
        print(f"LEFT   pid {p} `{base(procs[p][2])}` has no terminal but works in {cwds[p]} -- not a tab; inspect by hand")
    print(f"sweep {label}: {closed} {'to close' if a.dry_run else 'closed'}, {left} left, {len(orphans)} tty-less")


if __name__ == "__main__":
    main()
