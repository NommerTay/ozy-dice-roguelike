#!/usr/bin/env python3
"""
Build the game's dice FACES from the approved master icons.

Masters (16 dice-type artworks) live in ~/workspace/cozy-dice-canva-icons
(10 from Canva, 6 from the built-in generator - see the daily notes).
This script:
  1. pixel-normalizes each master (down to a 96px grid, back up NEAREST)
  2. frames it with its pool-coloured rim
  3. stamps crisp pixel-font badges for the variations
     (Hit +1..+5, Block +1..+5, Miss x2/x3, Crit x2)
  4. writes the 27 face icons into assets/icons/<pool>/ and the face
     database to data/face_database.json
  5. also builds miss_stamp.png - a round transparent Miss sticker used
     later by the Chip mechanic ("a random non-Miss side becomes a Miss")

Run before tools/generate_dice_textures.py.
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
MASTERS = Path.home() / "workspace" / "cozy-dice-canva-icons"
ALT = MASTERS / "alt"
ICON_OUT = ROOT / "assets" / "icons"
DB_OUT = ROOT / "data" / "face_database.json"

SIZE = 256          # face icon size
GRID = 96           # pixel-normalization grid
RIM = 12            # pool rim thickness in output px

RIM_COLORS = {
    "misses":   (104, 128, 152),   # blue-grey
    "attacks":  (198, 92, 58),     # terracotta
    "defends":  (106, 148, 100),   # sage
    "statuses": (150, 118, 190),   # lilac
}
BADGE_BG = (58, 44, 36)            # dark warm brown
BADGE_FG = (255, 240, 205)         # cream

# master file lookup: Canva masters are <name>.png, built-in ones are webp in alt/
def master_path(key):
    p = MASTERS / f"{key}.png"
    if p.exists():
        return p
    hits = sorted(ALT.glob(f"media-generation-{key.replace('_', '-')}-*.webp"))
    if hits:
        return hits[-1]
    raise FileNotFoundError(key)

# ---------------------------------------------------------------- pixel font
# 3x5 glyphs for the badge characters we need: + x 1 2 3 4 5
GLYPHS = {
    "+": ["010", "010", "111", "010", "010"],
    "x": ["000", "101", "010", "101", "000"],
    "1": ["010", "110", "010", "010", "111"],
    "2": ["110", "001", "010", "100", "111"],
    "3": ["110", "001", "010", "001", "110"],
    "4": ["101", "101", "111", "001", "001"],
    "5": ["111", "100", "110", "001", "110"],
}

def draw_badge(img, text, pool):
    """Chunky dark badge, bottom-right corner, cream pixel text."""
    scale = 5                       # each glyph pixel = 5 output px
    gw, gh = 3 * scale, 5 * scale
    gap = scale
    text_w = len(text) * (gw + gap) - gap
    pad = 10
    bw, bh = text_w + pad * 2, gh + pad * 2
    x1, y1 = SIZE - bw - 6, SIZE - bh - 6
    d = ImageDraw.Draw(img)
    rim = RIM_COLORS[pool]
    d.rounded_rectangle([x1 - 3, y1 - 3, x1 + bw + 3, y1 + bh + 3], radius=10, fill=rim)
    d.rounded_rectangle([x1, y1, x1 + bw, y1 + bh], radius=8, fill=BADGE_BG)
    cx = x1 + pad
    for ch in text:
        g = GLYPHS[ch]
        for r in range(5):
            for c in range(3):
                if g[r][c] == "1":
                    d.rectangle([cx + c * scale, y1 + pad + r * scale,
                                 cx + c * scale + scale - 1, y1 + pad + r * scale + scale - 1],
                                fill=BADGE_FG)
        cx += gw + gap

def build_face(master_key, pool):
    im = Image.open(master_path(master_key)).convert("RGB")
    im = im.resize((GRID, GRID), Image.LANCZOS).resize((SIZE, SIZE), Image.NEAREST)
    framed = Image.new("RGB", (SIZE, SIZE), RIM_COLORS[pool])
    framed.paste(im.resize((SIZE - 2 * RIM, SIZE - 2 * RIM), Image.NEAREST), (RIM, RIM))
    return framed

# ---------------------------------------------------------------- face specs
# (face id, name, pool, master, badge or None, value, effect)
FACES = [
    ("miss",      "Miss",       "misses", "miss",   None, 0, "Nothing happens."),
    ("miss_x2",   "Miss x2",    "misses", "miss",   "x2", 0, "Nothing happens. (Counts as 2 misses.)"),
    ("miss_x3",   "Miss x3",    "misses", "miss",   "x3", 0, "Nothing happens. (Counts as 3 misses.)"),
    ("chip",      "Chip",       "misses", "chip",   None, 0, "The die loses value: a random non-Miss side of it is turned into a Miss."),
    ("break",     "Break",      "misses", "break",  None, 0, "The die is destroyed and removed from your dice collection."),
    ("hit_1",     "Hit +1",     "attacks", "hit",   "+1", 1, "Succeeds the roll: a hit worth 1."),
    ("hit_2",     "Hit +2",     "attacks", "hit",   "+2", 2, "Succeeds the roll: a hit worth 2."),
    ("hit_3",     "Hit +3",     "attacks", "hit",   "+3", 3, "Succeeds the roll: a hit worth 3."),
    ("hit_4",     "Hit +4",     "attacks", "hit",   "+4", 4, "Succeeds the roll: a hit worth 4."),
    ("hit_5",     "Hit +5",     "attacks", "hit",   "+5", 5, "Succeeds the roll: a hit worth 5."),
    ("crit",      "Crit",       "attacks", "crit",  None, 2, "Double the amount of one of your Hits rolled."),
    ("crit_x2",   "Crit x2",    "attacks", "crit",  "x2", 3, "Triple the amount of one of your Hits rolled instead of doubling."),
    ("block_1",   "Block +1",   "defends", "block", "+1", 1, "Ignores one die from the Attack pool targeting you. Block strength 1."),
    ("block_2",   "Block +2",   "defends", "block", "+2", 2, "Ignores one die from the Attack pool targeting you. Block strength 2."),
    ("block_3",   "Block +3",   "defends", "block", "+3", 3, "Ignores one die from the Attack pool targeting you. Block strength 3."),
    ("block_4",   "Block +4",   "defends", "block", "+4", 4, "Ignores one die from the Attack pool targeting you. Block strength 4."),
    ("block_5",   "Block +5",   "defends", "block", "+5", 5, "Ignores one die from the Attack pool targeting you. Block strength 5."),
    ("negate",    "Negate",     "defends", "negate", None, 1, "Ignores one die from the Status pool targeting you."),
    ("status_burn",    "Burn",    "statuses", "status_burn_flame", None, 1, "Status: Burn. (Effect to be defined.)"),
    ("status_bleed",   "Bleed",   "statuses", "status_bleed",   None, 1, "Status: Bleed. (Effect to be defined.)"),
    ("status_poison",  "Poison",  "statuses", "status_poison",  None, 1, "Status: Poison. (Effect to be defined.)"),
    ("status_corrupt", "Corrupt", "statuses", "status_corrupt", None, 1, "Status: Corrupt. (Effect to be defined.)"),
    ("status_bless",   "Bless",   "statuses", "status_bless",   None, 1, "Status: Bless. (Effect to be defined.)"),
    ("status_daze",    "Daze",    "statuses", "status_daze_v2", None, 1, "Status: Daze. (Effect to be defined.)"),
    ("status_inspire", "Inspire", "statuses", "status_inspire", None, 1, "Status: Inspire. (Effect to be defined.)"),
    ("status_recoup",  "Recoup",  "statuses", "status_recoup",  None, 1, "Status: Recoup. (Effect to be defined.)"),
    ("status_charge",  "Charge",  "statuses", "status_charge",  None, 1, "Status: Charge. (Effect to be defined.)"),
]

MASTER_FOR = {  # face-master key -> file stem variants present on disk
    "status_burn_flame": "status_burn_flame",
}

def main():
    db = {"version": 2, "pools": {p: [] for p in RIM_COLORS}}
    for face_id, name, pool, master, badge, value, effect in FACES:
        img = build_face(master, pool)
        if badge:
            draw_badge(img, badge, pool)
        out_dir = ICON_OUT / pool
        out_dir.mkdir(parents=True, exist_ok=True)
        filename = f"{face_id}.png"
        img.save(out_dir / filename)
        db["pools"][pool].append({
            "id": face_id, "name": name, "value": value,
            "effect": effect, "icon": filename,
        })
        print("face", filename, f"({pool}, badge={badge})")

    DB_OUT.write_text(json.dumps(db, indent=2) + "\n")
    print("database ->", DB_OUT)

    # Miss stamp decal asset for the Chip mechanic: round transparent sticker
    miss = build_face("miss", "misses")
    stamp = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    mask = Image.new("L", (SIZE, SIZE), 0)
    md = ImageDraw.Draw(mask)
    md.ellipse([8, 8, SIZE - 8, SIZE - 8], fill=255)
    stamp.paste(miss, (0, 0), mask)
    sd = ImageDraw.Draw(stamp)
    sd.ellipse([8, 8, SIZE - 8, SIZE - 8], outline=RIM_COLORS["misses"] + (255,), width=10)
    stamp.save(ICON_OUT / "miss_stamp.png")
    print("stamp -> miss_stamp.png")


if __name__ == "__main__":
    main()
