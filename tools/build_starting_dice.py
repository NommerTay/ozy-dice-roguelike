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
# three-icon sides. The icons are drawn PROCEDURALLY as simple
# flat pixel art (Ben: the AI masters were too detailed and did
# not mesh with the set) on a 64px grid, then composed onto
# parchment faces with a bronze faction rim.
# ------------------------------------------------------------------
FACTION_RIM = (116, 79, 43)
FACTION_FIELD = (243, 213, 152)
# counts in die-value order 1..6: three 1s, two 2s, one 3
FACTION_LAYOUT = [1, 1, 2, 3, 2, 1]

DK = (56, 38, 24, 255)          # dark outline brown
WOOD = (172, 110, 58, 255)
WOOD_DK = (140, 84, 40, 255)
IRON = (72, 64, 60, 255)
IRON_LT = (150, 142, 132, 255)
FOAM = (247, 240, 220, 255)
FOAM_SH = (228, 208, 172, 255)
SKIN = (208, 138, 92, 255)
SKIN_DK = (168, 104, 64, 255)
LEATHER = (122, 79, 45, 255)
STEEL = (148, 152, 158, 255)
STEEL_LT = (190, 194, 200, 255)
HANDLE_WOOD = (150, 96, 50, 255)


def _poly(d, pts, fill):
    d.polygon(pts, fill=fill)


def mug_sprite():
    """Simple flat tankard: wood body, two iron bands, foam top."""
    im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # handle (behind body): dark ring with a punched hole
    d.rounded_rectangle([43, 25, 58, 47], radius=6, fill=DK)
    d.rounded_rectangle([48, 30, 55, 42], radius=4, fill=(0, 0, 0, 0))
    # body
    _poly(d, [(16, 20), (48, 20), (46, 57), (18, 57)], DK)
    _poly(d, [(18, 22), (46, 22), (44, 55), (20, 55)], WOOD)
    # plank lines
    d.line([27, 24, 27, 53], fill=WOOD_DK, width=2)
    d.line([37, 24, 37, 53], fill=WOOD_DK, width=2)
    # iron bands + rivets
    for y0 in (27, 43):
        d.rectangle([15, y0, 49, y0 + 4], fill=IRON)
        d.line([15, y0, 49, y0], fill=IRON_LT, width=1)
        for rx in (22, 32, 42):
            d.ellipse([rx, y0 + 1, rx + 2, y0 + 3], fill=IRON_LT)
    # foam: outlined bubbly top + a drip down the left
    for cx, cy, r in [(24, 15, 7), (33, 11, 8), (42, 15, 7),
                      (28, 18, 6), (38, 18, 6)]:
        d.ellipse([cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1], fill=DK)
    d.rectangle([17, 16, 47, 22], fill=FOAM)
    for cx, cy, r in [(24, 15, 7), (33, 11, 8), (42, 15, 7),
                      (28, 18, 6), (38, 18, 6)]:
        d.ellipse([cx - r, cy - r + 2, cx + r, cy + r + 2], fill=FOAM_SH)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=FOAM)
    d.ellipse([15, 20, 23, 30], fill=DK)
    d.ellipse([16, 21, 22, 29], fill=FOAM)
    return im.resize((256, 256), Image.NEAREST)


def hammer_sprite():
    """Simple flat icon: forearm + fist thrusting a hammer up."""
    im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # handle (behind fist and head)
    d.rectangle([28, 9, 36, 38], fill=DK)
    d.rectangle([30, 10, 34, 37], fill=HANDLE_WOOD)
    # hammer head: a chunky sledge block - flat striking caps at
    # both ends, lighter steel caps, socket where the haft enters
    d.rectangle([9, 3, 55, 18], fill=DK)
    d.rectangle([11, 5, 53, 16], fill=STEEL)
    d.rectangle([11, 5, 17, 16], fill=STEEL_LT)
    d.rectangle([47, 5, 53, 16], fill=STEEL_LT)
    d.line([11, 5, 53, 5], fill=STEEL_LT, width=1)
    d.rectangle([28, 15, 36, 20], fill=DK)
    # forearm rising from the bottom
    _poly(d, [(23, 64), (41, 64), (39, 40), (25, 40)], DK)
    _poly(d, [(25, 64), (39, 64), (37, 42), (27, 42)], SKIN)
    # leather wrist wrap + studs
    d.rectangle([26, 47, 38, 53], fill=LEATHER)
    d.line([26, 47, 38, 47], fill=DK, width=1)
    for rx in (29, 34):
        d.ellipse([rx, 49, rx + 2, rx and 51 or 51], fill=IRON_LT)
    # fist gripping the handle
    d.rounded_rectangle([19, 25, 45, 43], radius=6, fill=DK)
    d.rounded_rectangle([21, 27, 43, 41], radius=5, fill=SKIN)
    d.line([22, 33, 42, 33], fill=SKIN_DK, width=2)
    d.line([22, 38, 42, 38], fill=SKIN_DK, width=2)
    # thumb bump on the right of the fist
    d.ellipse([38, 26, 47, 35], fill=DK)
    d.ellipse([39, 27, 46, 34], fill=SKIN)
    return im.resize((256, 256), Image.NEAREST)


def build_faction():
    for sprite, out_name in (
            (mug_sprite(), "starting_faction_resilience.png"),
            (hammer_sprite(), "starting_faction_labor.png")):
        cells = [faction_face(sprite, c) for c in FACTION_LAYOUT]
        paint(cells).save(ROOT / out_name)
        print(out_name, FACTION_LAYOUT)


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
