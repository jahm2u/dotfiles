---
name: ux-video-review
description: Get Jeff's feedback on a UI change by video on Telegram. Record the changed flow at phone size with real taps (Chrome DevTools screencast), send the mp4 to Jeff's Telegram DM with a short pt-BR/English caption of what to look at, read his replies, and turn them into fixes before merge. Use whenever a PR changes what a user sees or how a screen moves (any UX change in ajudaduda's PWA or mobile, marketing, onboarding), when Jeff says "send me a video", "show me on telegram", or when an orchestrator reaches the merge gate of a UI PR.
---

# UX video review

Jeff reviews UI on his phone, not in a PR. A UI change is not done until he has
watched it moving and either said it is fine or his notes are fixed. Screenshots in a
PR body do not count: he wants the motion.

Script: `S=~/.claude/skills/ux-video-review/scripts/tg_review.py`

```bash
$S send /path/flow.mp4 --caption "..." --tag o6b   # -> SENT <message_id> <utc-iso>
$S text "..." --tag o6b                             # a follow-up line in the same DM
$S replies --since <utc-iso from SENT> [--wait 1800] # Jeff's DMs after that, or NO-REPLY-YET
```

It sends through **the Duda production bot** by default (Jeff, 2026-10-17: "you have your
own telegram"): the mp4 and caption are piped to CT 205 and `curl` runs there with
`TELEGRAM_BOT_TOKEN` / `TELEGRAM_ADMIN_ID` from `/opt/duda/.env`, so the token never leaves
the box; temp files go to CT 205's `/tmp`, never `/opt/duda`. `--via baba` uses Baba's bot
instead. Neither path calls `getUpdates` (the prod bot long-polls; a second poller would
steal its updates).

**Replies.** A DM to the Duda bot is answered by the Coach and not stored where this skill
can read it, so `replies` (which reads Baba's DM store) only sees answers sent to Baba's
bot. Until the Duda bot keeps review replies (ajudaduda issue: admin reply to a review video
is stored, not sent to the Coach), ask Jeff to answer in the Claude session or by replying to
the video, and check with him there.

## Who does what

- **Builder** (the session that made the change) records the video and gives the
  orchestrator its local path in the `pr-open` report, and again after any UI fix.
  A builder needs the browser: spawn it with `--mcp full`.
- **Orchestrator** sends it, waits for Jeff, and relays his notes to the builder as
  one numbered list. It does not merge a UI PR until Jeff has answered or the
  standing wait (below) has passed.

## 1. Record (builder)

1. Run the app the way its tests do (PWA: `npm run dev -w apps/duda-pwa` against a
   local or staging API), or use staging once the branch is deployed.
2. `emulate` the page at `390x844x3,mobile,touch` (iPhone-sized), light mode, pt-BR.
3. `screencast_start` with an `.mp4` path, then walk the flow with real `click`/`fill`
   calls from its first screen to its last, pausing ~1 s on each screen so motion
   finishes. Show the edge a reviewer would try: a back tap, the "Outro" path. **Show
   the error states too** (Jeff, 2026-10-17): a failed request and its retry, invalid
   input, a server refusal (e.g. e-mail in use), offline, whichever the flow has.
4. `screencast_stop`. Keep it under ~90 s and 50 MB (re-encode with ffmpeg if not).
   Check the shape before reporting: `ffprobe -show_entries stream=width,height,sample_aspect_ratio`
   must give a phone ratio (~390x844) with SAR 1:1. A stretched or squashed recording (Jeff,
   2026-10-17: "weirdly stretched") means the capture size and the emulated viewport disagree;
   re-record. `tg_review.py send` now re-encodes to square pixels and passes width/height.
   Save it outside `/tmp` (`~/Movies/duda-review/`): `/tmp` is wiped on restart.
4b. **Codex reviews the video before Jeff does** (Jeff, 2026-10-17: "have codex review
   and fix any bad shit"). Extract frames (`ffmpeg -i v.mp4 -vf fps=1 f%03d.png`), have
   Codex review them for anything broken, ugly, confusing or off-copy, fix what it finds,
   re-record, repeat until clean. Only then report `video:`.
   **Do not hand-roll `codex exec` for this** (2026-10-18): a builder's own script hits
   Codex's "Update available" menu (no `check_for_update_on_startup=false`) and, from a
   builder's Bash, a 401 (no gateway key there), and the tab hangs. Until a shared frame
   script exists on `codex-review.sh`'s route, the frame review is a fresh **Claude
   subagent** given the contact sheet and the same checklist (broken, ugly, confusing,
   off-copy, error states shown). Never move the gateway key into a file to make Codex work.
5. Commit it to a `pr-media/<slug>` branch (never the PR branch), link it in the PR
   body, and report the local path.

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
so the wait wakes you instead of polling. **That reads Baba's message cache only: it
never sees a reply to a `--via duda` video.** Until ajudaduda #420 (review replies
saved) is in production, a Duda DM reply goes to the Coach; read it from the Coach's
transcript on CT 205 (2026-10-17: Jeff's "tiro também" was found this way):

```bash
ssh mox "pct exec 205 -- bash -lc 'ls -t /opt/.claude/projects/-app/*.jsonl | head -1 | xargs tail -c 60000'" \
  | python3 -I -c 'import sys,json
for l in sys.stdin:
  try: d=json.loads(l)
  except Exception: continue
  c=d.get("message",{}).get("content")
  if d.get("type")=="user" and isinstance(c,str) and "[revis" in c: print(d["timestamp"][:19], c[-300:])'
```

`docker logs casa-tarefas` shows `Coach message triggered isDirectMessage: true` with
the time but not the text. Do not put the tag in `--caption` too: `--tag` already
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
