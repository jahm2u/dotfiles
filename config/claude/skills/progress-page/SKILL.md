---
name: progress-page
description: Build or update a visual progress page (one HTML file) for any project, showing where it stands toward its goal: the true blocker on top, a percentage counted from named steps, the ordered next steps to 100%, each stage step by step, cycles from the project's tracker, and what waits on the human. Facts come from wherever the project keeps them (GitHub issues, milestones or projects, Linear cycles, plan files, a checklist). Use when the user asks for a "progress update", "visual status", "where are we overall", "make me a page showing where we are", "update the progress page", or during /handoff when the project already has a progress page. Updates the same file in place.
---

# Progress page

One HTML page per project that answers, in this order: what is holding us, how far along we are, what gets us to 100% and in which order, and what is happening right now. The reader has not followed the work.

The overview is rendered from a data file, so an update means rewriting JSON, not HTML:

```bash
P=~/.claude/skills/progress-page
python3 $P/build.py --data <project>/progress/progress-data.json --out <project>/progress/<slug>-progress.html
```

Then show it in the browser through the Chrome DevTools MCP, not with `open`: `mcp__chrome-devtools__list_pages`, and if a tab already holds `file://<abs path>`, `select_page` it and `navigate_page` to the same URL to reload it; otherwise `new_page` with `file://<abs path>`. Fall back to `open <path>` only when the MCP is not available, and say so.

The top of the overview has ONE overall bar (every counted step across all stages: done, being worked on, waiting); each stage card below carries its own bar. Do not bring back a bar split per stage at the top.

`build.py` also prints a plain-text (ASCII) version of the overview, from the same data, and saves it next to the page as `<slug>-progress.txt`. Bars are `[####......] 94% (46 of 49)`, steps are marked `[x]` done, `[~]` doing, `[w]` waiting, `[ ]` to do, `[-]` later, and long lists (in motion, landed) are cut with a "+N more on the page" line. `--no-ascii` turns it off.

`build.py` creates the page when it is missing, and on an existing page replaces only what sits between `<!-- ov:start -->` and `<!-- ov:end -->`, so anything written below the overview (tables, charts, decisions, caveats) survives. It refuses data with no stage, a stage with no counted step, or an unknown step state, and writes nothing: a bar over nothing would read 0% or 100% without having looked at anything.

This repo is public: never copy a project's page, names or numbers into the skill folder.

## 1. Decide what 100% means, with the human's words

Write the goal as one sentence the human would say ("the app live in both stores and families charged"). Then break the road into 2 to 5 **stages**, and each stage into **steps** a person could tick: an issue, a pull request merged, a store approval, a switch someone flips. The percentage is steps done over steps counted, every step weighing the same, so:

- A step is done only when it is verifiably done (merged, closed, published, read on the live system). "In review" is `doing`. A step that waits on a party outside the team (a store review, a vendor, legal) is `waiting`, with that party as `owner`.
- Mark as `later` what is explicitly out of the goal; it is listed and not counted.
- If a group of issues has not been broken down yet, count it as one step and say so in its note. Do not invent a split.
- Say in `counts_note` what the percentage counts and what it does not (for example, that it is not the share of all issues closed).

No plan at all? Ask what the goal is and what counts as a step before inventing numbers.

## 2. Gather facts from the project's own sources (read-only)

Look for `<project>/progress/sources.md`. If it exists, follow it. If not, find out which of these the project uses, write the answer to that file so the next update does not have to ask, and gather:

| Source | What to read | How |
| --- | --- | --- |
| GitHub issues | steps = issues by label, by parent issue checklist, or by a phrase in title or body | `gh issue list --json number,title,state,labels,closedAt`, `gh issue view <n> --json body` |
| GitHub milestones or Projects | stages or cycles = milestones or iterations, with open and closed counts | `gh api repos/<o>/<r>/milestones?state=all`, `gh project item-list` |
| Pull requests | done = merged; in motion = open with its check counts | `gh pr list --json number,title,state,mergedAt,statusCheckRollup` |
| Linear | cycles (name, dates, done and total), issues by state | the Linear MCP or API if the session has it; otherwise ask for an export |
| Plan files | stories with ids, points, waves or epics | a one-off script over the files; quote the count it read |
| A live system | a deploy, a store console, a dashboard | read it now, or say "not re-read" on the page |

Rules for every source:

