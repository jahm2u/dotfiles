#!/usr/bin/env python3
import argparse
import json
import re
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
    file_title, steps = cpv.load_steps(steps_path)
    title = title if title is not None else file_title
    total = sum(c["duration"] for c in clips)
    over = [(i + 1, t) for i, (t, _) in enumerate(steps) if t >= total]
    if over:
        i, t = over[0]
        raise InputError(f"step {i} starts at {t:g}s, at or beyond the clips' {total:.2f}s")
    # cut each clip's still stretches, then move the steps (times on the joined timeline) to match
    offset, new_offset, joined = 0.0, 0.0, []
    for c in clips:
        c["keep"] = cpv.still_segments(c["path"], c["duration"], max_still)
        c["new"] = sum(b - a for a, b in c["keep"])
        joined += [(offset + a, offset + b) for a, b in c["keep"]]
        offset += c["duration"]
    steps = cpv.remap_steps(steps, joined)
    total = sum(c["new"] for c in clips)
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
            cmd += ["-loop", "1", "-framerate", str(FPS), "-t", f"{c['new']:.3f}", "-i", str(bg),
                    "-i", str(c["path"])]
            b, v = idx, idx + 1
            idx += 2
            chain.append(f"[{v}:v]setpts=PTS-STARTPTS,{cpv.retime(blend)}{cpv.keep_filter(c['keep'], c['duration'])},"
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
    frames = []
    for t in (1.0, 4.0, 7.0):
        f = work / f"mixed_{t:.1f}s.png"
        cpv.run([cpv.FFMPEG, "-y", "-v", "error", "-ss", str(t), "-i", str(results[1][1]), "-frames:v", "1", str(f)])
        frames.append(f)
    for name, final, got in results:
        print(f"SELF-TEST OK {name} {got['width']}x{got['height']} SAR {got['sar']} {got['duration']:.2f}s {final}")
    for f in frames:
        print(f"frame: {f}")


def main():
    ap = argparse.ArgumentParser(description="Compose a 1920x1080 review video: step list on the left, "
                                             "desktop clips in a window card and phone clips in an iPhone "
                                             "frame on the right, played in the order given.")
    ap.add_argument("--video", action="append", help="clip, repeatable; landscape = desktop card, portrait = phone frame")
    ap.add_argument("--steps", help="steps file (same format as compose_phone_video.py), times on the joined timeline")
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
