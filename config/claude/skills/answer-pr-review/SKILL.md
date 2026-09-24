---
name: answer-pr-review
description: 'Handle inbound code-review comments on a pull request end to end: fetch every finding (inline threads AND the review body, including the "Prompt for all review comments with AI agents" block), triage them against an impact bar so only findings with real consequences get worked, verify those against the real code, apply the real ones, decline false-premise ones with file:line evidence, drop the nitpicks unanswered, then commit, push, reply in-thread, and wait out one review round. Use when the user says "get the review comments", "answer the PR comments", "handle the CodeRabbit feedback", "address the review", or after a bot review lands on a PR. Not for generating a review, and not for the post-hoc retro of what a review found. Differs from coderabbit-loop, which fixes every unresolved CodeRabbit finding in batches until the PR is clean: this skill rations work by impact and lets nitpicks die unanswered.'
user_invocable: true
---

# IPM Answer PR Review

Follow the instructions in workflow.md — read that file first.
