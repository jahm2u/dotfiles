#!/usr/bin/env python3
"""tg_review.py -- send Jeff a UX review video on Telegram, then read his replies.

    tg_review.py send VIDEO.mp4 --caption "text" [--tag o6b]   prints: SENT <message_id> <utc-iso>
    tg_review.py text "message" [--tag o6b]                    prints: SENT <message_id> <utc-iso>
    tg_review.py replies --since <utc-iso> [--wait SECS]       prints Jeff's DMs after that time, one per line

Sends through Baba's bot to Jeff's DM (the same line `seatctl tg` uses), with
sendVideo / sendMessage only, never getUpdates (that would steal the platform bot's
updates). Jeff's replies are read read-only from Baba's message_cache on CT 212, where
the platform stores every DM to the bot. Credentials come from BabaFlow/.env and are
never printed. Both directions are appended to the org seat's run/tg.log, so the seat
sees the thread too.
"""
import argparse, base64, json, os, re, subprocess, sys, tempfile, time, uuid, urllib.request
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
FLEET = os.environ.get("BABA_FLEET") or f"{HOME}/repos/01_business/tp/baba-brain/repos/fleet"
BABAFLOW = os.environ.get("BABAFLOW_REPO") or f"{HOME}/repos/01_business/tp/baba-brain/repos/BabaFlow"
SEAT_DIR = os.environ.get("ORG_SEAT_DIR") or f"{FLEET}/run"
MAX_BYTES = 49 * 1024 * 1024  # Bot API upload cap is 50 MB


def env():
    path = os.environ.get("BABAFLOW_ENV") or f"{BABAFLOW}/.env"
    out = {}
    for line in open(path):
        m = re.match(r"\s*([A-Z_]+)\s*=\s*(.*)", line)
        if m:
            out[m.group(1)] = m.group(2).strip().strip("'\"")
    tok, chat = out.get("BABA_TELEGRAM_BOT_TOKEN"), out.get("DEVBOT_OPERATOR_TELEGRAM_ID")
    if not tok or not chat:
        sys.exit("BABA_TELEGRAM_BOT_TOKEN / DEVBOT_OPERATOR_TELEGRAM_ID missing from BabaFlow/.env")
    return tok, chat


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def log(direction, text):
    try:
        os.makedirs(SEAT_DIR, exist_ok=True)
        with open(f"{SEAT_DIR}/tg.log", "a") as f:
            f.write(f"{now_iso()} {direction} {re.sub(r'\s+', ' ', text).strip()}\n")
    except OSError:
        pass


def call(method, fields, files=None):
    tok, _ = env()
    url = f"https://api.telegram.org/bot{tok}/{method}"
    if files:
        b = uuid.uuid4().hex
        parts = []
        for k, v in fields.items():
            parts.append(f'--{b}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
        for k, (name, data, ctype) in files.items():
            parts.append(f'--{b}\r\nContent-Disposition: form-data; name="{k}"; filename="{name}"\r\n'
                         f'Content-Type: {ctype}\r\n\r\n'.encode() + data + b"\r\n")
        body = b"".join(parts) + f"--{b}--\r\n".encode()
        req = urllib.request.Request(url, body, {"Content-Type": f"multipart/form-data; boundary={b}"})
    else:
        req = urllib.request.Request(url, json.dumps(fields).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        res = json.load(r)
    if not res.get("ok"):
        sys.exit(f"telegram {method}: {res.get('description')}")
    return res["result"]["message_id"]


def tagged(text, tag):
    return f"[{tag}] {text}" if tag else text


DUDA_SEND = r'''
set -eu
val() { sed -nE "s/^$1=['\"]?([^'\"]*)['\"]?\$/\1/p" /opt/duda/.env | tail -1; }
TELEGRAM_BOT_TOKEN=$(val TELEGRAM_BOT_TOKEN)
# group = the ajudaduda dev Telegram group (Jeff 2026-10-18: his channel now); dm = his bot DM
if [ "${4:-group}" = dm ]; then CHAT=$(val TELEGRAM_ADMIN_ID); else CHAT=$(val OPS_ALERT_CHAT_ID); fi
F=$1; CAPF=$5; CAP=$(cat "$CAPF"); rm -f "$CAPF"
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${CHAT:-}" ] || { [ "$F" = "-" ] || rm -f "$F"; echo "NO-DUDA-CREDS"; exit 3; }
# --form-string: with -F, a caption starting with @ or < is read as a file name
if [ "$F" = "-" ]; then
  curl -sS --max-time 60 "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$CHAT" --data-urlencode "text=$CAP" -d disable_web_page_preview=true
else
  trap 'rm -f "$F"' EXIT
  curl -sS --max-time 300 "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendVideo" \
    --form-string "chat_id=$CHAT" --form-string "caption=$CAP" -F supports_streaming=true \
    -F "width=$2" -F "height=$3" -F "video=@$F"
fi
'''


def blank_lead(video):
    """Seconds of blank (all-white or all-black) frames at the start. Telegram uses the
    first frame as the preview, so a recording that opens on a loading page arrives as an
    empty thumbnail (Jeff, 2026-10-18, #503 v4: "the preview here is a bit broken")."""
    lead = 0.0
    for vf in ("negate,blackdetect=d=0:pic_th=0.98", "blackdetect=d=0:pic_th=0.98"):
        err = subprocess.run(["ffmpeg", "-hide_banner", "-i", video, "-vf", vf, "-an", "-f", "null", "-"],
                             capture_output=True, text=True, timeout=300).stderr
        m = re.search(r"black_start:0(?:\.0+)?\s+black_end:([\d.]+)", err)
        if m:
            lead = max(lead, float(m.group(1)))
    return lead


def normalize(video):
    """Re-encode to square pixels, even dimensions, yuv420p and faststart, and return
    (path, width, height). Telegram stretches a video sent without width/height or with a
    non-square sample aspect ratio (Jeff, 2026-10-17: the #437 video was "weirdly stretched";
    the O7 v6 file had SAR 42200:29523)."""
    out = os.path.join(tempfile.gettempdir(), f"tgnorm-{uuid.uuid4().hex[:8]}.mp4")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", f"{blank_lead(video):.2f}", "-i", video,
                    "-vf", "scale=trunc(iw*sar/2)*2:trunc(ih/2)*2,setsar=1",
                    "-c:v", "libx264", "-crf", "26", "-pix_fmt", "yuv420p",
                    "-movflags", "+faststart", "-an", out], check=True, timeout=600)
    dims = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                           "-show_entries", "stream=width,height", "-of", "csv=p=0", out],
                          capture_output=True, text=True, check=True).stdout.strip().split(",")
    return out, int(dims[0]), int(dims[1])


