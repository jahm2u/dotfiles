---
name: ux-video-review
description: Get Jeff's feedback on a UI change by video on Telegram. Record the changed flow at phone size with real taps (Chrome DevTools screencast), send the mp4 to Jeff on Telegram (AjudaDuda: the ajudaduda dev group) with a short pt-BR/English caption of what to look at, read his replies, and turn them into fixes before merge. Use whenever a PR changes what a user sees or how a screen moves (any UX change in ajudaduda's PWA or mobile, marketing, onboarding), when Jeff says "send me a video", "show me on telegram", or when an orchestrator reaches the merge gate of a UI PR.
---

# UX video review

Jeff reviews UI on his phone, not in a PR. A UI change is not done until he has
watched it moving and either said it is fine or his notes are fixed. Screenshots in a
PR body do not count: he wants the motion.

Script: `S=~/.claude/skills/ux-video-review/scripts/tg_review.py`

```bash
$S send /path/flow.mp4 --caption "..." --tag o6b   # -> SENT <message_id> <utc-iso>
$S text "..." --tag o6b                             # a follow-up line in the same DM
$S replies --since <utc-iso from SENT> [--wait 1800] # Jeff's replies after that, or NO-REPLY-YET
#   --via duda (auto under ajuda-brain): the ajudaduda dev group, read from prod PG review_replies.
#   --via baba (auto elsewhere): BabaFlow's message_cache. Never read AjudaDuda feedback via baba.
```

