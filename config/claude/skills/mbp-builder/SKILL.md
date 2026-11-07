---
name: mbp-builder
description: Launch, talk to, watch and close Claude builder sessions on Jeff's MacBook Pro (ssh mbp) in the herdr session `builders`, each in its own worktree of a separate clone, reporting back to the orchestrator on whichever Mac mini launched them (Mini-2024 or the work mini) through tell-mini. Use when the user says "launch a builder on the mbp", "mbp builder", "run builders on the macbook", "use the mbp for builders", "start a herdr builder", or when the Mini's builder slots are full and the work's gates can run on the MBP (paid-traffic and other Python repos). Not for docs-ipm db-e2e work, which needs the Mini's Postgres on 4132.
---

# mbp-builder

Builders on the MBP run in herdr session `builders`. Each one gets its own worktree at `~/builders/wt/<slug>`, cut from
a separate clone `~/builders/<repo>`, and starts on the Claude pool. Answers to it come from this Mini; its reports come
back through `tell-mini`. The ipm `kitchen remote` path can't do this, because it probes Linux only (`aarch64`,
`/proc/meminfo`) and rejects macOS `arm64`.

## When to use

- The work's gates run on the MBP: paid-traffic (`jeffheartmp/hive-paid-traffic`), dev-crew, other Python repos.
- The Mini's builder slots are full, and the MBP has memory to spare.
- Not for docs-ipm db-e2e: every docs-ipm builder shares the Mini's Postgres on 4132 under
  `lockf /tmp/docs-ipm-db-e2e.lock`, so put docs-ipm builders on the Mini.

## Flow

All scripts live in `~/.claude/skills/mbp-builder/scripts/` and run on the Mini that orchestrates: either
Mini-2024 (the MBP's ssh alias `mini-2024`) or the work mini (`mini`). The orchestrator must run in an Orca terminal,
since reports are typed into its tab.

1. Write the brief to a file. It must be at least 100 bytes: Intent, Boundaries, Done, the ticket, and "supervised:
   send the design first".
2. Launch it:
   ```bash
   scripts/launch.sh --repo jeffheartmp/hive-paid-traffic --slug ai-1725-ability-gate \
     --branch mc-console-r1b-14-ability-gate --brief /path/brief.md --orchestrator discus-1f
   ```
   - Optional: `--model claude-opus-5-5`, `--report-term <Orca handle>` (defaults to `$ORCA_TERMINAL_HANDLE`),
     `--report-host <the MBP's ssh alias for this Mac>` (defaults from `hostname`: Mini-2024 → `mini-2024`,
     ws-Mac-mini → `mini`; `MBP_REPORT_HOST` overrides). Launch refuses before creating anything unless the MBP
     can ssh to that host and find `tell-mini` there,
     `--report-repo <tell-mini repo>` (defaults to the cwd's main checkout name), `--rules <file>` (defaults to
     `orchestrator/fixes/_rules.md` when it exists), `--min-free 20`, `--no-venv`.
   - What it does:
     - installs `~/builders/bin/{mbb,claude-builder.sh}` on the MBP;
     - refuses below 20% free memory (`memory_pressure -Q`);
     - starts the `builders` herdr server if it isn't running;
     - clones or fetches the repo, adds the worktree, and builds `.venv` with uv;
     - copies the brief, `_rules.md` and a generated `kickoff.md` to `~/builders/briefs/<slug>/`;
     - opens a workspace `🔨 <slug>`, starts claude through `claude-builder.sh`, answers a trust dialog, and names
       the agent `b-<slug>`;
     - sends the kickoff line and waits up to 90 s for a tool call.
   - Exit codes: 0 means it was seen working, 3 means it started but no tool call was seen (run `peek.sh`).
3. Talk to it: `scripts/send.sh <slug> "text"` or `scripts/send.sh <slug> --file answer.md`. A file is copied over
   first, so multi-line text never goes through a keystroke stream.
4. Watch it:
   - `scripts/peek.sh <slug> [lines]` reads the pane;
   - `scripts/ls.sh` lists every `b-*` agent with its status;
   - `herdr --remote mbp --session builders` attaches live.
5. Close it with `scripts/close.sh <slug>`. It refuses when the worktree is dirty, when commits aren't on
   `origin/<branch>`, or when the branch has no MERGED PR (checked with gh on the Mini). Otherwise it sends `/exit`,
   closes the workspace, and removes the worktree and the local branch. The ledger is kept as
   `~/builders/ledger/<slug>.closed-*.env`. `--force` skips the checks, and it is a person's call.

## The reporting channel

The builder writes its message to a file and runs:

```bash
ssh -o ConnectTimeout=10 <report-host> 'MINI_TERM=<handle> ~/.claude/skills/mbp-builder/scripts/tell-mini <repo> mbp:builders/b-<slug>' < file
```

`tell-mini` ships in this skill (it calls Orca's bundled CLI; `/usr/local/bin/orca` is broken on Mini-2024). The
work mini also keeps an older copy at `~/.local/bin/tell-mini`. The message lands in `~/.local/state/from-mbp/` on
the Mini and is typed into the pinned Orca tab as a `[mini-tell from mbp:builders/b-<slug>]` line, whose reply hint
is `send.sh <slug> --file reply.md`. Verified end to end from Mini-2024 on 2026-11-07 (smoke builder, report in ~30 s,
reply delivered, closed clean). The builder also appends each report to
`~/builders/briefs/<slug>/log.md`. If the orchestrator restarts in a new tab, the pinned handle is stale: send the
builder the new handle with `send.sh`. SendMessage and ListAgents can't see MBP builders.

## Landmines

- **Kimi by default.** On the MBP, `~/.config/claude-gateway/base` is `/kimi`, and an interactive shell's `cg`
  wrapper pins k3.1. `claude-builder.sh` exports the Claude-pool env for its own process only:
  `ANTHROPIC_BASE_URL=https://claude.ipmedia.com.br`, the key from `~/.config/claude-gateway/key`, every
  `ANTHROPIC_DEFAULT_*` and `CLAUDE_CODE_SUBAGENT_MODEL`. Then it runs `command claude`. Never edit the `base` file:
  the live crews read it.
- **gh-mp answers 401 over ssh**, because its token is in the keychain. The clone bootstraps from the live checkout's
  objects (read-only), then points `origin` at GitHub with `include.path ~/.gitconfig-mp` for credentials. If
  `gh pr create` fails on the MBP, the builder pushes and the Mini opens the PR.
- **Never `mkt-crew`, `dev-crew` or `hive-paid-traffic`** (the live herdr sessions): `mbb` refuses them. Never a
  worktree of the live checkout `~/repos/01_business/mp/<repo>`: seats work there with prompts off.
- **Memory.** The MBP runs both live hives. Launch refuses below 20% free; check `ls.sh` before adding a third
  builder.
- **Renaming.** An agent name is lost when claude restarts in the pane. Rename it again with
  `ssh mbp 'herdr --session builders agent rename <pane> b-<slug>'`.
- **zsh on the MBP.** Every argument goes through `printf %q` into `bash ~/builders/bin/mbb`, so nothing is
  word-split or globbed by the remote zsh.