def normalized_bytes(video):
    """normalize() and read it back, refusing anything over the Bot API's 50 MB."""
    norm, w, h = normalize(video)
    data = open(norm, "rb").read()
    os.remove(norm)
    if len(data) > MAX_BYTES:
        sys.exit(f"{video} is {len(data)//1048576} MB; Telegram bots take 50 MB. Re-encode smaller "
                 "(ffmpeg -i in.mp4 -vf scale=390:-2 -crf 30 out.mp4).")
    return data, w, h


def duda(video, text, to="group"):
    """Send through the Duda production bot on CT 205: the token never leaves the box.
    Every temp file carries this send's id, so two builders sending at once don't collide."""
    def push(local_bytes, remote):
        subprocess.run(["ssh", "-o", "BatchMode=yes", "mox", f"pct exec 205 -- sh -c 'cat > {remote}'"],
                       input=local_bytes, check=True, timeout=600)
    base = f"/tmp/duda-review-{uuid.uuid4().hex[:8]}"
    target, w, h = "-", 0, 0
    if video:
        data, w, h = normalized_bytes(video)
        target = f"{base}.mp4"
        push(data, target)
    push(text.encode(), f"{base}.txt")
    push(DUDA_SEND.encode(), f"{base}.sh")
    p = subprocess.run(["ssh", "-o", "BatchMode=yes", "mox",
                        f"pct exec 205 -- sh {base}.sh {target} {w} {h} {to} {base}.txt; pct exec 205 -- rm -f {base}.sh"],
                       capture_output=True, text=True, timeout=600)
    try:
        res = json.loads(p.stdout.strip().splitlines()[0])
    except Exception:
        sys.exit(f"duda send failed: {(p.stdout + p.stderr).strip()[:200]}")
    if not res.get("ok"):
        sys.exit(f"duda telegram: {res.get('description')}")
    return res["result"]["message_id"]


def cmd_send(a):
    if a.via == "duda":
        stamp = now_iso(); cap = tagged(a.caption, a.tag)[:1000]
        mid = duda(a.video, cap, a.to)
        log("->", f"#{mid} [duda {a.to}] [video {os.path.basename(a.video)}] {cap}")
        print(f"SENT {mid} {stamp} via duda to {a.to}"); return
    data, w, h = normalized_bytes(a.video)
    _, chat = env()
    cap = tagged(a.caption, a.tag)[:1000]
    stamp = now_iso()
    mid = call("sendVideo", {"chat_id": chat, "caption": cap, "supports_streaming": "true",
                             "width": str(w), "height": str(h)},
               {"video": (os.path.basename(a.video), data, "video/mp4")})
    log("->", f"#{mid} [video {os.path.basename(a.video)}] {cap}")
    print(f"SENT {mid} {stamp}")


def cmd_text(a):
    if a.via == "duda":
        stamp = now_iso(); text = tagged(a.message, a.tag)[:4000]
        mid = duda(None, text, a.to)
        log("->", f"#{mid} [duda {a.to}] {text}")
        print(f"SENT {mid} {stamp} via duda to {a.to}"); return
    _, chat = env()
    text = tagged(a.message, a.tag)[:4000]
    stamp = now_iso()
    mid = call("sendMessage", {"chat_id": chat, "text": text, "disable_web_page_preview": True})
    log("->", f"#{mid} {text}")
    print(f"SENT {mid} {stamp}")


