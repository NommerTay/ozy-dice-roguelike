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


def main():
    combat = [Image.open(find_icon(fid)) for fid in COMBAT_FACES]
    paint(combat).save(ROOT / "starting_combat.png")
    print("starting_combat.png", COMBAT_FACES)
    for stat, colors in STATS.items():
        cells = [event_face(kind, colors) for kind in EVENT_LAYOUT]
        out = ROOT / f"starting_event_{stat}.png"
        paint(cells).save(out)
        print(out.name, EVENT_LAYOUT)


if __name__ == "__main__":
    main()
