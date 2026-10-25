---
name: openai-image
description: "Generate images (diagrams, illustrations, covers, mockups) with the OpenAI Images API using Jeff's key. Use when asked to generate, draw or illustrate an image, diagram or visual, or when a doc or page would be clearer with a picture."
---

# OpenAI image generation

```bash
python3 ~/.claude/skills/openai-image/scripts/gen_image.py <out.png> --prompt "..." [--size 1536x1024] [--quality high] [--model ...]
```

- Key: `$OPENAI_API_KEY`, else `~/.config/openai/api-key` (chmod 600). Never print, echo, cat or log it,
  never copy it into a repo, a prompt or a message. If it is missing, ask Jeff to copy the key and run
  `! pbpaste > ~/.config/openai/api-key && chmod 600 ~/.config/openai/api-key`.
- Default model `gpt-image-2.5-sunburst` (override with `--model` or `$OPENAI_IMAGE_MODEL`). Sizes:
  `1024x1024`, `1536x1024`, `1024x1536`. A call takes 30-120 s; run several in parallel as separate processes.
- Diagrams: give every label word for word, in quotes, and ask for "no other text". Then open the PNG with
  Read and check every label before using it: image models misspell and invent text. Regenerate what is wrong.
- Save outputs under the repo's `screenshots/<topic>/` (gitignored), never under `docs/`.
