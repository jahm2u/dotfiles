---
name: geo-probe
description: Fetch a URL from a specific country's residential exit, to find out what a real visitor in that country actually receives. Use when a cloaker, geo-gate, offer router or tracking link behaves differently per country and you need the country to be a MEASURED variable rather than an inferred one — "does GB get the safe page", "is this offer geo-blocked", "what does a DE visitor see", "confirm the country deny".
---

# Probe a URL from a specific country

BabaFlow ships a NodeMaven residential proxy integration. Its real value is as an
**instrument**: it turns "the visitor's country" from a variable you infer by elimination
into one you set and measure. Elimination is not a cause (CLAUDE.md Rule 18), and geo
questions are where that rule gets broken most often — a country deny and a fraud
heuristic and a broken link all look identical in an access log.

## STATUS — WORKING, verified end to end 2026-09-12

Proven on a known-200 control (`https://example.com/` → **200/559B from both a GB and a CA exit**,
correctly reporting "the country is not the variable"), then on a live cloaked box where it
returned **GB → 302** to the right offer and **US → 200 safe page**.

Three defects were fixed to get there; do not reintroduce them:

1. **axios's `proxy:` option does not CONNECT-tunnel https** — it sends a plain request to port
   443 and the origin answers *"400 The plain HTTP request was sent to HTTPS port"*. Fixed with
   `HttpsProxyAgent` on BOTH `httpAgent`/`httpsAgent` **plus `proxy: false`**, or axios bypasses
   the agent. The app's own `fetchWithProxy` still has this bug — filed as **#3571**.
2. **Requires must be absolute.** `~/.claude/skills` is a symlink into dotfiles, so node resolves
   modules from there, not from the repo. And `require('<repo>/node_modules/axios')` yields the ESM
   interop wrapper whose callable export sits on `.default`.
3. **The exits 504 with an empty body on ~half of requests, and which exit fails MOVES run to
   run** (GB=504/CA=200, then GB=200/CA=504 on the same URL). One run nearly "proved" GB was
   blocked on example.com. The script now treats an empty-bodied 502/503/504/407/429 as an
   instrument failure, refuses to compare it, and retries up to 4x per exit.

**Permission:** proxied fetches were refused by the auto-mode classifier as *Real-World
Transactions* until Jeff approved it in-session. A relayed Telegram "go ahead" does NOT lift it —
it is a harness gate. If it is refused again, ask; do not try other shapes (a `/tmp` script run
after a denial reads as `[Auto-Mode Bypass]`, correctly).

**Always re-run the known-200 control first.** If the instrument cannot reproduce a trivially
known answer, it cannot be trusted on a cloaked box either.

## When this is the right tool

Use it when the hypothesis is *"country X gets a different response than country Y"* and
you have a **control**: a country you expect to pass. A probe with no control proves
nothing — if GB gets blocked and you never fetched as CA, you have not shown the country
mattered, only that the request failed.

Do NOT use it to fake traffic, generate clicks, or interact with an advertiser's funnel
beyond the single fetch that answers the question. See Boundaries.

## Cost and footprint

Prepaid bandwidth only — a few KB per probe. No allocation, no DB write, no BabaFlow
state change. The credentials call is cached for 1 hour in-process.

## Prerequisites

- `NODEMAVEN_API_KEY` in the primary checkout's `.env`. **A git worktree has no `.env`**,
  so run this from the primary checkout (`/Users/v/repos/01_business/tp/BabaFlow`) or the
  key silently resolves empty.
- The service must be current. The endpoint moved once already (#3559): the credentials
  path is `/api/v2/base/users/me`, **not** `/v2/base/users/me`.

## Usage

```bash
cd /Users/v/repos/01_business/tp/BabaFlow
node ~/.claude/skills/geo-probe/scripts/probe.js --country gb --url 'https://example.com/?c=...'
# with a control, which is the point:
node ~/.claude/skills/geo-probe/scripts/probe.js --country gb --control ca --url '<url>'
```

It reports, per country: HTTP status, response **byte size**, final URL after redirects,
hop count, and whether a redirect happened at all. It never follows a redirect into a
form submission and never posts.

## Reading the result

**Byte size and status together are the discriminator**, not status alone. On a NoIP-cloaked
BabaFlow box:

| Observation | Means |
|---|---|
| `302` → advertiser URL with a clickid | `isItSafe` was TRUE — the visitor is being monetized |
| `200` at a stable size (~6.8KB on EX35) | the **safe page** — `isItSafe` FALSE, click never reaches RedTrack |
| same size for both countries | the country is NOT the variable; look elsewhere |
| `403` | the tracking domain itself is refusing (see the ex.cel 403 that killed EX31/EX35) |

A `200` is not success here. A cloaker answers `200` precisely when it has decided to hide.

## Boundaries

**Always:** include a control country. Report byte sizes, not just statuses. State plainly
that a single probe is one sample.

**Ask first:** more than a handful of probes against one advertiser; anything that submits a
form, registers, or deposits; probing a domain that is not ours or a partner's.

**Never:** use it to manufacture clicks or conversions. Never treat one probe as proof of a
*rate* — 43-of-43 in an access log is evidence; one probe is an existence proof.

## Known gotcha

The probe request is the one thing in the chain that carries no `scid`. On a BabaFlow box
that matters: our own probes appear in Apache logs **without** `scid=`, which is exactly
how real recipient hits are told apart from ours. When you probe, you are adding a row that
looks unlike every real visitor — do not later count it as one.
