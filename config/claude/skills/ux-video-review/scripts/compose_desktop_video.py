#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import compose_phone_video as cpv

cpv.PANEL_X = 64
cpv.PANEL_W = 520
cpv.PHONE_CX = 1250

W, H, FPS, BG = cpv.W, cpv.H, cpv.FPS, cpv.BG
InputError = cpv.InputError

AREA_X0, AREA_X1 = 640, 1880
BAR_H = 34
CARD_R = 14
ZOOM_S = 0.8
FOCUS_MIN = 0.4
FOCUS_PAD = 1.3
OPENING_S = 2.5
NUM = r"(-?\d+(?:\.\d+)?)"
FOCUS_RE = re.compile(r"\s*@\s*" + r"\s*,\s*".join([NUM] * 4) + r"\s*$")


def parse_focus(value, i):
    if not isinstance(value, (list, tuple)) or len(value) != 4:
        raise InputError(f"step {i}: focus must be [x, y, w, h], got {value!r}")
    try:
        x, y, w, h = (float(v) for v in value)
    except (TypeError, ValueError):
        raise InputError(f"step {i}: focus must be four numbers, got {value!r}")
    if w <= 0 or h <= 0:
        raise InputError(f"step {i}: focus width and height must be > 0, got {value!r}")
    return x, y, w, h


def load_steps(path):
    """Steps as compose_phone_video.py reads them, plus an optional focus rectangle per step in
    raw-recording pixels: `0:12 -> caption @ x,y,w,h` or JSON `"focus": [x, y, w, h]`."""
    title, steps = cpv.load_steps(path)
    raw = Path(path).read_text(encoding="utf-8")
    focus = [None] * len(steps)
    if raw.lstrip().startswith(("{", "[")):
        data = json.loads(raw)
        items = data.get("steps") if isinstance(data, dict) else data
        for i, item in enumerate(items):
            if isinstance(item, dict) and item.get("focus") is not None:
                focus[i] = parse_focus(item["focus"], i + 1)
    out = []
    for i, (t, text) in enumerate(steps):
        m = FOCUS_RE.search(text)
        if m:
            if focus[i] is None:
                focus[i] = parse_focus(m.groups(), i + 1)
            text = text[:m.start()].strip()
            if not text:
                raise InputError(f"step {i + 1}: a focus needs a caption before the @")
        out.append((t, text))
    return title, out, focus


def focus_box(rect, fw, fh, i):
    """The rectangle the card zooms to: the focus padded, at the frame's aspect, never tighter
    than FOCUS_MIN of the frame, moved inside it."""
    x, y, w, h = rect
    x0, y0, x1, y1 = max(0.0, x), max(0.0, y), min(fw, x + w), min(fh, y + h)
    if x1 <= x0 or y1 <= y0:
        raise InputError(f"step {i}: focus {rect} is outside the {fw:g}x{fh:g} recording")
    aspect = fw / fh
    bw = min(fw, max((x1 - x0) * FOCUS_PAD, (y1 - y0) * FOCUS_PAD * aspect, fw * FOCUS_MIN))
    bh = bw / aspect
    bx = min(max((x0 + x1) / 2 - bw / 2, 0.0), fw - bw)
    by = min(max((y0 + y1) / 2 - bh / 2, 0.0), fh - bh)
    return bx, by, bw, bh


def ease(x):
    return f"(pow(clip({x},0,1),2)*(3-2*clip({x},0,1)))"


