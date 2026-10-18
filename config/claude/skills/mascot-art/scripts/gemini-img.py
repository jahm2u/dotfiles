#!/usr/bin/env python3
"""Generate an image with Gemini from a reference image + prompt. Usage: gemini-img.py <ref.png> <out.png> "<prompt>" [model]"""
import base64, json, sys, urllib.request, pathlib
ref, out, prompt = sys.argv[1], sys.argv[2], sys.argv[3]
model = sys.argv[4] if len(sys.argv) > 4 else "gemini-2.5-flash-image"
key = pathlib.Path.home().joinpath(".config/gemini/api_key").read_text().strip()
body = {"contents": [{"parts": [
    {"inline_data": {"mime_type": "image/png", "data": base64.b64encode(open(ref, "rb").read()).decode()}},
    {"text": prompt}]}], "generationConfig": {"responseModalities": ["IMAGE", "TEXT"]}}
req = urllib.request.Request(f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
    data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "x-goog-api-key": key})
res = json.load(urllib.request.urlopen(req, timeout=180))
for p in res["candidates"][0]["content"]["parts"]:
    if "inlineData" in p or "inline_data" in p:
        d = p.get("inlineData") or p.get("inline_data")
        open(out, "wb").write(base64.b64decode(d["data"])); print("wrote", out); break
else:
    print("no image:", json.dumps(res)[:400])
