---
name: progress-page
description: Build or update a visual progress page (one HTML file) for any project, from its plan (stories, epics, waves, story points), live GitHub state and the session's decisions. Use when the user asks for a "progress update", "visual status", "make me a page showing where we are", "update the progress page", or during /handoff when the project already has a progress page. Updates the same file in place, so the link and path stay stable.
---

# Progress page

One HTML page per project that shows where the work stands: overall %, stages and gates, per-epic and per-wave bars, what's left, what's waiting on the human, decisions since the last update, and what merged. A finished example lives outside this public repo, at `~/orca/workspaces/agile-biz-builder/babaflow/projects/2026-11-06-agent-hive-efficiency-audit/progress/strategist-progress.html`. Copy its structure and tokens, not its content. This repo is public: never copy project pages, business names or numbers into it.

## 1. Find or create the page

- Path: `<project>/progress/<slug>-progress.html`. If one exists, **update it in place**: never fork a second page.
- Sidecar: `<project>/progress/progress-data.json` holds the last snapshot (`{as_of, total_sp, done_sp, total_stories, done_stories, done_ids[]}`). Read it to get "since last update" deltas, and rewrite it at the end.
- No plan folder? Ask what counts as a unit of work (issues with a label, a checklist, milestones) before inventing numbers.

## 2. Gather facts (read-only)

Compute the numbers; don't eyeball them:
- **Plan:** story files (YAML `story_points`, `id`, wave/epic), `dependencies.json` waves, epic and feature indexes. In Phil's Business Builder that's `projects/<p>/planning/tickets/stories/*.md` and `planning/dependencies/dependencies.json`. Count with a one-off node or python script.
- **Done means merged.** For every story you mark done, check its PR with `gh pr view <n> --json state,mergedAt`. Partial (some PRs merged, the acceptance gate still open) counts as remaining, labelled "in review".
- **Gates:** each one is Met / Pending / Blocked / At-meeting, with the evidence number (x/y), never a bare %. An empty or unread check is Pending, not Met.
- **Human asks:** from the session, the handoff JSON `open_questions`, and any desk or issue lists.
- **Decisions since the last update:** from the session, or the project's decision log (for example `technical-architecture.md` "Decisions during build").

## 3. Page contract

- Sections, in order: headline (one sentence saying where things stand) → big % plus a bar split into "done before" and "since last update" → stage timeline (inline SVG, drawn to a date scale, with a "today" marker) → gate checklist → by epic → by wave → remaining | waiting on the human → decisions → merged table → caveats.
- Every PR or issue is a full URL, never a bare `#123`.
- State caveats plainly: what you counted as done and what you did not verify.
- Load the `artifact-design` skill before writing. Colour tokens on `:root` with dark-mode blocks, an explicit body background, a phone-width layout, the side gutter written with `max(16px, env(safe-area-inset-*))`, Google Fonts only, everything else inline.
- Keep the title stable across updates (for example "Strategist v0 Build").

## 4. Deliver

- Open it locally: `open <path>`.
- If the session has a claude.ai login, publish it with the Artifact tool, updating the same URL if it was published before. If not, say so and give the path.
- Rewrite `progress-data.json`.
- Reply with the headline number, what changed since the last update, and the human asks. Keep the page itself as the detail.

## From /handoff

At the handoff's progress step: if `<project>/progress/*-progress.html` exists, run this skill to refresh it before writing the continuation prompt, and mention the path in the handoff's "Paths".