def zoom_filter(windows, fw, fh):
    """perspective filter that eases the full view into each window's box over ZOOM_S, holds it
    and eases back out over the window's last ZOOM_S. Sub-pixel, so the zoom never jitters."""
    if not windows:
        return ""
    t = f"(in/{FPS})"
    terms = [(f"{ease(f'({t}-{a:.3f})/{ZOOM_S}')}*{ease(f'({b:.3f}-{t})/{ZOOM_S}')}", box) for a, b, box in windows]

    def corner(base, delta):
        return f"{base:.3f}" + "".join(f"+{p}*({delta(box):.3f})" for p, box in terms)

    left = corner(0, lambda b: b[0])
    right = corner(fw, lambda b: b[0] + b[2] - fw)
    top = corner(0, lambda b: b[1])
    bottom = corner(fh, lambda b: b[1] + b[3] - fh)
    en = "+".join(f"between(n,{int(a * FPS) - 1},{int(b * FPS) + 1})" for a, b, _ in windows)
    return (f",perspective=x0='{left}':y0='{top}':x1='{right}':y1='{top}':x2='{left}':y2='{bottom}':"
            f"x3='{right}':y3='{bottom}':interpolation=cubic:sense=source:eval=frame:enable='{en}'")


def merge_spans(spans):
    out = []
    for a, b in sorted(spans):
        if out and a <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], b))
        else:
            out.append((a, b))
    return out


def desktop_geometry(vw, vh):
    max_w = AREA_X1 - AREA_X0
    max_h = H - 80 - BAR_H
    scale = min(max_w / vw, max_h / vh)
    video_w, video_h = cpv.even(vw * scale), cpv.even(vh * scale)
    cx = (AREA_X0 + AREA_X1) // 2
    ox = cx - video_w // 2
    oy = (H - video_h - BAR_H) // 2
    return {"card": (ox, oy, ox + video_w, oy + BAR_H + video_h), "video": (ox, oy + BAR_H, video_w, video_h)}


def render_desktop_background(g, path):
    img = Image.new("RGBA", (W, H), BG + (255,))
    x0, y0, x1, y1 = g["card"]
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((x0 + 10, y0 + 18, x1 + 10, y1 + 18), radius=CARD_R, fill=80)
    img.paste((70, 74, 86, 255), (0, 0), shadow.filter(ImageFilter.GaussianBlur(24)))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((x0 - 1, y0 - 1, x1 + 1, y1 + 1), radius=CARD_R, fill=(208, 212, 220))
    d.rounded_rectangle((x0, y0, x1, y1), radius=CARD_R, fill=(232, 234, 239))
    d.rectangle((x0, y0 + BAR_H - 1, x1, y0 + BAR_H), fill=(208, 212, 220))
    for i, color in enumerate(((255, 95, 87), (254, 188, 46), (40, 200, 64))):
        cx, cy = x0 + 22 + i * 22, y0 + BAR_H // 2
        d.ellipse((cx - 6, cy - 6, cx + 6, cy + 6), fill=color)
    img.convert("RGB").save(path)


def clip_info(path):
    path = Path(path)
    if not path.is_file():
        raise InputError(f"video not found: {path}")
    info = cpv.probe(path)
    if info["duration"] <= 0:
        raise InputError(f"{path}: could not read a duration")
    sar = info["sar"] if re.fullmatch(r"\d+:\d+", info["sar"]) and info["sar"] != "0:1" else "1:1"
    num, den = (int(x) for x in sar.split(":"))
    info["dw"] = info["width"] * num / den
    info["phone"] = info["dw"] < info["height"]
    info["path"] = path
    return info


