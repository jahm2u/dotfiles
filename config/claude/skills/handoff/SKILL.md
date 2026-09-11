---
name: handoff
description: 'Smart session handoff / smart compact. First reads the previous handoff and runs a short interactive interview (max 2 rounds x 3 questions, via AskUserQuestion) to settle pending decisions or next steps, then curates a structured checkpoint of the CURRENT session (mission, problems+root-causes, decisions+rationale, current state, next steps, landmines) to _bmad/handoff/ so a FRESH session (after /clear) is auto-re-seeded by the SessionStart hook, and distil learnings into an append-only learnings log. Read-only on production code; never runs /clear. Use when the user says "handoff", "checkpoint this session", "smart compact", "context is getting full", or when a Stop-hook reminder shows the context window is large (~70%+).'
---

# Handoff

Follow the instructions in `~/.claude/skills/handoff/workflow.md` — read that file first.
