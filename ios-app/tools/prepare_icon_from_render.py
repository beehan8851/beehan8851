#!/usr/bin/env python3
"""Turns a generated icon render into an App Store ready 1024 px icon.

Image generators usually draw the icon as a rounded square on a white canvas. iOS
wants the opposite: a full-bleed square, because it applies its own corner mask, and
a generated corner is rounder than Apple's, so a straight crop shows white wedges in
every corner. This script:

  1. finds the drawn shape (white canvas = near-white pixels connected to the border,
     so a white character inside the icon is never mistaken for background),
  2. drops the anti-aliased edge and any thin rim (erodes the shape a few pixels),
  3. fills everything outside it with the nearest colour from inside, ring by ring,
     and softens only that filled part,
  4. crops a square, resizes to 1024 and saves an opaque PNG (App Store Connect
     rejects alpha),
  5. checks that no white is left anywhere the iOS mask would show, and writes
     before/after and home-screen previews next to the output.

Usage:
  python3 tools/prepare_icon_from_render.py <source image> <output dir>
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

WHITE = 228        # canvas threshold (min channel)
ERODE = 6          # px trimmed off the drawn edge before filling
FONT = "/System/Library/Fonts/SFNS.ttf"


def squircle(size, n=5.0, ss=4):
    """Close stand-in for Apple's icon mask: the superellipse |x|^n + |y|^n <= 1."""
    s = size * ss
    t = (np.arange(s) + 0.5) / s * 2 - 1
    xx, yy = np.meshgrid(t, t)
    m = (np.abs(xx) ** n + np.abs(yy) ** n) <= 1.0
    return Image.fromarray((m * 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)


def grow(mask, limit=None):
    g = mask.copy()
    g[1:, :] |= mask[:-1, :]; g[:-1, :] |= mask[1:, :]; g[:, 1:] |= mask[:, :-1]; g[:, :-1] |= mask[:, 1:]
    return g & limit if limit is not None else g


def exterior(rgb):
    white = rgb.min(axis=2) >= WHITE
    ext = np.zeros(white.shape, bool)
    ext[0, :], ext[-1, :], ext[:, 0], ext[:, -1] = white[0, :], white[-1, :], white[:, 0], white[:, -1]
    while True:
        g = grow(ext, white)
        if (g == ext).all():
            return ext
        ext = g


def fill_outside(rgb, known):
    img = rgb.astype(np.float32).copy()
    img[~known] = 0
    known = known.copy()
    shifts = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
    while not known.all():
        acc = np.zeros_like(img); cnt = np.zeros(known.shape, np.float32)
        kv = img * known[..., None]; kf = known.astype(np.float32)
        for dy, dx in shifts:
            acc += np.roll(np.roll(kv, dy, 0), dx, 1)
            cnt += np.roll(np.roll(kf, dy, 0), dx, 1)
        new = (~known) & (cnt > 0)
        if not new.any():
            break
        img[new] = acc[new] / cnt[new][:, None]
        known |= new
    return np.clip(img, 0, 255).astype(np.uint8)


def prepare(src_path, out_dir):
    out = Path(out_dir); out.mkdir(parents=True, exist_ok=True)
    src = Image.open(src_path).convert("RGB")
    rgb = np.asarray(src).astype(int)
    ext = exterior(rgb)
    ys, xs = np.where(~ext)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    side = int(min(x1 - x0, y1 - y0)) + 1            # generated shapes are not always square
    cx = (x0 + x1 + 1) // 2
    sx, sy = cx - side // 2, y0                         # keep the top, trim the bottom if taller

    inside = ~ext
    for _ in range(ERODE):
        e = inside.copy()
        e[1:, :] &= inside[:-1, :]; e[:-1, :] &= inside[1:, :]; e[:, 1:] &= inside[:, :-1]; e[:, :-1] &= inside[:, 1:]
        inside = e

    pad = 12
    box = (sx - pad, sy - pad, sx + side + pad, sy + side + pad)
    filled = Image.fromarray(fill_outside(rgb[box[1]:box[3], box[0]:box[2]], inside[box[1]:box[3], box[0]:box[2]]))
    fmask = Image.fromarray(((~inside[box[1]:box[3], box[0]:box[2]]) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))
    merged = Image.composite(filled.filter(ImageFilter.GaussianBlur(6)), filled, fmask)
    icon = merged.crop((pad, pad, pad + side, pad + side)).resize((1024, 1024), Image.LANCZOS).convert("RGB")
    icon.save(out / "AppIcon-1024.png", optimize=True)

    # Verify: no canvas white left where the iOS mask shows the icon.
    was_canvas = Image.fromarray((ext[sy:sy + side, sx:sx + side] * 255).astype(np.uint8)).resize((1024, 1024), Image.NEAREST)
    shown = np.asarray(squircle(1024)) > 127
    leak = (np.asarray(icon).min(axis=2) >= 200) & shown & (np.asarray(was_canvas) > 0)
    raw = src.crop((sx, sy, sx + side, sy + side))
    raw_leak = (np.asarray(raw.resize((1024, 1024))).min(axis=2) >= 200) & shown & (np.asarray(was_canvas) > 0)

    def masked(im, size):
        im = im.resize((size, size), Image.LANCZOS).convert("RGBA"); im.putalpha(squircle(size)); return im

    f = lambda s: ImageFont.truetype(FONT, s)
    board = Image.new("RGB", (1180, 640), (24, 26, 34)); d = ImageDraw.Draw(board)
    for i, (label, im) in enumerate((("Hozirgi holida", raw), ("Tuzatilgan", icon))):
        ic = masked(im, 460); board.paste(ic, (80 + i * 560, 60), ic)
        d.text((80 + i * 560, 545), label, font=f(30), fill=(235, 235, 240))
    board.save(out / "check-corners.png")

    sheet = Image.new("RGB", (1500, 1170), (246, 242, 236)); d = ImageDraw.Draw(sheet)
    d.text((60, 40), "App icon · telefonda", font=f(44), fill=(30, 26, 23))
    d.text((60, 98), "1024 px PNG, iOS niqobi bilan, haqiqiy piksel o'lchamlarida.", font=f(24), fill=(120, 112, 104))

    def tile(size, dark):
        im = Image.new("RGBA", (size, size), (58, 60, 72, 255) if dark else (214, 210, 202, 255)); im.putalpha(squircle(size))
        ImageDraw.Draw(im).ellipse([size * .33] * 2 + [size * .67] * 2, fill=(96, 98, 112, 255) if dark else (176, 172, 164, 255))
        return im

    for row, dark in enumerate((False, True)):
        y = 160 + row * 350
        d.rounded_rectangle([60, y, 1440, y + 330], radius=28, fill=(18, 20, 30) if dark else (226, 222, 214))
        for i in range(6):
            cxp = 60 + i * 230 + 115; size = 180; x = cxp - 90
            ic = masked(icon, size) if i == 2 else tile(size, dark)
            sheet.paste(ic, (x, y + 50), ic)
            name = "Dawnwick" if i == 2 else "Ilova"
            d.text((cxp - d.textlength(name, font=f(28)) / 2, y + 252), name, font=f(28), fill=(240, 240, 244) if dark else (30, 30, 30))
    y, x = 880, 60
    d.text((60, y), "Kichik o'lchamlar", font=f(26), fill=(30, 26, 23))
    for size, label in ((120, "Spotlight"), (87, "Sozlamalar"), (60, "Bildirishnoma")):
        x_label = x
        for dark in (False, True):
            d.rounded_rectangle([x, y + 50, x + size + 40, y + 90 + size], radius=18, fill=(18, 20, 30) if dark else (226, 222, 214))
            ic = masked(icon, size); sheet.paste(ic, (x + 20, y + 70), ic); x += size + 56
        d.text((x_label, y + 230), label, font=f(22), fill=(120, 112, 104)); x += 40
    sheet.save(out / "preview-home.png", optimize=True)
    return {"shape": (int(x1 - x0 + 1), int(y1 - y0 + 1)), "square": side, "white_shown_before": int(raw_leak.sum()),
            "white_shown_after": int(leak.sum())}


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    print(prepare(sys.argv[1], sys.argv[2]))
