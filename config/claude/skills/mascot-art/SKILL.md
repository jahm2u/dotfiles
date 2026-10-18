---
name: mascot-art
description: Generate consistent mascot illustrations (poses, moods, widget states, lock-screen glyphs) from an existing character reference with Gemini or OpenAI image models, as transparent cutouts, and preview them on status-coloured widget backgrounds. Use when asked to design widget art, mascot poses or moods, app imagery, "Duolingo-style" character states, or icons for a state machine (AjudaDuda's Duda first; works for any mascot).
---

# mascot-art

This skill turns one character reference image into a whole set of poses that still look like the same character. Each pose is a transparent cutout. The app paints the colour behind it, so the same art works for every status.

## Keys and models

- **OpenAI** `gpt-image-1`, key at `~/.config/openai/api-key`. This is the default for cutouts: it returns a real transparent background (`background=transparent`, RGBA PNG).
- **Gemini** `gemini-2.5-flash-image`, key at `~/.config/gemini/api_key`. Gemini is good at keeping the character consistent from the reference, but it can't make transparent backgrounds. Use it for full scenes and for a second opinion on a pose.
- Never print either key. The scripts read them from disk.

## Scripts (`scripts/`)

```bash
S=~/.claude/skills/mascot-art/scripts
$S/openai-img.py <ref.png> <out.png> "<prompt>" [low|medium|high]   # transparent cutout, 1024²
$S/gemini-img.py <ref.png> <out.png> "<prompt>" [model]             # full scene, opaque
$S/status-card.sh <cutout.png> <good|normal|urgent|done|away|#hex> <out.png> [size]  # preview a widget state
```

Run several generations in parallel with `&` and `wait`; each one takes 30 to 90 seconds. Write the results under `~/Movies/<project>-review/widget-art/`, never into a repo, until someone picks a set. A builder then commits the chosen PNGs into the app's assets.

## Prompt template

To keep a set consistent, start every prompt with the same identity sentence and change only the pose and mood:

> Same character as the reference (<one line naming the character's fixed traits: hair, outfit, props>), same illustration style. Full-body character cutout, centered, transparent background, no scenery, no text.
> Pose: <pose>. Mood: <mood>.

The model may still bake in borders or rounded corners, or forget the transparency. Check each file with `ffprobe ... pix_fmt` (it should say `rgba`) and look at it before showing anyone.

## Widget state design (from Duolingo's widget, blog.duolingo.com/widget-feature)

- **Show one thing:** whether today's goal is done, and the streak. Duolingo found that extra stats didn't add value.
- **The mascot's mood carries the message.** It changes with the time of day and whether the goal is done. Calm and happy when done, more and more desperate as the deadline nears.
- **Promote the install.** Most installs came after an in-app prompt with an animated how-to, shown after the user had just finished a lesson.
- **Lock-screen widgets** are a small monochrome silhouette plus a number. Make a separate one-colour glyph for them.
- **Background colour signals status** (Jeff, AjudaDuda): green when things are going well or everything is done, red when a chore is really overdue or about to run out of time. Orange is too close to red, so don't use it as the normal colour. For the default, use a calm blue. For days away (custody), use grey-blue.
- **Kids' apps:** urgency must be friendly, never scary or guilt-tripping (Brazil's ECA Digital, art. 18 §2). Turn the "desperate Duo" joke down for children.

## AjudaDuda specifics

- **Reference:** `repos/ajudaduda/apps/duda-mobile/assets/onboarding/duda-mascot.png`. Duda is a Brazilian girl coach with a curly dark ponytail, a yellow-green Brazil shirt and a black whistle on a cord.
- **States the app can compute today** (no new features):
  - chores waiting, on time;
  - one left in the evening;
  - overdue;
  - all done;
  - waiting for parent approval;
  - custody day away;
  - streak milestone.
- **Review:** new art goes to the ajudaduda dev Telegram group as a contact sheet before a builder wires it in (`ux-video-review` covers sending).