def compose(videos, steps_path, out, title=None, status_bar="auto", lang="auto", max_still=cpv.MAX_STILL, blend=True):
    if not videos:
        raise InputError("give at least one --video")
    clips = [clip_info(v) for v in videos]
    file_title, steps, focus = load_steps(steps_path)
    title = title if title is not None else file_title
    total = sum(c["duration"] for c in clips)
    over = [(i + 1, t) for i, (t, _) in enumerate(steps) if t >= total]
    if over:
        i, t = over[0]
        raise InputError(f"step {i} starts at {t:g}s, at or beyond the clips' {total:.2f}s")
    raw_ends = [steps[i + 1][0] if i + 1 < len(steps) else total for i in range(len(steps))]
    offset, new_offset, joined = 0.0, 0.0, []
    for c in clips:
        held = [(max(s, offset) - offset, min(e, offset + c["duration"]) - offset)
                for (s, _), e, f in zip(steps, raw_ends, focus) if f and s < offset + c["duration"] and e > offset]
        c["keep"] = merge_spans(cpv.still_segments(c["path"], c["duration"], max_still) + held)
        c["new"] = sum(b - a for a, b in c["keep"])
        c["offset"] = new_offset
        c["windows"] = []
        joined += [(offset + a, offset + b) for a, b in c["keep"]]
        offset += c["duration"]
        new_offset += c["new"]
    steps = cpv.remap_steps(steps, joined)
    total = sum(c["new"] for c in clips)
    lead = max(0.0, OPENING_S - steps[0][0]) if focus[0] else 0.0
    ends = [steps[i + 1][0] if i + 1 < len(steps) else total for i in range(len(steps))]
    for i, ((s, _), e, f) in enumerate(zip(steps, ends, focus)):
        if not f:
            continue
        c = next(c for c in reversed(clips) if c["offset"] <= s)
        if c["phone"]:
            raise InputError(f"step {i + 1} has a focus but plays on the phone clip {c['path'].name}")
        box = focus_box(f, c["width"], c["height"], i + 1)
        a, b = s - c["offset"], min(e - c["offset"], c["new"])
        if c is clips[0]:
            a, b = a + lead, b + lead
        c["windows"].append((a, b, box))
    if lead:
        clips[0]["new"] += lead
        steps = [(t + lead if i else t, text) for i, (t, text) in enumerate(steps)]
        total += lead
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="compose_desktop_") as td:
        td = Path(td)
        cmd = [cpv.FFMPEG, "-y", "-v", "error"]
        chain, idx, seg = [], 0, []
        for n, c in enumerate(clips):
            if c["phone"]:
                g = cpv.phone_geometry(c["dw"], c["height"], cpv.status_height(c["path"], c["duration"], status_bar))
                bg, frame = td / f"bg{n}.png", td / f"frame{n}.png"
                cpv.render_background(g, bg)
                cpv.render_frame(g, frame)
                vx, vy, vw, vh = g["video"]
            else:
                g = desktop_geometry(c["dw"], c["height"])
                bg, frame = td / f"bg{n}.png", None
                render_desktop_background(g, bg)
                vx, vy, vw, vh = g["video"]
            pad = f",tpad=start_duration={lead:.3f}:start_mode=clone" if lead and n == 0 else ""
            cmd += ["-loop", "1", "-framerate", str(FPS), "-t", f"{c['new']:.3f}", "-i", str(bg),
                    "-i", str(c["path"])]
            b, v = idx, idx + 1
            idx += 2
            chain.append(f"[{v}:v]setpts=PTS-STARTPTS,{cpv.retime(blend)}{cpv.keep_filter(c['keep'], c['duration'])}"
                         f"{pad}{zoom_filter(c['windows'], c['width'], c['height'])},"
                         f"scale={vw}:{vh}:flags=lanczos,setsar=1[r{n}]")
            chain.append(f"[{b}:v][r{n}]overlay={vx}:{vy}:shortest=1,trim=duration={c['new']:.3f},"
                         f"setpts=PTS-STARTPTS[s{n}a]")
            last = f"s{n}a"
            if frame:
                cmd += ["-i", str(frame)]
                chain.append(f"[{last}][{idx}:v]overlay=0:0[s{n}b]")
                idx += 1
                last = f"s{n}b"
            chain.append(f"[{last}]format=yuv420p,setsar=1[s{n}]")
            seg.append(f"[s{n}]")
        chain.append(f"{''.join(seg)}concat=n={len(seg)}:v=1:a=0[cat]")
        inputs, more, last = cpv.panel_overlays(title, steps, total, td, idx, "cat", lang)
        cmd += inputs
        chain += more
        chain.append(f"[{last}]format=yuv420p,setsar=1[out]")
        cmd += ["-filter_complex", ";".join(chain), "-map", "[out]", "-an", "-r", str(FPS),
                "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p",
                "-movflags", "+faststart", "-t", f"{total:.3f}", str(out)]
        cpv.run(cmd)
    return out


