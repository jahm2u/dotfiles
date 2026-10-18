#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FFMPEG = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
FFPROBE = shutil.which("ffprobe") or "/opt/homebrew/bin/ffprobe"

W, H = 1920, 1080
FPS = 30
BG = (243, 244, 247)
INK = (24, 26, 32)
DIM = (150, 155, 166)
DONE = (92, 98, 110)
ACCENT = (37, 99, 235)
ACCENT_SOFT = (219, 230, 253)
CHECK = (22, 163, 74)
BODY = (28, 28, 31)
RIM = (70, 70, 76)

PANEL_X = 120
PANEL_W = 700
PANEL_TOP = 120
PANEL_BOTTOM = 980

PHONE_CX = 1392
PHONE_OUTER_H = 980
BEZEL = 16
STATUS_H = 48
SCREEN_R = 54

FONT_FACES = {
    "bold": [("/System/Library/Fonts/Avenir Next.ttc", 0), ("/System/Library/Fonts/HelveticaNeue.ttc", 1),
             ("/Library/Fonts/Arial Bold.ttf", 0), ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 0)],
    "demi": [("/System/Library/Fonts/Avenir Next.ttc", 2), ("/System/Library/Fonts/HelveticaNeue.ttc", 10),
             ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 0)],
    "regular": [("/System/Library/Fonts/Avenir Next.ttc", 5), ("/System/Library/Fonts/HelveticaNeue.ttc", 0),
                ("/System/Library/Fonts/Supplemental/Arial.ttf", 0)],
}


class InputError(Exception):
    pass


def font(weight, size):
    for path, index in FONT_FACES[weight]:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size, index=index)
            except OSError:
                continue
    fc = shutil.which("fc-match")
    if fc:
        style = "Bold" if weight != "regular" else "Regular"
        out = subprocess.run([fc, "-f", "%{file}", f"sans:style={style}"], capture_output=True, text=True).stdout
        if out and os.path.exists(out):
            return ImageFont.truetype(out, size)
    return ImageFont.load_default(size=size)


def even(n):
    return int(round(n / 2.0)) * 2


def run(cmd):
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        tail = "\n".join(proc.stderr.strip().splitlines()[-15:])
        raise RuntimeError(f"command failed: {' '.join(cmd[:3])} ...\n{tail}")
    return proc.stdout


def probe(path):
    out = run([FFPROBE, "-v", "error", "-select_streams", "v:0", "-show_entries",
               "stream=width,height,sample_aspect_ratio:format=duration", "-of", "json", str(path)])
    data = json.loads(out)
    streams = data.get("streams") or []
    if not streams:
        raise InputError(f"{path}: no video stream")
    s = streams[0]
    duration = float(data.get("format", {}).get("duration") or 0)
    return {"width": int(s["width"]), "height": int(s["height"]),
            "sar": s.get("sample_aspect_ratio", "1:1"), "duration": duration}


def parse_time(token):
    token = token.strip()
    if re.fullmatch(r"\d+(\.\d+)?", token):
        return float(token)
    m = re.fullmatch(r"(\d+):(\d{1,2}(?:\.\d+)?)", token)
    if m:
        return int(m.group(1)) * 60 + float(m.group(2))
    raise InputError(f"bad time {token!r}: use seconds (12.5) or mm:ss (0:12)")


def load_steps(path):
    p = Path(path)
    if not p.is_file():
        raise InputError(f"steps file not found: {path}")
    raw = p.read_text(encoding="utf-8")
    title = None
    steps = []
    if raw.lstrip().startswith(("{", "[")):
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as e:
            raise InputError(f"{path}: invalid JSON: {e}")
        if isinstance(data, dict):
            title = data.get("title")
            items = data.get("steps")
        else:
            items = data
        if not isinstance(items, list):
            raise InputError(f"{path}: expected a list of steps")
        for i, item in enumerate(items, 1):
            if isinstance(item, dict):
                t, text = item.get("start", item.get("t")), item.get("text", item.get("caption"))
            elif isinstance(item, (list, tuple)) and len(item) == 2:
                t, text = item
            else:
                raise InputError(f"{path}: step {i} must be {{\"start\": s, \"text\": ...}} or [s, text]")
            if t is None or not text:
                raise InputError(f"{path}: step {i} needs a start time and a caption")
            steps.append((parse_time(str(t)), str(text).strip()))
    else:
        for n, line in enumerate(raw.splitlines(), 1):
            line = line.strip()
            if not line:
                continue
            if line.lower().startswith("title:"):
                title = line.split(":", 1)[1].strip()
                continue
            m = re.match(r"^(\d+(?::\d{1,2})?(?:\.\d+)?)\s*(?:->|\||-|:)?\s+(.+)$", line)
            if not m:
                raise InputError(f"{path}:{n}: expected '<seconds or mm:ss> -> caption', got {line!r}")
            steps.append((parse_time(m.group(1)), m.group(2).strip()))
    if not steps:
        raise InputError(f"{path}: no steps")
    for i in range(1, len(steps)):
        if steps[i][0] <= steps[i - 1][0]:
            raise InputError(f"steps not sorted: step {i + 1} starts at {steps[i][0]:g}s, "
                             f"not after step {i} at {steps[i - 1][0]:g}s")
    if steps[0][0] < 0:
        raise InputError("step times must be >= 0")
    return title, steps