**The channel follows the repo** (Jeff, 2026-10-18): in an AjudaDuda checkout it sends through
the Duda production bot; anywhere else (BabaFlow, the brain) through **Baba's bot**, Jeff's
technical DM where Baba talks to him. A BabaFlow video in the Duda chat is the wrong channel.
`--via` overrides; the script prints which one it picked. The Duda path (Jeff, 2026-10-17: "you have your
own telegram"): the mp4 and caption are piped to CT 205 and `curl` runs there with
`TELEGRAM_BOT_TOKEN` / `TELEGRAM_ADMIN_ID` from `/opt/duda/.env`, so the token never leaves
the box; temp files go to CT 205's `/tmp`, never `/opt/duda`. `--via baba` uses Baba's bot
instead. Neither path calls `getUpdates` (the prod bot long-polls; a second poller would
steal its updates).

**AjudaDuda videos and questions go to the ajudaduda dev Telegram group** (Jeff, 2026-10-18:
his channel now), never his bot DM: a DM to the Duda bot is answered by the Coach. `--via duda`
sends to the group by default (`OPS_ALERT_CHAT_ID`, read on CT 205 like the token); `--to dm`
exists only for an explicit ask.

**Replies.** `replies` reads the store that matches the channel: `--via duda` reads prod
Postgres `review_replies` on CT 206 (every group message and Duda DM reply, since ajudaduda
#414/#478/#485), `--via baba` reads Baba's `message_cache` on CT 212.

## Who does what

- **`ux-evidence` agent** (`agents/ux-evidence.md`, Sonnet) does §1 for the builder: its own
  headless Chrome with a throwaway profile (`chrome-devtools-mcp --isolated --headless`, never
  `--autoConnect` to Jeff's Chrome, which asks him to allow it every time), records, composes,
  runs the `frame-reviewer` loop and returns `video:`. spawn.sh passes both agents to every
  builder with `--agents "$(python3 scripts/agents_json.py)"`, the one route whose MCP servers
  survive `--strict-mcp-config`; outside a builder, run the same flag yourself.
- **Builder** (the session that made the change) gets the video from `ux-evidence` and gives the
  orchestrator its local path in the `pr-open` report, and again after any UI fix.
- **Orchestrator** sends it, waits for Jeff, and relays his notes to the builder as
  one numbered list. It does not merge a UI PR until Jeff has answered or the
  standing wait (below) has passed.

## 1. Record (builder)

1. Run the app the way its tests do (PWA: `npm run dev -w apps/duda-pwa` against a
   local or staging API), or use staging once the branch is deployed.
2. `emulate` the page at `390x844x3,mobile,touch` (iPhone-sized), light mode, pt-BR.
3. `screencast_start` with an `.mp4` path, then walk the flow with real `click`/`fill`
   calls from its first screen to its last (each click preceded by `scripts/tap_ring.js` via
   `evaluate_script` on the same element, so the tap shows: the screencast draws no pointer),
   pausing ~1 s on each screen so motion
   finishes. Show the edge a reviewer would try: a back tap, the "Outro" path. **Show
   the error states too** (Jeff, 2026-10-17): a failed request and its retry, invalid
   input, a server refusal (e.g. e-mail in use), offline, whichever the flow has.
   **Show the whole viewport the whole time** (Jeff, 2026-10-18): no crops or cuts to one
   panel. To show a detail, zoom in smoothly from the full view, hold, and zoom back out to
   the full view (animated, e.g. ffmpeg `zoompan`), never a hard cut to a zoomed crop.
4. `screencast_stop`. Keep it under ~90 s and 50 MB (re-encode with ffmpeg if not).
   Check the raw shape: `ffprobe -show_entries stream=width,height,sample_aspect_ratio`
   must give a phone ratio (~390x844) with SAR 1:1. A stretched or squashed recording (Jeff,
   2026-10-17: "weirdly stretched") means the capture size and the emulated viewport disagree;
   re-record. Save everything outside `/tmp` (`~/Movies/<name>-review/`): `/tmp` is wiped on restart.
   Once the final is composed, shrink the raw (`-c:v libx264 -crf 30 -preset slow`): device
   captures run 10-120 MB and ~/Movies had 4.5 GB of raws by 2026-10-19; finals are ~1-2 MB.
4a. **Pick the frame by what the user sees** (Jeff, 2026-10-18: "maybe it should not be phone on
   the right? its hard to see... phone when simulating what users will see like email and landers
   but desktop for the babaflow ux"):
   - **Phone layout** only for what an end user sees on a phone: the AjudaDuda app/PWA, e-mails,
     landers. Composed as below.
   - **Desktop UX (BabaFlow admin, any operator/admin screen):** record at desktop size
     (`1440x900x1` or `1920x1080x1`, no `mobile`/`touch`), no phone frame, and compose it
     with a column of short explanatory points down the LEFT (current one highlighted, done ones
     checked), the desktop recording on the right (Jeff, 2026-10-19: "for babaflow admin we show
     on desktop with some points on the left explaining things"). Same steps file as below;
     keep the recording large enough to read.
   The phone composed layout: landscape 1920x1080,
   the walkthrough's steps on the left (current one highlighted, done ones checked), the raw
   recording in an iPhone frame on the right. Write a steps file with the time each step
   starts in the raw recording (`steps.txt`: `title: ...`, then `0:00 -> Abre o app`, `0:07 -> ...`;
   or JSON `{"title": ..., "steps": [{"start": 0, "text": ...}]}`), one short step per screen or
   action. Up to 5 show as one list; past 5 the list is a sliding 5-row window (the step just
   done stays above the current one, 0.45 s eased slide, edge fades, "Passo 3 de 12" /
   "Step 3 of 12" under the title, `--lang auto|pt|en`), never pages. Still stretches longer
   than 1.5 s (the agent thinking between taps; a 10-step flow came out at 121 s) are cut to
   their first 0.6 s and last 0.9 s and the step times moved to match (`--max-still`, 0 keeps
   all), so the final is shorter than the raw. The screencast's sparse frames (3-30 fps) are
   blended rather than repeated, so taps and screen changes dissolve instead of jumping
   (`--no-blend` to repeat). Then:
   `python3 ~/.claude/skills/ux-video-review/scripts/compose_phone_video.py --video raw.mp4 --steps steps.txt --out final.mp4 [--title "..."]`
   (`--self-test` checks the script). A device or Simulator capture (1206x2622) already has its
   own clock and Dynamic Island, so the frame's "9:41" bar is skipped automatically (it showed the
   top twice, Jeff 2026-10-19); `--status-bar draw|none` overrides, and never crop the bar off by hand. ffprobe the **final**: 1920x1080, SAR 1:1, no longer than
   the raw. The final is what gets reviewed, committed and sent.
4b. **The frames are reviewed before Jeff sees them** (Jeff, 2026-10-17: "have codex review
   and fix any bad shit"; 2026-10-19: Haiku 5.5, and only the frames where something happens).
   `scripts/review_frames.py final.mp4 --out sheets-vN --layout phone|desktop` keeps each
   animation's start, middle and settled frames and one frame of each still stretch, crops to
   the phone or the desktop card and tiles them (4 phone or 2 desktop frames to an image): a 40 s video is ~8.5k tokens, not the
   ~66k of `fps=1`. The **`frame-reviewer`** agent (`claude-haiku-5-5`, `agents/frame-reviewer.md`)
   reads the sheets against the steps file and its checklist; fix, re-record, repeat until it
   says `clean`. Only then report `video:`. Never open the sheets in the builder's own context,
   and never hand-roll `codex exec` for this (2026-10-18: update menu + 401, the tab hangs).
5. Commit the final to a `pr-media/<slug>` branch (never the PR branch), link it in the PR
   body, and report the local path.
6. **Clean up what you started**, every time, including when the run fails (2026-10-21:
   Simulator.app was left open for a day). **Simulator, in any repo:** never `xcrun simctl boot`
   by hand; use `scripts/sim_session.sh`:
   ```bash
   SIM=~/.claude/skills/ux-video-review/scripts/sim_session.sh
   $SIM boot ["iPhone 17"]       # remembers what was running, boots, waits; prints the UDID
   $SIM record ~/Movies/<slug>-review/raw.mp4   # ... drive the app ...
   $SIM stop                     # mp4 written whole
   $SIM end                      # shuts down only what this session booted, quits the app if it wasn't open
   $SIM run -- bash apps/duda-mobile/scripts/run-maestro.sh flow.yaml   # a repo's own runner, always cleaned up
   ```
   Repo runners (AjudaDuda's `run-maestro.sh`, `run-vrt.sh`) boot a Simulator and never shut it
   down; keep them in the repo (CI runs them) and wrap them in `run`. `end` also catches the
   device an already-open Simulator.app boots on its own. If a run died before `end`, use
   `end --all` once you know no other builder is on the Simulator. Also stop any dev server
   you started (kill its PID; don't `pkill node`), close extra browser pages, delete
   `./.ux-evidence-raw.mp4` if it's still in the checkout, and remove old `sheets-v*` folders
   once the reviewer has said `clean`. Keep only the final, the steps file and the shrunk raw.

## 2. Send (orchestrator)

Caption, at most 4 short lines, in the language Jeff wrote in:
what changed, the 2-3 things to look at, and how to answer.

```
Novo cadastro estilo Duolingo (PR #412/#4xx), do início ao fim.
Olha: a ordem das perguntas, o "Continuar" com a reação da Duda, o quadro da criança no fim.
Responde aqui com o que mudar (pode mandar print). "ok" se tá bom.
```

Record the `SENT` id and timestamp in the builder's ledger log
(`tell.sh <slug> --log-only "video sent #<id> <iso>"`).

## 3. Read replies and act

`$S replies --since <iso> --wait 1800` in the background (Bash `run_in_background`),
so the wait wakes you instead of polling. Use the same `--via` as the send (the default
picks it from the repo the same way). Do not put the tag in `--caption` too: `--tag` already
prefixes it (v2 of O6b went out as `[revisão] [revisão]`). Then:

- **"ok" / approval:** merge under the normal gates; one line back: `$S text "Valeu, mergeado."`.
- **Notes:** number them, confirm in one line which ones you will do
  (`$S text "Vou fazer 1, 2 e 4; 3 fica pra depois porque ..."`), send the list to the
  builder, and send a new video once the fixes are in. Money, plans and trial wording
  stay Jeff's even inside a note: ask, do not decide.
- **No reply after the wait:** hold the merge if the change is user-facing in
  production; otherwise merge to staging only and ask again with the next video.
  Never promote a UX change to production on silence.

Jeff's replies also reach the org seat (it reads the same DMs). If the seat answers
him too, that is fine; your relay to the builder is what makes the change.
