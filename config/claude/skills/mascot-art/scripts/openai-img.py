#!/usr/bin/env python3
"""Edit/generate an image with OpenAI gpt-image-1 from a reference image, transparent background.
Usage: openai-img.py <ref.png> <out.png> "<prompt>" [quality: low|medium|high]
Key: ~/.config/openai/api-key (never printed)."""
import base64, json, pathlib, sys, urllib.request, uuid

ref, out, prompt = sys.argv[1], sys.argv[2], sys.argv[3]
quality = sys.argv[4] if len(sys.argv) > 4 else "medium"
key = pathlib.Path.home().joinpath(".config/openai/api-key").read_text().strip()
fields = {"model": "gpt-image-1", "prompt": prompt, "background": "transparent",
          "output_format": "png", "size": "1024x1024", "quality": quality}
b = uuid.uuid4().hex
body = b""
for k, v in fields.items():
    body += f'--{b}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
body += (f'--{b}\r\nContent-Disposition: form-data; name="image[]"; filename="ref.png"\r\n'
         f"Content-Type: image/png\r\n\r\n").encode() + open(ref, "rb").read() + b"\r\n"
body += f"--{b}--\r\n".encode()
req = urllib.request.Request("https://api.openai.com/v1/images/edits", data=body,
                             headers={"Authorization": f"Bearer {key}",
                                      "Content-Type": f"multipart/form-data; boundary={b}"})
try:
    res = json.load(urllib.request.urlopen(req, timeout=300))
except urllib.error.HTTPError as e:
    sys.exit(f"openai {e.code}: {e.read()[:300]!r}")
open(out, "wb").write(base64.b64decode(res["data"][0]["b64_json"]))
print("wrote", out)