def wrap(draw, text, fnt, width):
    lines, cur = [], ""
    for word in text.split():
        trial = f"{cur} {word}".strip()
        if draw.textlength(trial, font=fnt) <= width or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def layout_steps(title, steps):
    probe_img = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    for size in range(40, 19, -2):
        title_f = font("bold", int(size * 1.4))
        step_f = font("demi", size)
        text_w = PANEL_W - int(size * 2.2)
        title_lines = wrap(probe_img, title, title_f, PANEL_W) if title else []
        title_h = len(title_lines) * int(size * 1.4 * 1.2) + (int(size * 1.6) if title else 0)
        blocks = [wrap(probe_img, text, step_f, text_w) for _, text in steps]
        line_h = int(size * 1.35)
        gap = int(size * 0.9)
        total = title_h + sum(len(b) * line_h for b in blocks) + gap * (len(blocks) - 1)
        if total <= PANEL_BOTTOM - PANEL_TOP:
            return size, title_f, title_lines, step_f, blocks, line_h, gap, total
    raise InputError("too many steps or captions too long to fit the left panel; shorten them")


def render_panels(title, steps, outdir):
    size, title_f, title_lines, step_f, blocks, line_h, gap, total = layout_steps(title, steps)
    reg_f = font("regular", size)
    num_f = font("bold", int(size * 0.62))
    paths = []
    for current in range(len(steps)):
        img = Image.new("RGBA", (PANEL_W + 40, PANEL_BOTTOM - PANEL_TOP), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        y = max(0, (PANEL_BOTTOM - PANEL_TOP - total) // 2)
        for line in title_lines:
            d.text((0, y), line, font=title_f, fill=INK)
            y += int(size * 1.4 * 1.2)
        if title_lines:
            y += int(size * 0.5)
            d.rounded_rectangle((0, y, 72, y + 6), radius=3, fill=ACCENT)
            y += int(size * 1.1)
        r = int(size * 0.62)
        for i, block in enumerate(blocks):
            cy = y + line_h // 2
            cx = r
            block_h = len(block) * line_h
            if i == current:
                d.rounded_rectangle((-0, y - gap // 3, PANEL_W + 30, y + block_h + gap // 3),
                                    radius=16, fill=ACCENT_SOFT + (255,))
                cx = r + 14
                d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=ACCENT)
                d.text((cx, cy), str(i + 1), font=num_f, fill=(255, 255, 255), anchor="mm")
                fnt, color = step_f, INK
            elif i < current:
                d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=CHECK)
                k = r * 0.45
                d.line([(cx - k, cy + k * 0.05), (cx - k * 0.25, cy + k * 0.75), (cx + k, cy - k * 0.7)],
                       fill=(255, 255, 255), width=max(3, size // 10), joint="curve")
                fnt, color = reg_f, DONE
            else:
                d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=DIM, width=3)
                d.text((cx, cy), str(i + 1), font=num_f, fill=DIM, anchor="mm")
                fnt, color = reg_f, DIM
            tx = cx + r + int(size * 0.8)
            for j, line in enumerate(block):
                d.text((tx, y + j * line_h + line_h // 2), line, font=fnt, fill=color, anchor="lm")
            y += block_h + gap
        p = outdir / f"panel_{current:02d}.png"
        img.save(p)
        paths.append(p)
    return paths


def phone_geometry(vw, vh):
    screen_h = PHONE_OUTER_H - 2 * BEZEL
    video_h = even(screen_h - STATUS_H)
    video_w = even(video_h * vw / vh)
    screen_h = video_h + STATUS_H
    screen_w = video_w
    outer_w = screen_w + 2 * BEZEL
    outer_h = screen_h + 2 * BEZEL
    ox = PHONE_CX - outer_w // 2
    oy = (H - outer_h) // 2
    sx, sy = ox + BEZEL, oy + BEZEL
    return {"outer": (ox, oy, ox + outer_w, oy + outer_h), "screen": (sx, sy, sx + screen_w, sy + screen_h),
            "video": (sx, sy + STATUS_H, video_w, video_h)}


def render_background(g, path):
    img = Image.new("RGB", (W, H), BG)
    sx, sy, sx2, sy2 = g["screen"]
    ImageDraw.Draw(img).rectangle((sx, sy, sx2, sy + STATUS_H + 2), fill=(255, 255, 255))
    img.save(path)


def render_frame(g, path):
    img = Image.new("RGBA", (W, H), BG + (255,))
    ox, oy, ox2, oy2 = g["outer"]
    outer_r = SCREEN_R + BEZEL
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((ox + 14, oy + 22, ox2 + 14, oy2 + 22), radius=outer_r, fill=95)
    img.paste((70, 74, 86, 255), (0, 0), shadow.filter(ImageFilter.GaussianBlur(28)))
    d = ImageDraw.Draw(img)
    for side_y, length in ((oy + 170, 60), (oy + 250, 90), (oy + 360, 90)):
        d.rounded_rectangle((ox - 5, side_y, ox + 4, side_y + length), radius=3, fill=RIM)
    d.rounded_rectangle((ox2 - 4, oy + 280, ox2 + 5, oy + 410), radius=3, fill=RIM)
    d.rounded_rectangle((ox, oy, ox2, oy2), radius=outer_r, fill=RIM)
    d.rounded_rectangle((ox + 3, oy + 3, ox2 - 3, oy2 - 3), radius=outer_r - 3, fill=BODY)
    sx, sy, sx2, sy2 = g["screen"]
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle((sx, sy, sx2 - 1, sy2 - 1), radius=SCREEN_R, fill=255)
    alpha = img.getchannel("A")
    alpha.paste(0, (0, 0), mask)
    img.putalpha(alpha)
    d = ImageDraw.Draw(img)
    cx = (sx + sx2) // 2
    iw, ih = 118, 34
    iy = sy + (STATUS_H - ih) // 2 + 2
    d.rounded_rectangle((cx - iw // 2, iy, cx + iw // 2, iy + ih), radius=ih // 2, fill=(0, 0, 0))
    tf = font("demi", 22)
    d.text((sx + 62, sy + STATUS_H // 2 + 2), "9:41", font=tf, fill=(0, 0, 0), anchor="mm")
    bx, by = sx2 - 70, sy + STATUS_H // 2 + 2
    for i, hgt in enumerate((6, 9, 12, 15)):
        d.rounded_rectangle((bx - 44 + i * 7, by + 7 - hgt, bx - 40 + i * 7, by + 7), radius=1, fill=(0, 0, 0))
    d.rounded_rectangle((bx, by - 7, bx + 30, by + 7), radius=4, outline=(0, 0, 0), width=2)
    d.rectangle((bx + 3, by - 4, bx + 24, by + 4), fill=(0, 0, 0))
    d.rounded_rectangle((bx + 31, by - 3, bx + 34, by + 3), radius=1, fill=(0, 0, 0))
    img.save(path)


def compose(video, steps_path, out, title=None):
    video = Path(video)
    if not video.is_file():
        raise InputError(f"video not found: {video}")
    file_title, steps = load_steps(steps_path)
    title = title if title is not None else file_title
    info = probe(video)
    if info["duration"] <= 0:
        raise InputError(f"{video}: could not read a duration")
    if info["width"] >= info["height"]:
        raise InputError(f"{video}: {info['width']}x{info['height']} is not portrait; record at 390x844")
    over = [(i + 1, t) for i, (t, _) in enumerate(steps) if t >= info["duration"]]
    if over:
        i, t = over[0]
        raise InputError(f"step {i} starts at {t:g}s, at or beyond the video's {info['duration']:.2f}s")
    num, den = (int(x) for x in (info["sar"] if re.fullmatch(r"\d+:\d+", info["sar"]) and info["sar"] != "0:1" else "1:1").split(":"))
    g = phone_geometry(info["width"] * num / den, info["height"])
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="compose_phone_") as td:
        td = Path(td)
        bg, frame = td / "bg.png", td / "frame.png"
        render_background(g, bg)
        render_frame(g, frame)
        panels = render_panels(title, steps, td)
        vx, vy, vw, vh = g["video"]
        cmd = [FFMPEG, "-y", "-v", "error", "-loop", "1", "-framerate", str(FPS), "-i", str(bg),
               "-i", str(video), "-i", str(frame)]
        for p in panels:
            cmd += ["-i", str(p)]
        chain = [f"[1:v]setpts=PTS-STARTPTS,fps={FPS},scale={vw}:{vh}:flags=lanczos,setsar=1[rec]",
                 f"[0:v][rec]overlay={vx}:{vy}:shortest=1[a0]",
                 "[a0][2:v]overlay=0:0[b0]"]
        last = "b0"
        for i, _ in enumerate(panels):
            start = 0 if i == 0 else steps[i][0]
            end = steps[i + 1][0] if i + 1 < len(steps) else info["duration"] + 10
            label = f"p{i}"
            chain.append(f"[{last}][{3 + i}:v]overlay={PANEL_X}:{PANEL_TOP}:"
                         f"enable='between(t,{start:.3f},{end - 0.001:.3f})'[{label}]")
            last = label
        chain.append(f"[{last}]format=yuv420p,setsar=1[out]")
        cmd += ["-filter_complex", ";".join(chain), "-map", "[out]", "-an", "-r", str(FPS),
                "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p",
                "-movflags", "+faststart", "-t", f"{info['duration']:.3f}", str(out)]
        run(cmd)
    return out


def self_test(keep_dir=None):
    work = Path(keep_dir) if keep_dir else Path(tempfile.mkdtemp(prefix="compose_selftest_"))
    work.mkdir(parents=True, exist_ok=True)
    raw = work / "raw.mp4"
    run([FFMPEG, "-y", "-v", "error", "-f", "lavfi", "-i", "testsrc=size=390x844:rate=30:duration=9",
         "-c:v", "libx264", "-pix_fmt", "yuv420p", str(raw)])
    steps = work / "steps.json"
    steps.write_text(json.dumps({"title": "Novo cadastro: do início ao fim", "steps": [
        {"start": 0, "text": "Abre o app e toca em Começar"},
        {"start": 3, "text": "Preenche nome e e-mail; e-mail já em uso mostra o erro"},
        {"start": 6, "text": "Tenta de novo e chega no quadro da criança"}]}), encoding="utf-8")
    final = compose(raw, steps, work / "final.mp4")
    src, got = probe(raw), probe(final)
    assert (got["width"], got["height"]) == (W, H), f"size {got['width']}x{got['height']}"
    assert got["sar"] in ("1:1", "N/A"), f"SAR {got['sar']}"
    assert abs(got["duration"] - src["duration"]) <= 0.2, f"duration {got['duration']} vs {src['duration']}"
    bad = work / "unsorted.txt"
    bad.write_text("0 a\n5 b\n2 c\n", encoding="utf-8")
    for case, args in (("unsorted", (raw, bad)), ("missing video", (work / "nope.mp4", steps))):
        try:
            compose(*args, out=work / "x.mp4")
        except InputError:
            continue
        raise AssertionError(f"{case} input was accepted")
    late = work / "late.txt"
    late.write_text("title: t\n0 a\n0:30 b\n", encoding="utf-8")
    try:
        compose(raw, late, work / "x.mp4")
        raise AssertionError("step beyond duration was accepted")
    except InputError:
        pass
    frames = []
    for t in (1.5, 4.5, 7.5):
        f = work / f"frame_{t:.1f}s.png"
        run([FFMPEG, "-y", "-v", "error", "-ss", str(t), "-i", str(final), "-frames:v", "1", str(f)])
        frames.append(f)
    print(f"SELF-TEST OK {got['width']}x{got['height']} SAR {got['sar']} "
          f"duration {got['duration']:.2f}s (input {src['duration']:.2f}s)")
    print(f"final: {final}")
    for f in frames:
        print(f"frame: {f}")


def main():
    ap = argparse.ArgumentParser(description="Compose a 1920x1080 review video: step list on the left, "
                                             "the phone recording in an iPhone frame on the right.")
    ap.add_argument("--video", help="raw portrait screencast (390x844 ratio)")
    ap.add_argument("--steps", help="steps file: JSON {title, steps:[{start, text}]} or text lines '<s|mm:ss> -> caption'")
    ap.add_argument("--out", help="output mp4")
    ap.add_argument("--title", help="title above the steps (overrides the steps file)")
    ap.add_argument("--self-test", action="store_true", help="compose a synthetic clip and check the result")
    ap.add_argument("--self-test-dir", help="keep self-test files here")
    a = ap.parse_args()
    try:
        if a.self_test:
            self_test(a.self_test_dir)
            return 0
        if not (a.video and a.steps and a.out):
            ap.error("--video, --steps and --out are required")
        out = compose(a.video, a.steps, a.out, a.title)
        info = probe(out)
        print(f"OK {out} {info['width']}x{info['height']} SAR {info['sar']} {info['duration']:.2f}s")
        return 0
    except InputError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    except (RuntimeError, AssertionError) as e:
        print(f"FAILED: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
