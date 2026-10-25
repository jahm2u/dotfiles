---
name: gemini-video
description: Watch a video with Gemini (YouTube URL or local file) and get structured notes, diagram reconstructions, timestamps or answers. Use when the user asks to "watch this video", "get the transcript/diagrams of this YouTube video", "summarize this video", or any task needing video/audio understanding.
---

# gemini-video

Gemini reads the video frames and audio directly; no download needed for YouTube.

```bash
S=~/.claude/skills/gemini-video/scripts/gemini.py
python3 $S --video "https://www.youtube.com/watch?v=ID" --prompt-file prompt.txt --out notes.md
python3 $S --video ./clip.mp4 --prompt "list every slide with timestamp" --out slides.md
python3 $S --list-models
```

- Key: `~/.config/gemini/api-key` (chmod 600) or `$GEMINI_API_KEY`. Never print it. Source: SSM
  `/ipmedia-approvalbot-dev/gemini-api-key`, profile `ipmedia-ai`, us-east-2 (the moderation bot's dev key).
- Default model `gemini-3.1-pro-preview`; pass `--model` with a name from `--list-models` (without `models/`).
- A ~1h video is ~135k input tokens. Private YouTube videos fail; download and pass the file instead.
- Write outputs outside project repos (e.g. `~/scratch/<topic>/`) unless the user wants them in the repo.
- Ask for notes in the model's own words, not a verbatim transcript. For diagrams, ask for timestamp +
  a mermaid or outline reconstruction.
