#!/usr/bin/env python3
"""Ask Gemini about a video (YouTube URL or local file) or plain text. Key: $GEMINI_API_KEY or ~/.config/gemini/api-key."""
import argparse, json, mimetypes, os, pathlib, sys, time, urllib.request

BASE = "https://generativelanguage.googleapis.com"

def key():
    k = os.environ.get("GEMINI_API_KEY") or (pathlib.Path.home() / ".config/gemini/api-key").read_text().strip()
    if not k:
        sys.exit("no Gemini key: set GEMINI_API_KEY or ~/.config/gemini/api-key")
    return k

def call(url, body=None, headers=None, method=None):
    req = urllib.request.Request(url, data=body, headers=headers or {}, method=method)
    with urllib.request.urlopen(req, timeout=900) as r:
        return r

def upload(path, k):
    size = os.path.getsize(path)
    mime = mimetypes.guess_type(path)[0] or "video/mp4"
    start = urllib.request.Request(f"{BASE}/upload/v1beta/files?key={k}", method="POST",
        data=json.dumps({"file": {"display_name": pathlib.Path(path).name}}).encode(),
        headers={"X-Goog-Upload-Protocol": "resumable", "X-Goog-Upload-Command": "start",
                 "X-Goog-Upload-Header-Content-Length": str(size), "X-Goog-Upload-Header-Content-Type": mime,
                 "Content-Type": "application/json"})
    up_url = urllib.request.urlopen(start).headers["X-Goog-Upload-URL"]
    fin = urllib.request.Request(up_url, data=open(path, "rb").read(), method="POST",
        headers={"X-Goog-Upload-Offset": "0", "X-Goog-Upload-Command": "upload, finalize"})
    f = json.load(urllib.request.urlopen(fin))["file"]
    while f.get("state") == "PROCESSING":
        time.sleep(5)
        f = json.load(urllib.request.urlopen(f"{BASE}/v1beta/{f['name']}?key={k}"))
    return {"file_data": {"file_uri": f["uri"], "mime_type": mime}}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="gemini-3.1-pro-preview")
    ap.add_argument("--video", help="YouTube URL or local video path")
    ap.add_argument("--prompt", help="prompt text; or --prompt-file")
    ap.add_argument("--prompt-file")
    ap.add_argument("--out")
    ap.add_argument("--list-models", action="store_true")
    a = ap.parse_args()
    k = key()
    if a.list_models:
        ms = json.load(urllib.request.urlopen(f"{BASE}/v1beta/models?pageSize=200&key={k}"))["models"]
        print("\n".join(m["name"] for m in ms if "generateContent" in m.get("supportedGenerationMethods", [])))
        return
    if not a.out:
        sys.exit("--out is required")
    prompt = a.prompt or open(a.prompt_file).read()
    parts = []
    if a.video:
        parts.append({"file_data": {"file_uri": a.video}} if a.video.startswith("http") else upload(a.video, k))
    parts.append({"text": prompt})
    req = urllib.request.Request(f"{BASE}/v1beta/models/{a.model.removeprefix('models/')}:generateContent?key={k}",
        data=json.dumps({"contents": [{"parts": parts}]}).encode(), headers={"Content-Type": "application/json"})
    r = json.load(urllib.request.urlopen(req, timeout=900))
    txt = "".join(p.get("text", "") for p in r["candidates"][0]["content"]["parts"])
    pathlib.Path(a.out).write_text(txt)
    print(a.out, len(txt), "chars", r.get("usageMetadata", {}).get("totalTokenCount"), "tokens")

if __name__ == "__main__":
    main()