def card_track(video, fw, fh):
    """Per output frame of a composed gradient clip (grey = source x), the zoom scale and the
    left edge, both as fractions of the full view, read off the card's middle row."""
    vx, vy, vw, vh = desktop_geometry(fw, fh)["video"]
    raw = subprocess.run([cpv.FFMPEG, "-v", "error", "-i", str(video), "-vf",
                          f"crop={vw}:2:{vx}:{vy + vh // 2},format=gray", "-f", "rawvideo", "-"],
                         capture_output=True, check=True).stdout
    rows = [raw[i * 2 * vw:(i * 2 + 1) * vw] for i in range(len(raw) // (2 * vw))]
    edges = [(sum(r[4:8]) / 4, sum(r[vw - 8:vw - 4]) / 4) for r in rows]
    full = edges[0][1] - edges[0][0]
    return [(full / (r - l), (l - edges[0][0]) / full) for l, r in edges]


def check_smooth(name, track, max_scale_step=0.08, max_move_step=0.06):
    for i in range(1, len(track)):
        ds = abs(track[i][0] - track[i - 1][0]) / track[i - 1][0]
        dx = abs(track[i][1] - track[i - 1][1])
        assert ds <= max_scale_step, f"{name}: scale jumps {ds:.1%} at frame {i} ({i / FPS:.2f}s)"
        assert dx <= max_move_step, f"{name}: view moves {dx:.1%} at frame {i} ({i / FPS:.2f}s)"


def self_test(keep_dir=None):
    work = Path(keep_dir) if keep_dir else Path(tempfile.mkdtemp(prefix="compose_desktop_selftest_"))
    work.mkdir(parents=True, exist_ok=True)
    desk, phone = work / "desk.mp4", work / "phone.mp4"
    cpv.run([cpv.FFMPEG, "-y", "-v", "error", "-f", "lavfi", "-i", "testsrc=size=1440x900:rate=30:duration=5",
             "-c:v", "libx264", "-pix_fmt", "yuv420p", str(desk)])
    cpv.run([cpv.FFMPEG, "-y", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=390x844:rate=30:duration=4",
             "-c:v", "libx264", "-pix_fmt", "yuv420p", str(phone)])
    steps = work / "steps.json"
    steps.write_text(json.dumps({"title": "Offer branding", "steps": [
        {"start": 0, "text": "Open an offer in the admin"},
        {"start": 2.5, "text": "Set brand, bonus and logo"},
        {"start": 5.5, "text": "The lander picks them up on a phone"}]}), encoding="utf-8")
    results = []
    for name, vids, st in (("desktop", [desk], None), ("mixed", [desk, phone], steps)):
        s = st
        if s is None:
            s = work / "steps_desk.txt"
            s.write_text("title: Desktop only\n0 -> One\n2 -> Two\n", encoding="utf-8")
        final = compose(vids, s, work / f"{name}.mp4")
        got = cpv.probe(final)
        want = sum(cpv.probe(v)["duration"] for v in vids)
        assert (got["width"], got["height"]) == (W, H), f"{name}: size {got['width']}x{got['height']}"
        assert got["sar"] in ("1:1", "N/A"), f"{name}: SAR {got['sar']}"
        assert abs(got["duration"] - want) <= 0.25, f"{name}: duration {got['duration']} vs {want}"
        results.append((name, final, got))
    late = work / "late.txt"
    late.write_text("title: t\n0 a\n0:30 b\n", encoding="utf-8")
    for case, args in (("step beyond duration", ([desk], late)), ("missing video", ([work / "nope.mp4"], steps)),
                       ("no video", ([], steps))):
        try:
            compose(*args, out=work / "x.mp4")
        except InputError:
            continue
        raise AssertionError(f"{case} input was accepted")
    ft, fj = work / "focus.txt", work / "focus.json"
    ft.write_text("title: Focus\n0 -> Whole page\n0:02 -> Suggested panel @ 820,140,560,380\n6 -> Back\n",
                  encoding="utf-8")
    fj.write_text(json.dumps({"title": "Focus", "steps": [
        {"start": 0, "text": "Whole page"},
        {"start": 2, "text": "Suggested panel", "focus": [820, 140, 560, 380]},
        [6, "Back"]]}), encoding="utf-8")
    for f in (ft, fj):
        got_steps = load_steps(f)
        assert got_steps == ("Focus", [(0.0, "Whole page"), (2.0, "Suggested panel"), (6.0, "Back")],
                             [None, (820.0, 140.0, 560.0, 380.0), None]), f"{f.name}: parsed {got_steps}"
    bx, by, bw, bh = focus_box((820, 140, 560, 380), 1440, 900, 1)
    assert bx <= 820 and by <= 140 and bx + bw >= 1380 and by + bh >= 520, f"focus box {bx, by, bw, bh} cuts the focus"
    assert bx >= 0 and by >= 0 and bx + bw <= 1440 and by + bh <= 900, f"focus box {bx, by, bw, bh} leaves the frame"
    bw, bh = focus_box((700, 400, 10, 10), 1440, 900, 1)[2:]
    assert bw >= 1440 * FOCUS_MIN and abs(bw / bh - 1.6) < 1e-9, f"tiny focus box {bw}x{bh}"
    grad_png, grad = work / "grad.png", work / "grad.mp4"
    img = Image.new("L", (1440, 900))
    img.putdata([round(255 * x / 1439) for _ in range(900) for x in range(1440)])
    img.save(grad_png)
    cpv.run([cpv.FFMPEG, "-y", "-v", "error", "-loop", "1", "-framerate", "30", "-t", "9", "-i", str(grad_png),
             "-c:v", "libx264", "-pix_fmt", "yuv420p", str(grad)])
    zoomed = compose([grad], ft, work / "focus.mp4")
    got_z = cpv.probe(zoomed)
    assert abs(got_z["duration"] - 5.5) <= 0.3, f"focus: duration {got_z['duration']} (the focused 4 s must stay)"
    track = card_track(zoomed, 1440, 900)
    peak = max(sc for sc, _ in track)
    assert peak >= 1.7, f"focus: zoom frames look like the full view (peak scale {peak:.2f})"
    assert abs(track[-1][0] - 1) <= 0.02 and abs(track[5][0] - 1) <= 0.02, "focus: does not start and end on the full view"
    held = sum(sc >= peak - 0.02 for sc, _ in track) / FPS
    assert held >= 2.0, f"focus: held only {held:.2f}s"
    check_smooth("focus", track)
    try:
        check_smooth("hard cut", [(1.0, 0.0), (1.0, 0.0), (1.82, 0.47)])
        raise AssertionError("a hard cut to the zoomed view passed the smoothness check")
    except AssertionError as e:
        if "passed" in str(e):
            raise
    opening = work / "opening.json"
    opening.write_text(json.dumps({"steps": [{"start": 0, "text": "Suggested panel", "focus": [820, 140, 560, 380]},
                                             {"start": 4, "text": "Back"}]}), encoding="utf-8")
    opened = compose([grad], opening, work / "opening.mp4")
    got_o = cpv.probe(opened)
    track_o = card_track(opened, 1440, 900)
    lead_frames = track_o[:int(OPENING_S * FPS)]
    assert all(abs(sc - 1) <= 0.02 for sc, _ in lead_frames), "opening: zoomed before 2.5 s of full view"
    assert max(sc for sc, _ in track_o) >= 1.7, "opening: never zoomed"
    assert abs(got_o["duration"] - (4 + 0.9 + OPENING_S)) <= 0.3, f"opening: duration {got_o['duration']}"
    check_smooth("opening", track_o)
    phone_focus = work / "phone_focus.txt"
    phone_focus.write_text("0 -> Desk\n5.5 -> Lander @ 10,10,100,100\n", encoding="utf-8")
    zero = work / "zero.txt"
    zero.write_text("0 -> Desk @ 10,10,0,100\n", encoding="utf-8")
    outside = work / "outside.txt"
    outside.write_text("0 -> Desk @ 2000,10,100,100\n", encoding="utf-8")
    bare = work / "bare.txt"
    bare.write_text("0 -> @ 10,10,100,100\n", encoding="utf-8")
    for case, args in (("focus on a phone clip", ([desk, phone], phone_focus)), ("zero-size focus", ([desk], zero)),
                       ("focus outside the frame", ([desk], outside)), ("focus without caption", ([desk], bare))):
        try:
            compose(*args, out=work / "x.mp4")
        except InputError:
            continue
        raise AssertionError(f"{case} input was accepted")
    frames = []
    for t in (0.3, 1.0, 2.5, 4.4):
        f = work / f"focus_{t:.1f}s.png"
        cpv.run([cpv.FFMPEG, "-y", "-v", "error", "-ss", str(t), "-i", str(zoomed), "-frames:v", "1", str(f)])
        frames.append(f)
    for t in (1.0, 4.0, 7.0):
        f = work / f"mixed_{t:.1f}s.png"
        cpv.run([cpv.FFMPEG, "-y", "-v", "error", "-ss", str(t), "-i", str(results[1][1]), "-frames:v", "1", str(f)])
        frames.append(f)
    for name, final, got in results:
        print(f"SELF-TEST OK {name} {got['width']}x{got['height']} SAR {got['sar']} {got['duration']:.2f}s {final}")
    print(f"SELF-TEST OK focus parse text+json, peak zoom {peak:.2f}x held {held:.2f}s, "
          f"{got_z['duration']:.2f}s smooth {zoomed}")
    print(f"SELF-TEST OK opening {OPENING_S:g}s full view before the first zoom, {got_o['duration']:.2f}s smooth {opened}")
    for f in frames:
        print(f"frame: {f}")


def main():
    ap = argparse.ArgumentParser(description="Compose a 1920x1080 review video: step list on the left, "
                                             "desktop clips in a window card and phone clips in an iPhone "
                                             "frame on the right, played in the order given.")
    ap.add_argument("--video", action="append", help="clip, repeatable; landscape = desktop card, portrait = phone frame")
    ap.add_argument("--steps", help="steps file (same format as compose_phone_video.py), times on the joined timeline; "
                         "'0:12 -> caption @ x,y,w,h' or JSON \"focus\": [x,y,w,h] zooms the desktop card "
                         "to that raw-pixel rectangle for the step")
    ap.add_argument("--out", help="output mp4")
    ap.add_argument("--title", help="title above the steps (overrides the steps file)")
    ap.add_argument("--status-bar", choices=["auto", "draw", "none"], default="auto",
                    help="phone clips: draw our status bar; auto skips it when the recording has its own")
    ap.add_argument("--lang", choices=["auto", "pt", "en"], default="auto",
                    help="language of the step counter shown past 5 steps")
    ap.add_argument("--no-blend", action="store_true", help="repeat frames instead of blending between them")
    ap.add_argument("--max-still", type=float, default=cpv.MAX_STILL,
                    help="cut still stretches longer than this many seconds down to it (0 keeps all)")
    ap.add_argument("--self-test", action="store_true", help="compose synthetic clips and check the result")
    ap.add_argument("--self-test-dir", help="keep self-test files here")
    a = ap.parse_args()
    try:
        if a.self_test:
            self_test(a.self_test_dir)
            return 0
        if not (a.video and a.steps and a.out):
            ap.error("--video, --steps and --out are required")
        out = compose(a.video, a.steps, a.out, a.title, a.status_bar, a.lang, a.max_still, not a.no_blend)
        info = cpv.probe(out)
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