def fetch_since(since):
    _, chat = env()
    prog = ("const db=require('better-sqlite3')('/opt/babaflow/data/message_cache.db',{readonly:true});"
            "const rows=db.prepare(\"SELECT id,created_at,message_text,screenshot_url FROM message_cache "
            "WHERE org_id = -1 AND CAST(telegram_chat_id AS TEXT) = ? AND created_at > ? ORDER BY id\")"
            f".all({json.dumps(str(chat))},{json.dumps(since)});"
            "process.stdout.write(JSON.stringify(rows));")
    b64 = base64.b64encode(prog.encode()).decode()
    remote = f"pct exec 212 -- bash -lc 'cd /opt/babaflow && echo {b64} | base64 -d | node'"
    p = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "mox", remote],
                       capture_output=True, text=True, timeout=60)
    if p.returncode != 0:
        sys.exit(f"reply fetch failed: {(p.stderr or p.stdout).strip()[:200]}")
    return json.loads(p.stdout or "[]")


def fetch_since_duda(since):
    """Jeff's replies in the ajudaduda dev group (and his Duda DM). The Duda bot saves every one
    into prod Postgres `review_replies` (#414/#478); BabaFlow's message_cache never sees them.
    Read-only, over ssh to CT 206 (duda-pg). The SQL travels base64 so no quoting can break it."""
    sql = ("SELECT coalesce(json_agg(r ORDER BY r.created_at), '[]') FROM ("
           "SELECT id, to_char(received_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"') AS created_at, "
           "text AS message_text, tag, replied_to_message_id, media_kind FROM review_replies "
           f"WHERE received_at > {json.dumps(since).replace(chr(34), chr(39))}::timestamptz) r")
    b64 = base64.b64encode(sql.encode()).decode()
    remote = (f"pct exec 206 -- su postgres -s /bin/sh -c "
              f"'cd /tmp && echo {b64} | base64 -d | psql -v ON_ERROR_STOP=1 -d duda -At'")
    p = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "mox", remote],
                       capture_output=True, text=True, timeout=60)
    if p.returncode != 0:
        sys.exit(f"duda reply fetch failed: {(p.stderr or p.stdout).strip()[:200]}")
    out = (p.stdout or "").strip()  # psql -At splits json_agg's array over several lines
    return json.loads(out or "[]")


def cmd_replies(a):
    since = a.since  # message_cache stores ISO 'YYYY-MM-DDTHH:MM:SS.mmmZ', so ISO compares in order
    deadline = time.time() + (a.wait or 0)
    while True:
        rows = fetch_since_duda(since) if a.via == "duda" else fetch_since(since)
        if rows or time.time() >= deadline:
            break
        time.sleep(30)
    for r in rows:
        extra = f" (screenshot: {r['screenshot_url']})" if r.get("screenshot_url") else ""
        if a.via == "duda":
            extra += f" [tag {r.get('tag') or '-'}, reply to #{r.get('replied_to_message_id') or '-'}]"
            if r.get("media_kind"): extra += f" ({r['media_kind']} attached)"
        print(f"{r['created_at']} #{r['id']} {r['message_text']}{extra}")
    if not rows:
        print("NO-REPLY-YET")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("send"); s.add_argument("video"); s.add_argument("--caption", required=True); s.add_argument("--tag")
    t = sub.add_parser("text"); t.add_argument("message"); t.add_argument("--tag")
    for p in (s, t):
        p.add_argument("--via", choices=["duda", "baba"], default=None,
                       help="duda = the Duda production bot on CT 205 (AjudaDuda work); baba = Baba's bot, Jeff's "
                            "technical DM (BabaFlow and everything else). Default: picked from the current repo.")
        p.add_argument("--to", choices=["group", "dm"], default="group",
                       help="duda only: group = the ajudaduda dev Telegram group (default, Jeff 2026-10-18); dm = Jeff's bot DM")
    r = sub.add_parser("replies"); r.add_argument("--since", required=True); r.add_argument("--wait", type=int, default=0)
    r.add_argument("--via", choices=["duda", "baba"], default=None,
                   help="duda = Jeff's replies in the ajudaduda dev group (prod PG review_replies); baba = BabaFlow's "
                        "message_cache. Default: picked from the current repo, like send.")
    a = ap.parse_args()
    if getattr(a, "via", "") is None:
        top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
        a.via = "duda" if re.search(r"ajuda|duda", os.path.basename(top), re.I) else "baba"
        print(f"via {a.via} (repo {os.path.basename(top) or '?'})", file=sys.stderr)
    {"send": cmd_send, "text": cmd_text, "replies": cmd_replies}[a.cmd](a)


if __name__ == "__main__":
    main()
