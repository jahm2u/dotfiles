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


MAX_STILL = 1.5      # a still stretch longer than this is cut down to it (0 = keep all)
STILL_HEAD, STILL_TAIL = 0.6, 0.9   # what is kept of it: the start (a ring appears) and the end (the tap)
CHANGED_LEVEL, CHANGED_PIXELS = 10, 3   # a frame moves when more than 3 of its 96x96 grey pixels change by >10


def frame_changes(video, fps, vf_prefix=""):
    """Per sampled frame, how many pixels of a 96x96 grey copy changed since the previous one.
    A count, not a mean: a chip changing colour or a 44 px tap ring is a few dozen pixels,
    lost in a whole-frame average (2026-10-19: three chip taps were cut as still)."""
    sw = sh = 96
    raw = subprocess.run([FFMPEG, "-v", "error", "-i", str(video), "-vf",
                          f"{vf_prefix}fps={fps},scale={sw}:{sh},format=gray", "-f", "rawvideo", "-"],
                         capture_output=True, check=True).stdout
    n = len(raw) // (sw * sh)
    frames = [raw[i * sw * sh:(i + 1) * sw * sh] for i in range(n)]
    return [0] + [sum(abs(a - b) > CHANGED_LEVEL for a, b in zip(frames[i - 1], frames[i])) for i in range(1, n)]


def still_segments(video, duration, max_still=MAX_STILL, fps=10):
    """Spans of the recording to keep. An agent's recording sits still for 10-20 s while it
    thinks between taps (2026-10-19: a 10-step flow came out at 121 s); each still stretch
    longer than max_still keeps its first STILL_HEAD and last STILL_TAIL seconds."""
    if not max_still or max_still <= 0:
        return [(0.0, duration)]
    changes = frame_changes(video, fps)
    n = len(changes)
    still = [i > 0 and c <= CHANGED_PIXELS for i, c in enumerate(changes)]
    head, tail = min(STILL_HEAD, max_still / 2), min(STILL_TAIL, max_still / 2)
    cuts, i = [], 0
    while i < n:
        if not still[i]:
            i += 1
            continue
        j = i
        while j < n and still[j]:
            j += 1
        a, b = (i - 1) / fps, min(j / fps, duration)
        if b - a > max_still:
            cuts.append((a + head, b - tail))
        i = j
    keep, t = [], 0.0
    for a, b in cuts:
        if a > t:
            keep.append((t, a))
        t = b
    if t < duration:
        keep.append((t, duration))
    return keep or [(0.0, duration)]


def remap(t, keep):
    """A time in the recording -> its time after the cuts (a cut-out moment maps to where
    the next kept span starts)."""
    out = 0.0
    for a, b in keep:
        if t < a:
            return out
        if t <= b:
            return out + t - a
        out += b - a
    return out


def remap_steps(steps, keep):
    out = []
    for t, text in steps:
        nt = remap(t, keep)
        if out and nt < out[-1][0] + 0.3:   # two steps inside one cut stay apart
            nt = out[-1][0] + 0.3
        out.append((nt, text))
    return out


def retime(blend=True):
    """Filter that turns the recording into FPS constant frames. The DevTools screencast sends a
    frame only when Chrome repaints, at 3-30 fps depending on the run (2026-10-19: ~3 fps, every
    ring and screen change in 2-3 jumps). Plain fps= repeats frames, so it jumps; framerate=
    blends neighbouring frames instead, so each jump becomes a short dissolve."""
    if blend:
        return f"framerate=fps={FPS}:interp_start=0:interp_end=255:scene=100"
    return f"fps={FPS}"


def keep_filter(keep, duration):
    """Filter chain fragment that keeps only the spans, retimed to run back to back."""
    if keep == [(0.0, duration)]:
        return ""
    expr = "+".join(f"between(t,{a:.3f},{b:.3f})" for a, b in keep)
    return f",select='{expr}',setpts=N/{FPS}/TB"


