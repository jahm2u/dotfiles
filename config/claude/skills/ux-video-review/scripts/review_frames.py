#!/usr/bin/env python3
"""review_frames.py -- contact sheets of a review video for a frame review, cheap on tokens.

    review_frames.py final.mp4 --out sheets/ [--layout phone|desktop] [--per-sheet 4]

Keeps frames where something moves and drops the still stretches: the video is sampled at
--fps, each motion burst keeps its first frame, a few in-between ones and the settled frame,
and a still stretch keeps one. The kept frames are cropped to the recording (no step panel),
labelled with their time and tiled side by side, so one sheet image carries --per-sheet frames
for the price of one. Prints one line per sheet and an estimate of the tokens they cost.
"""
import argparse
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import compose_phone_video as cpv

CROPS = {"phone": (840, 0, 1920, 1080), "desktop": (600, 0, 1920, 1080), "full": (0, 0, 1920, 1080)}


def fit_crop(video, crop):
    """Shrink the crop to what is drawn on the background: the phone frame or the desktop card."""
    x0, y0, x1, y1 = crop
    raw = subprocess.run([cpv.FFMPEG, "-v", "error", "-ss", "0.5", "-i", str(video), "-frames:v", "1",
                          "-vf", f"crop={x1 - x0}:{y1 - y0}:{x0}:{y0}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         capture_output=True, check=True).stdout
    img = Image.frombytes("RGB", (x1 - x0, y1 - y0), raw)
    diff = ImageChops.difference(img, Image.new("RGB", img.size, cpv.BG)).convert("L").point(lambda v: 255 if v > 40 else 0)
    box = diff.getbbox()
    if not box:
        return crop
    pad = 8
    bx0, by0, bx1, by1 = box
    return (x0 + max(0, bx0 - pad) // 2 * 2, y0 + max(0, by0 - pad) // 2 * 2,
            x0 + min(x1 - x0, bx1 + pad) // 2 * 2, y0 + min(y1 - y0, by1 + pad) // 2 * 2)


def motion(video, fps, crop):
    x0, y0, x1, y1 = crop
    return cpv.frame_changes(video, fps, f"crop={x1 - x0}:{y1 - y0}:{x0}:{y0},")


def pick(diffs, fps, threshold, per_burst):
    """Frame indexes to keep: the first, each burst's start/inner/settled frames, the last."""
    n = len(diffs)
    moving = [d > threshold for d in diffs]
    gap = max(1, int(fps * 0.3))  # a pause shorter than this is still the same burst
    keep, i = {0, n - 1}, 1
    while i < n:
        if not moving[i]:
            i += 1
            continue
        start, end, still = i, i, 0
        while i < n and still <= gap:
            if moving[i]:
                end, still = i, 0
            else:
                still += 1
            i += 1
        keep.add(start - 1)                      # just before it moves
        settled = min(end + 1, n - 1)
        keep.add(settled)                        # once it has stopped
        inner = end - start + 1
        for k in range(1, per_burst + 1):        # evenly through the motion
            if inner > k:
                keep.add(start + inner * k // (per_burst + 1))
    return sorted(keep)


def sheets(video, times, crop, out, per_sheet, tile_w):
    out.mkdir(parents=True, exist_ok=True)
    x0, y0, x1, y1 = crop
    tile_h = round(tile_w * (y1 - y0) / (x1 - x0))
    tiles = []
    for t in times:
        f = out / f".f{t:08.3f}.png"
        cpv.run([cpv.FFMPEG, "-y", "-v", "error", "-ss", f"{t:.3f}", "-i", str(video), "-frames:v", "1",
                 "-vf", f"crop={x1 - x0}:{y1 - y0}:{x0}:{y0},scale={tile_w}:{tile_h}", str(f)])
        tiles.append((t, f))
    paths = []
    for s in range(0, len(tiles), per_sheet):
        group = tiles[s:s + per_sheet]
        sheet = Image.new("RGB", (tile_w * len(group) + 6 * (len(group) - 1), tile_h + 28), (255, 255, 255))
        d = ImageDraw.Draw(sheet)
        for k, (t, f) in enumerate(group):
            x = k * (tile_w + 6)
            sheet.paste(Image.open(f), (x, 28))
            d.text((x + 4, 4), f"{int(t // 60)}:{t % 60:05.2f}", font=cpv.font("demi", 20), fill=(0, 0, 0))
            f.unlink()
        p = out / f"sheet-{s // per_sheet + 1:02d}.png"
        sheet.save(p)
        paths.append((p, group[0][0], group[-1][0], sheet.size))
    return paths


def tokens(size):
    w, h = size
    scale = min(1.0, 1568 / max(w, h), (1_150_000 / (w * h)) ** 0.5)
    return round(w * scale * h * scale / 750)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("video")
    ap.add_argument("--out", required=True, help="directory for sheet-NN.png")
    ap.add_argument("--layout", choices=list(CROPS), default="phone",
                    help="which part of the composed 1920x1080 to keep (default phone)")
    ap.add_argument("--fps", type=float, default=8, help="how finely motion is sampled")
    ap.add_argument("--threshold", type=int, default=cpv.CHANGED_PIXELS,
                    help="changed pixels (of a 96x96 grey copy) above which a frame counts as moving")
    ap.add_argument("--per-burst", type=int, default=2, help="frames kept inside each motion burst")
    ap.add_argument("--per-sheet", type=int, default=4)
    ap.add_argument("--tile-width", type=int, help="px per frame (default: 390 phone, 760 desktop/full)")
    a = ap.parse_args()
    crop = CROPS[a.layout] if a.layout == "full" else fit_crop(a.video, CROPS[a.layout])
    tile_w = a.tile_width or (390 if a.layout == "phone" else 760)
    per_sheet = a.per_sheet if a.layout == "phone" or a.per_sheet != 4 else 2
    diffs = motion(a.video, a.fps, crop)
    keep = pick(diffs, a.fps, a.threshold, a.per_burst)
    paths = sheets(Path(a.video), [i / a.fps for i in keep], crop, Path(a.out), per_sheet, tile_w)
    total = 0
    for p, t0, t1, size in paths:
        total += tokens(size)
        print(f"{p}  {t0:.2f}s-{t1:.2f}s")
    dur = len(diffs) / a.fps
    print(f"{len(keep)} frames in {len(paths)} sheets from {dur:.1f}s (fps=1 would be {int(dur) + 1} images, "
          f"~{(int(dur) + 1) * 1600:,} tokens); these ~{total:,} tokens")


if __name__ == "__main__":
    main()
