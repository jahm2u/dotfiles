#!/usr/bin/env python3
"""Generate an image with the OpenAI Images API. Key: $OPENAI_API_KEY or ~/.config/openai/api-key."""
import argparse, base64, json, os, sys, time, urllib.error, urllib.request
from pathlib import Path

KEY_FILE = Path.home() / ".config" / "openai" / "api-key"
DEFAULT_MODEL = os.environ.get("OPENAI_IMAGE_MODEL", "gpt-image-2.5-sunburst")


def load_key() -> str:
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key and KEY_FILE.exists():
        key = KEY_FILE.read_text().strip()
    if not key:
        sys.exit(f"no OpenAI key: set OPENAI_API_KEY or write it to {KEY_FILE} (chmod 600)")
    return key


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("out", help="output .png path")
    ap.add_argument("--prompt", help="prompt text (or --prompt-file, or stdin)")
    ap.add_argument("--prompt-file")
    ap.add_argument("--size", default="1536x1024", help="1024x1024 | 1536x1024 | 1024x1536")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--quality", help="low | medium | high")
    a = ap.parse_args()
    prompt = a.prompt or (Path(a.prompt_file).read_text() if a.prompt_file else sys.stdin.read())
    if not prompt.strip():
        sys.exit("empty prompt")
    body = {"model": a.model, "prompt": prompt, "size": a.size, "n": 1}
    if a.quality:
        body["quality"] = a.quality
    req = urllib.request.Request(
        "https://api.openai.com/v1/images/generations",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {load_key()}", "Content-Type": "application/json"},
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode()[:500]}")
    b64 = data["data"][0].get("b64_json")
    if not b64:
        sys.exit(f"no image in response: {json.dumps(data)[:300]}")
    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(base64.b64decode(b64))
    print(f"{out} ({out.stat().st_size // 1024} KB, {time.time() - t0:.0f}s, {a.model})")


if __name__ == "__main__":
    main()