- Compute, don't eyeball. Quote counts (x of y), and if a query returns zero rows, treat it as a wrong query until shown otherwise.
- Done means verified this run. A fact carried over from a handoff or an earlier page is written as carried over, with its time.
- **Cycles** (sprints, iterations, milestones with dates): when the tracker has them, fill `cycles` with the current and the next one: name, start, end, done, total, url, and name the tracker in `cycles.source`. No cycles in the tracker: leave `cycles` null. Never fabricate a cycle from dates.
- Human asks come from the session, the handoff's open questions and the tracker's "needs human" marks. One line each, the exact action.

## 3. Write `progress-data.json`

```json
{
  "title": "Project · where we are",
  "as_of": "15 Nov 2026, 11:05 UTC",
  "human_name": "Ana",
  "headline": "One sentence: where things stand.",
  "summary": "One or two sentences of supporting fact. Optional.",
  "blocker": { "title": "What holds us: ...", "text": "Who must do what.", "owner": "Apple" },
  "goal": "the sentence from step 1",
  "counts_note": "What the percentage counts and what it does not.",
  "next_steps": [ { "text": "The next thing, in order", "owner": "builders", "url": "https://...", "note": "why, or what it waits on" } ],
  "stages": [
    { "label": "Stage 1 · we are here", "status": "current", "name": "Short stage name", "holds": "What holds this stage.",
      "items": [ { "text": "A step", "state": "done", "url": "https://...", "owner": "Ana", "note": "evidence, with its time" } ] }
  ],
  "cycles": { "source": "Linear", "items": [ { "name": "Cycle 12", "start": "10 Nov", "end": "23 Nov", "done": 9, "total": 21, "url": "https://..." } ] },
  "waiting_on_human": [ { "text": "The exact action", "state": "todo" } ],
  "in_motion": [ { "text": "What is being worked on", "state": "doing", "url": "https://...", "note": "3 of 8 checks passed" } ],
  "landed": [ { "text": "What landed since the last update", "state": "done", "url": "https://..." } ]
}
```

- Step `state` is one of `done`, `doing`, `waiting`, `todo`, `later`. Stage `status` is `current` for the stage being worked, anything else otherwise.
- `blocker` is the one true thing holding the goal, or `null` when nothing is. It sits on top of the page; do not fill it with a routine status.
- `next_steps` is the ordered path to 100%, 5 to 10 lines, each with an owner. It must cover every stage: a reader should be able to tell what remains after the current stage.
- Every pull request or issue is a full URL; the link text is a plain title, never a bare number.
- Plain words. No internal labels, no shas as the only description of something, no real customer or family names.

## 4. Build, look, deliver

1. Run `build.py`. Read the line it prints (steps done, total, stages) and check it against what you counted.
2. Open the page and **look at it** at desktop width and at phone width, light and dark, before telling anyone it is ready. Fix what is cramped or wrong in the data, not by hand in the HTML between the markers.
3. Below the overview the page is free-form. Keep there what a curious reader may want: the count of all issues, charts over time, gates with their evidence, decisions, the merged list, and what was and was not verified. Left-aligned text, no emoji in headings, readable at phone width. **Every section there is expanded by default.** If the record is long enough to want `<details>`, write `<details open>` and do not describe the sections as folded: the human asked not to have to open each line. `build.py` adds `open` to any `<details>` that lacks it on every run and prints how many it changed.
4. Deliver the way the project does: show it in the browser through the Chrome DevTools MCP (reload the tab that already has it, else open a new one; `open <path>` only without the MCP); commit it where the project tracks it; publish it with the Artifact tool when the session has a claude.ai login and the human wants a link. Do not make the human wait on a pull request to see the page.
5. Reply with the ASCII version in a code block (copy it from `<slug>-progress.txt`, or the part from the top through the stages when it is long), then the headline, the percentage with its counts, what changed since the last update, and the human asks. The reader may be in a terminal or on a phone, where the HTML is one more tap away.

## Existing pages

A page made before this layout has no markers. Put `<!-- ov:start -->` and `<!-- ov:end -->` around its old first-screen section (keep the detail below), then run `build.py`. Keep a copy of the old file until the human has seen the new one.

## From /handoff

At the handoff's progress step: if `<project>/progress/*-progress.html` exists, refresh `progress-data.json` from live facts, run `build.py`, and name the path in the handoff's "Paths".
