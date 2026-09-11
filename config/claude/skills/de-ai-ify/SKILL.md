---
name: de-ai-ify
description: Rewrite or edit any asset (doc, email, slide, message, code comment) to strip AI-sounding language and make it sound like a real human wrote it. Trigger with "de-ai-ify", "make this sound less AI", "humanize this", "rewrite this naturally", or when output reads like generic LLM slop.
user_invocable: true
---

# De-AI-ify

Take the user's asset and rewrite it so it reads like a sharp, direct human wrote it. The goal is substance over style, clarity over polish.

## Core Principles

- **First principles only.** Start from what's actually true. Build up from evidence, not from what "sounds right."
- **Be direct.** Say the thing. No warm-up, no hedging, no filler.
- **Adapt to context.** A Slack message and an exec summary need different registers. Match the medium.
- **Verifiable facts over platitudes.** If you can't point to evidence, cut the claim.
- **Cite every source.** Every factual claim gets a citation. No exceptions.
- **Useful over polite.** When something is wrong, say so. Show what's better.

## Banned Patterns

Hard-banned. Find and kill on every pass:

- Emdashes (`--` or `—`) — rewrite the sentence instead
- "Great question" or any variant ("That's a really interesting point")
- "It's not about X, it's about Y" — just say what it's about
- "Here's the kicker" / "Here's the thing" / "Here's what's interesting"
- "Delve" / "dive into" / "unpack"
- "Leverage" / "utilize" (say "use")
- "Landscape" / "ecosystem" / "holistic"
- "Crucial" / "essential" / "vital" when you mean "important"
- "Robust" / "comprehensive" / "cutting-edge"
- "At the end of the day"
- "It's worth noting that" — if it's worth noting, just note it
- "In today's [anything]"
- "Navigate" / "foster" / "cultivate"
- Rhetorical questions used as transitions ("So what does this mean?")
- Starting paragraphs with "So,"
- Triple-adjective stacking ("powerful, flexible, and intuitive")
- Watery hedging ("arguably", "it could be said that", "in many ways")
- Fake enthusiasm ("exciting", "incredible", "game-changing", "transformative")

## Calibration

Match your edits to how much the input needs. If the text already reads naturally, make minimal changes. Don't rewrite for the sake of rewriting. A casual Slack message that has one emdash needs a light touch, not a full teardown. Reserve heavy rewrites for text that clearly reads like AI generated it.

## Rewrite Process

For every asset, run this internally (user sees only the final output):

### Pass 1: Strip
- Remove all banned phrases and patterns
- Cut filler sentences that add no information
- Remove unnecessary qualifiers and hedges

### Pass 2: Restructure
- Lead with the point, not the context
- One idea per paragraph
- Short sentences where possible. Vary length for rhythm.
- Use active voice. Name the actor.

### Pass 3: Humanize
- Add specific details where generalities existed
- Use concrete examples instead of abstract claims
- Write like you're explaining to a smart colleague, not performing for an audience
- Keep some imperfection. Real writing has personality.

### Pass 4: Self-Critique
- Rate the rewrite 1–10 on: directness, specificity, human feel, usefulness
- If any dimension scores below 7, fix it and re-rate
- Check: would a reader suspect AI wrote this? If yes, another pass.

## Output Format

Return only the rewritten asset. No preamble ("Here's the rewritten version:"), no summary of changes. Just the clean output.

If the user asks what changed, then explain the key edits.

## When Invoked Without an Asset

If the user runs `/de-ai-ify` without providing text, ask: "Paste the text you want me to rewrite." Nothing else.
