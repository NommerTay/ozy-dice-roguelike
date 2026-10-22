#!/usr/bin/env python3
"""Build the four STARTING dice textures (repo root, for TTS).

- starting_combat.png: every combat starting die is the SAME die -
  2x Block, 1x Block +1, 1x Hit, 1x Daze, 1x Miss (Ben's spec).
- starting_event_<stat>.png: stat dice - 3x one-dot, 2x blank,
  1x two-dot sides; DEX green, CON yellow, STR red. The dot faces
  are drawn procedurally (64px pixel grid, upscaled NEAREST) as
  magic orbs on a stat-coloured panel.

Painting uses the calibrated value->cell mapping + 180-degree
rotations from generate_dice_textures.py (verified in TTS).
Face order in each list below is die values 1..6.
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ICONS = ROOT / "assets" / "icons"
CELL = 256
CANVAS = 768
VALUE_TO_CELL = {1: (0, 1), 2: (0, 0), 3: (1, 1), 4: (1, 0), 5: (2, 0), 6: (2, 1)}
VALUE_ROTATION = {1: 180, 6: 180}

# combat die values 1..6 (opposites sum to 7: miss/block,
# block/daze, block+1/hit)
COMBAT_FACES = ["miss", "block", "block_1", "hit", "status_daze", "block"]

# event die values 1..6: blank, 1-dot, 1-dot, 2-dot, 1-dot, blank
EVENT_LAYOUT = ["blank", "dot1", "dot1", "dot2", "dot1", "blank"]
STATS = {
    "dex": {"base": (43, 79, 54), "panel": (79, 128, 90), "edge": (30, 58, 39)},
    "con": {"base": (133, 99, 28), "panel": (186, 148, 52), "edge": (96, 70, 18)},
    "str": {"base": (128, 47, 40), "panel": (172, 78, 62), "edge": (90, 31, 26)},
}
CREAM = (246, 235, 208)
SHADE = (206, 178, 132)
SPARK = (255, 252, 240)


def find_icon(face_id):
    db = json.loads((ROOT / "data" / "face_database.json").read_text())
    for pool, faces in db["pools"].items():
        for f in faces:
            if f["id"] == face_id:
                return ICONS / pool / f["icon"]
    raise KeyError(face_id)


def paint(cells):
    """cells: list of 6 PIL images in value order 1..6."""
    canvas = Image.new("RGB", (CANVAS, CANVAS), (0, 0, 0))
    for value, icon in enumerate(cells, start=1):
        col, row = VALUE_TO_CELL[value]
        icon = icon.convert("RGB")
        if icon.size != (CELL, CELL):
            icon = icon.resize((CELL, CELL), Image.NEAREST)
        if value in VALUE_ROTATION:
            icon = icon.rotate(VALUE_ROTATION[value])
        canvas.paste(icon, (col * CELL, 256 + row * CELL))
    return canvas


def draw_dot(d, cx, cy, r):
    d.ellipse([cx - r, cy - r + 2, cx + r, cy + r + 2], fill=SHADE)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=CREAM)
    d.ellipse([cx - r + 2, cy - r + 2, cx - r + 6, cy - r + 5], fill=SPARK)
    # tiny 4-point sparkle, upper right of the orb
    sx, sy = cx + r - 2, cy - r + 1
    d.line([sx - 2, sy, sx + 2, sy], fill=SPARK)
    d.line([sx, sy - 2, sx, sy + 2], fill=SPARK)


def event_face(kind, colors):
    g = 64
    im = Image.new("RGB", (g, g), colors["base"])
    d = ImageDraw.Draw(im)
    d.rectangle([5, 5, g - 6, g - 6], fill=colors["panel"], outline=colors["edge"], width=2)
    if kind == "blank":
        d.rectangle([14, 14, g - 15, g - 15], outline=colors["edge"])
    elif kind == "dot1":
        draw_dot(d, 32, 32, 10)
    elif kind == "dot2":
        draw_dot(d, 21, 21, 8)
        draw_dot(d, 43, 43, 8)
    return im.resize((CELL, CELL), Image.NEAREST)


# ------------------------------------------------------------------
# Faction dice: Drunkard's Resilience (mugs) and Hard Labor
# (hammer arm). Each die has 3x one-icon, 2x two-icon and 1x
# three-icon sides. The icons are AI masters (kept with the other
# masters) keyed off their flat backgrounds into sprites, then
# composed onto parchment faces with a bronze faction rim.
# ------------------------------------------------------------------
import glob as _glob
from collections import deque

MASTERS_DIR = Path.home() / "workspace" / "cozy-dice-canva-icons"
FACTION_RIM = (116, 79, 43)
FACTION_FIELD = (243, 213, 152)
# counts in die-value order 1..6: three 1s, two 2s, one 3
FACTION_LAYOUT = [1, 1, 2, 3, 2, 1]


def _flood_passable(alpha, seeds_img, color_test):
    """Flood from the borders through pixels passing color_test;
    returns a mask of reached pixels."""
    w, h = seeds_img.size
    px = seeds_img.load()
    seen = bytearray(w * h)
    dq = deque()
    for x in range(w):
        for y in (0, h - 1):
            if color_test(px[x, y]):
                dq.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if color_test(px[x, y]):
                dq.append((x, y))
    while dq:
        x, y = dq.popleft()
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] \
                    and color_test(px[nx, ny]):
                dq.append((nx, ny))
    return seen


def make_sprite(pattern):
    path = sorted(_glob.glob(str(MASTERS_DIR / pattern)))[0]
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    corner = px[2, 2]
    # pass 1: the border-connected background (dark for the mug,
    # dark teal for the hammer)
    bg1 = _flood_passable(None, im,
                          lambda c: sum(abs(c[i] - corner[i]) for i in range(3)) < 110)
    # pass 2: the hammer master also has a light teal disc BEHIND the
    # subject - a second island colour. Sample it from a clear disc
    # spot (left-middle, away from the arm) and flood again, treating
    # already-keyed pixels as passable.
    import numpy as np
    arr = np.array(im).astype(int)
    alpha = np.where(np.array(bg1, dtype=bool).reshape(h, w), 0, 255).astype(np.uint8)
    disc = tuple(arr[int(h * 0.5), int(w * 0.06)])
    def disc_test(c):
        return sum(abs(c[i] - disc[i]) for i in range(3)) < 60
    passable_img = Image.fromarray(
        np.where((alpha == 0)[..., None], (0, 0, 0), arr).astype(np.uint8))
    # flood on a synthetic image: bg-coloured where keyed or disc-like
    synth = np.array(passable_img)
    keyed = (alpha == 0)
    synth[keyed] = corner
    is_disc = np.zeros((h, w), dtype=bool)
    for yy in range(h):
        for xx in range(w):
            if disc_test(tuple(arr[yy, xx])):
                is_disc[yy, xx] = True
    synth_img = Image.fromarray(synth.astype(np.uint8))
    bg2 = _flood_passable(None, synth_img,
                          lambda c: sum(abs(c[i] - corner[i]) for i in range(3)) < 110)
    bg2 = np.array(bg2, dtype=bool).reshape(h, w)
    newly = bg2 & is_disc
    alpha[newly] = 0
    # drop speck components (stray foam dots etc.): keep components
    # at least 2% the size of the largest
    from scipy import ndimage
    lab, n = ndimage.label(alpha > 0)
    if n > 1:
        sizes = ndimage.sum(alpha > 0, lab, range(1, n + 1))
        keep = np.isin(lab, [i + 1 for i, s in enumerate(sizes)
                              if s >= 0.02 * sizes.max()])
        alpha = np.where(keep, alpha, 0).astype(np.uint8)
    sprite = Image.fromarray(
        np.dstack([arr.astype(np.uint8), alpha]).astype(np.uint8), "RGBA")
    bbox = sprite.getbbox()
    sprite = sprite.crop(bbox)
    # pixel-normalize: down to a 64px grid, back up NEAREST
    sw, sh = sprite.size
    grid = 64
    small = sprite.resize((grid, max(1, round(grid * sh / sw))), Image.LANCZOS)
    sprite = small.resize((256, max(1, round(256 * sh / sw))), Image.NEAREST)
    return sprite


def faction_face(sprite, count):
    face = Image.new("RGB", (CELL, CELL), FACTION_RIM)
    field = Image.new("RGB", (CELL - 24, CELL - 24), FACTION_FIELD)
    face.paste(field, (12, 12))
    if count == 1:
        spots = [(0.5, 0.5, 0.80)]
    elif count == 2:
        spots = [(0.31, 0.31, 0.58), (0.69, 0.69, 0.58)]
    else:
        spots = [(0.5, 0.27, 0.52), (0.28, 0.71, 0.52), (0.72, 0.71, 0.52)]
    for fx, fy, fs in spots:
        side = int(CELL * fs)
        sw, sh = sprite.size
        s = side / max(sw, sh)
        spr = sprite.resize((max(1, round(sw * s)), max(1, round(sh * s))),
                            Image.NEAREST)
        face.paste(spr, (int(fx * CELL - spr.size[0] / 2),
                         int(fy * CELL - spr.size[1] / 2)), spr)
    return face


def build_faction():
    for pattern, out_name in (
            ("media-generation-faction-mug-*.webp", "starting_faction_resilience.png"),
            ("media-generation-faction-hammer-*.webp", "starting_faction_labor.png")):
        sprite = make_sprite(pattern)
        cells = [faction_face(sprite, c) for c in FACTION_LAYOUT]
        paint(cells).save(ROOT / out_name)
        print(out_name, FACTION_LAYOUT)


def main():
    combat = [Image.open(find_icon(fid)) for fid in COMBAT_FACES]
    paint(combat).save(ROOT / "starting_combat.png")
    print("starting_combat.png", COMBAT_FACES)
    for stat, colors in STATS.items():
        cells = [event_face(kind, colors) for kind in EVENT_LAYOUT]
        out = ROOT / f"starting_event_{stat}.png"
        paint(cells).save(out)
        print(out.name, EVENT_LAYOUT)
    build_faction()


if __name__ == "__main__":
    main()