def own_status_bar(video, duration):
    """True when the recording already carries the phone's status bar: a device or Simulator
    capture (1206x2622) has its own clock and Dynamic Island, a DevTools screencast (390x844)
    has neither. Drawing ours on top of a device capture showed the top twice (Jeff, 2026-10-19).
    Looks for the island: a pure-black pill centred in the top band, with non-black either side."""
    sw = 300
    for t in (min(0.5, duration / 2), duration / 2):
        raw = subprocess.run([FFMPEG, "-v", "error", "-ss", f"{t:.2f}", "-i", str(video), "-frames:v", "1",
                              "-vf", f"scale={sw}:-2,format=gray", "-f", "rawvideo", "-"], capture_output=True).stdout
        sh = len(raw) // sw
        if not sh:
            continue
        for y in range(int(sh * 0.01), int(sh * 0.05) + 1):
            row = raw[y * sw:(y + 1) * sw]
            if row[sw // 2] > 12:
                continue
            l = r = sw // 2
            while l > 0 and row[l - 1] <= 12:
                l -= 1
            while r < sw - 1 and row[r + 1] <= 12:
                r += 1
            if 0.2 * sw <= r - l <= 0.45 * sw and abs((l + r) / 2 - sw / 2) <= sw * 0.03 and l > 0 and r < sw - 1:
                return True
    return False


WINDOW_ROWS = 5      # at most this many steps on screen; longer lists slide
SLIDE_S = 0.45       # how long the list takes to slide one row
FADE_PX = 48         # edge fade when steps are hidden above or below
PT_HINT = re.compile(r"[ãõçáéíóúâêôà]|\b(de|da|pra|para|com|não|nao|toca|abre|volta|e)\b", re.I)


def counter_text(current, n, lang, steps):
    if lang == "auto":
        lang = "pt" if any(PT_HINT.search(t) for _, t in steps) else "en"
    return f"Passo {current + 1} de {n}" if lang == "pt" else f"Step {current + 1} of {n}"


def window_start(current, n):
    """First visible row: the step just done stays above the current one, and the window
    stops at the last WINDOW_ROWS instead of leaving empty rows."""
    return max(0, min(current - 1, n - WINDOW_ROWS))


def layout_window(title, steps):
    probe_img = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    panel_h = PANEL_BOTTOM - PANEL_TOP
    for size in range(40, 19, -2):
        title_f = font("bold", int(size * 1.4))
        step_f = font("demi", size)
        text_w = PANEL_W - int(size * 2.2)
        title_lines = wrap(probe_img, title, title_f, PANEL_W) if title else []
        title_h = len(title_lines) * int(size * 1.4 * 1.2)
        counter_h = int(size * 1.5)
        head_h = title_h + counter_h + int(size * 1.6)
        blocks = [wrap(probe_img, text, step_f, text_w) for _, text in steps]
        line_h = int(size * 1.35)
        gap = int(size * 0.9)
        slot = max(len(b) for b in blocks) * line_h + gap
        if head_h + WINDOW_ROWS * slot <= panel_h:
            return {"size": size, "title_f": title_f, "step_f": step_f, "title_lines": title_lines,
                    "title_h": title_h, "counter_h": counter_h, "head_h": head_h, "blocks": blocks,
                    "line_h": line_h, "gap": gap, "slot": slot,
                    "top": PANEL_TOP + max(0, (panel_h - head_h - WINDOW_ROWS * slot) // 2)}
    raise InputError("captions too long to fit the left panel; shorten them")


def draw_step(d, i, current, block, y, L, reg_f, num_f):
    size, line_h, gap, step_f = L["size"], L["line_h"], L["gap"], L["step_f"]
    r = int(size * 0.62)
    cy, cx = y + line_h // 2, r
    block_h = len(block) * line_h
    if i == current:
        d.rounded_rectangle((0, y - gap // 3, PANEL_W + 30, y + block_h + gap // 3),
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


def render_window(title, steps, outdir, lang):
    """Per step: a strip with every row (current one highlighted) and a full-height mask that
    is opaque background except the 5-row window, carrying title, counter and edge fades.
    The strip slides under the mask; nothing outside the window shows."""
    L = layout_window(title, steps)
    n, size, slot = len(steps), L["size"], L["slot"]
    reg_f, num_f = font("regular", size), font("bold", int(size * 0.62))
    cnt_f = font("demi", int(size * 0.8))
    win_y = L["top"] + L["head_h"]
    win_h = WINDOW_ROWS * slot
    out = []
    for current in range(n):
        strip = Image.new("RGBA", (PANEL_W + 40, n * slot), (0, 0, 0, 0))
        d = ImageDraw.Draw(strip)
        for i, block in enumerate(L["blocks"]):
            draw_step(d, i, current, block, i * slot + L["gap"] // 2, L, reg_f, num_f)
        sp = outdir / f"strip_{current:02d}.png"
        strip.save(sp)
        mask = Image.new("RGBA", (PANEL_W + 40, H), BG + (255,))
        d = ImageDraw.Draw(mask)
        y = L["top"]
        for line in L["title_lines"]:
            d.text((0, y), line, font=L["title_f"], fill=INK)
            y += int(size * 1.4 * 1.2)
        d.text((0, y + int(size * 0.2)), counter_text(current, n, lang, steps), font=cnt_f, fill=DONE)
        y += L["counter_h"] + int(size * 0.3)
        d.rounded_rectangle((0, y, 72, y + 6), radius=3, fill=ACCENT)
        mask.paste((0, 0, 0, 0), (0, win_y, PANEL_W + 40, win_y + win_h))
        ws = window_start(current, n)
        for k in range(FADE_PX):
            a = round(255 * (1 - k / FADE_PX))
            if ws > 0:
                d.line([(0, win_y + k), (PANEL_W + 40, win_y + k)], fill=BG + (a,))
            if ws + WINDOW_ROWS < n:
                d.line([(0, win_y + win_h - 1 - k), (PANEL_W + 40, win_y + win_h - 1 - k)], fill=BG + (a,))
        mp = outdir / f"mask_{current:02d}.png"
        mask.save(mp)
        out.append((sp, mp))
    return out, win_y, slot


def panel_overlays(title, steps, duration, outdir, idx, last, lang="auto"):
    """The step panel as ffmpeg inputs + filter chain on top of stream `last`.
    Returns (input args, chain, new last label). Up to WINDOW_ROWS steps: one still per step.
    More: a sliding window (see render_window), eased over SLIDE_S at each step change."""
    inputs, chain = [], []
    ends = [steps[i + 1][0] if i + 1 < len(steps) else duration + 10 for i in range(len(steps))]
    starts = [0.0] + [t for t, _ in steps[1:]]
    if len(steps) <= WINDOW_ROWS:
        for i, p in enumerate(render_panels(title, steps, outdir)):
            inputs += ["-i", str(p)]
            chain.append(f"[{last}][{idx}:v]overlay={PANEL_X}:{PANEL_TOP}:"
                         f"enable='between(t,{starts[i]:.3f},{ends[i] - 0.001:.3f})'[p{i}]")
            last, idx = f"p{i}", idx + 1
        return inputs, chain, last
    layers, win_y, slot = render_window(title, steps, outdir, lang)
    n = len(steps)
    for i, (sp, mp) in enumerate(layers):
        a = window_start(i - 1, n) * slot if i else 0
        b = window_start(i, n) * slot
        tc = starts[i]
        y = (f"{win_y}-({a}+({b - a})*st(0,clip((t-{tc:.3f})/{SLIDE_S},0,1))"
             f"*ld(0)*(3-2*ld(0)))")
        en = f"between(t,{starts[i]:.3f},{ends[i] - 0.001:.3f})"
        inputs += ["-i", str(sp), "-i", str(mp)]
        chain.append(f"[{last}][{idx}:v]overlay=x={PANEL_X}:y='{y}':eval=frame:enable='{en}'[s{i}]")
        chain.append(f"[s{i}][{idx + 1}:v]overlay=x={PANEL_X}:y=0:enable='{en}'[p{i}]")
        last, idx = f"p{i}", idx + 2
    return inputs, chain, last


def phone_geometry(vw, vh, status_h=STATUS_H):
    screen_h = PHONE_OUTER_H - 2 * BEZEL
    video_h = even(screen_h - status_h)
    video_w = even(video_h * vw / vh)
    screen_h = video_h + status_h
    screen_w = video_w
    outer_w = screen_w + 2 * BEZEL
    outer_h = screen_h + 2 * BEZEL
    ox = PHONE_CX - outer_w // 2
    oy = (H - outer_h) // 2
    sx, sy = ox + BEZEL, oy + BEZEL
    return {"outer": (ox, oy, ox + outer_w, oy + outer_h), "screen": (sx, sy, sx + screen_w, sy + screen_h),
            "video": (sx, sy + status_h, video_w, video_h), "status_h": status_h}


def render_background(g, path):
    img = Image.new("RGB", (W, H), BG)
    sx, sy, sx2, sy2 = g["screen"]
    if g["status_h"]:
        ImageDraw.Draw(img).rectangle((sx, sy, sx2, sy + g["status_h"] + 2), fill=(255, 255, 255))
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
    if not g["status_h"]:
        img.save(path)
        return
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


def status_height(video, duration, status_bar="auto"):
    if status_bar == "auto":
        status_bar = "none" if own_status_bar(video, duration) else "draw"
    return STATUS_H if status_bar == "draw" else 0


def compose(video, steps_path, out, title=None, status_bar="auto", lang="auto", max_still=MAX_STILL, blend=True):
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
    keep = still_segments(video, info["duration"], max_still)
    steps = remap_steps(steps, keep)
    duration = sum(b - a for a, b in keep)
    num, den = (int(x) for x in (info["sar"] if re.fullmatch(r"\d+:\d+", info["sar"]) and info["sar"] != "0:1" else "1:1").split(":"))
    g = phone_geometry(info["width"] * num / den, info["height"], status_height(video, info["duration"], status_bar))
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="compose_phone_") as td:
        td = Path(td)
        bg, frame = td / "bg.png", td / "frame.png"
        render_background(g, bg)
        render_frame(g, frame)
        vx, vy, vw, vh = g["video"]
        cmd = [FFMPEG, "-y", "-v", "error", "-loop", "1", "-framerate", str(FPS), "-i", str(bg),
               "-i", str(video), "-i", str(frame)]
        chain = [f"[1:v]setpts=PTS-STARTPTS,{retime(blend)}{keep_filter(keep, info['duration'])},"
                 f"scale={vw}:{vh}:flags=lanczos,setsar=1[rec]",
                 f"[0:v][rec]overlay={vx}:{vy}:shortest=1[a0]",
                 "[a0][2:v]overlay=0:0[b0]"]
        inputs, more, last = panel_overlays(title, steps, duration, td, 3, "b0", lang)
        cmd += inputs
        chain += more
        chain.append(f"[{last}]format=yuv420p,setsar=1[out]")
        cmd += ["-filter_complex", ";".join(chain), "-map", "[out]", "-an", "-r", str(FPS),
                "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p",
                "-movflags", "+faststart", "-t", f"{duration:.3f}", str(out)]
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
    frames = []
    assert (got["width"], got["height"]) == (W, H), f"size {got['width']}x{got['height']}"
    assert got["sar"] in ("1:1", "N/A"), f"SAR {got['sar']}"
    assert abs(got["duration"] - src["duration"]) <= 0.2, f"duration {got['duration']} vs {src['duration']}"
    long_steps = work / "long.txt"
    long_steps.write_text("title: Lista longa\n" + "".join(f"{i * 0.7:.1f} -> Passo número {i + 1} do fluxo\n"
                                                         for i in range(12)), encoding="utf-8")
    long_final = compose(raw, long_steps, work / "long.mp4")
    got_long = probe(long_final)
    assert (got_long["width"], got_long["height"]) == (W, H) and abs(got_long["duration"] - src["duration"]) <= 0.2
    assert [window_start(c, 12) for c in range(12)] == [0, 0, 1, 2, 3, 4, 5, 6, 7, 7, 7, 7]
    assert counter_text(2, 12, "auto", [(0, "Abre o app")]) == "Passo 3 de 12"
    assert counter_text(2, 12, "auto", [(0, "Open the app")]) == "Step 3 of 12"
    for t in (0.3, 4.4, 8.6):
        f = work / f"long_{t:.1f}s.png"
        run([FFMPEG, "-y", "-v", "error", "-ss", str(t), "-i", str(long_final), "-frames:v", "1", str(f)])
        frames.append(f)
    paused = work / "paused.mp4"   # 2 s moving, 6 s still (an agent thinking), 2 s moving
    run([FFMPEG, "-y", "-v", "error", "-f", "lavfi", "-i", "testsrc=size=390x844:rate=30:duration=2",
         "-f", "lavfi", "-i", "color=c=0xfbf3e4:size=390x844:rate=30:duration=6",
         "-f", "lavfi", "-i", "testsrc=size=390x844:rate=30:duration=2",
         "-filter_complex", "[0:v][1:v][2:v]concat=n=3:v=1[v]", "-map", "[v]",
         "-c:v", "libx264", "-pix_fmt", "yuv420p", str(paused)])
    keep = still_segments(paused, probe(paused)["duration"])
    assert abs(sum(b - a for a, b in keep) - 5.5) <= 0.25, f"kept {keep}"
    assert abs(remap(9.0, keep) - 4.5) <= 0.25 and abs(remap(4.0, keep) - remap(6.0, keep)) <= 0.01
    pst = work / "paused.txt"
    pst.write_text("0 -> mexe\n2.2 -> parado\n8.5 -> mexe de novo\n", encoding="utf-8")
    got_p = probe(compose(paused, pst, work / "paused_final.mp4"))
    assert abs(got_p["duration"] - 5.5) <= 0.25, f"paused final {got_p['duration']}"
    assert abs(probe(compose(paused, pst, work / "x.mp4", max_still=0))["duration"] - 10) <= 0.2
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
    ap.add_argument("--status-bar", choices=["auto", "draw", "none"], default="auto",
                    help="draw our status bar above the recording; auto skips it when the recording has its own")
    ap.add_argument("--lang", choices=["auto", "pt", "en"], default="auto",
                    help="language of the 'Passo 3 de 12' / 'Step 3 of 12' counter shown past 5 steps")
    ap.add_argument("--no-blend", action="store_true",
                    help="repeat frames instead of blending between them (blending smooths a low-fps screencast)")
    ap.add_argument("--max-still", type=float, default=MAX_STILL,
                    help=f"cut still stretches longer than this many seconds down to it (default {MAX_STILL}; 0 keeps all)")
    ap.add_argument("--self-test", action="store_true", help="compose a synthetic clip and check the result")
    ap.add_argument("--self-test-dir", help="keep self-test files here")
    a = ap.parse_args()
    try:
        if a.self_test:
            self_test(a.self_test_dir)
            return 0
        if not (a.video and a.steps and a.out):
            ap.error("--video, --steps and --out are required")
        out = compose(a.video, a.steps, a.out, a.title, a.status_bar, a.lang, a.max_still, not a.no_blend)
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
