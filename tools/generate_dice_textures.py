#!/usr/bin/env python3
"""
Generate pre-made Custom Dice textures for Tabletop Simulator.

WHY PRE-MADE DICE?
------------------
A TTS "Custom_Dice" object takes ONE texture image with all 6 faces
baked into it. Faces drafted at click-time therefore can't be drawn
inside TTS (Lua can't composite images). So the draft happens HERE, at
build time: this script creates one finished die per legal composition
(13 total). At runtime the Roll button picks one of these dice at
random and spawns it as a real Custom_Dice. Every die still obeys
Ben's draft rules: 1-2 Misses / 1-3 Attacks / 1-3 Defends / 0-2 Statuses.

TEXTURE LAYOUT (verified from real mods' Custom_Dice textures)
--------------------------------------------------------------
Square canvas (768x768). The top third is unused (black, matching the
proven layout). The 6 faces sit in a 3x2 grid of 256px cells below it:

    y=256 (row A):  [ value 2 ] [ value 4 ] [ value 1 ]
    y=512 (row B):  [ value 3 ] [ value 5 ] [ value 6 ]

Cell<->value mapping was derived from a real Custom_Dice save whose
RotationValues name each face (SCED "Lola die"): combining its rest
rotations with its texture gives model faces +Y=cell A0, +X=A1,
+Z=A2, -X=B0, -Y=B1, -Z=B2, and a standard d6's values sit at
1=+Z, 2=+Y, 3=-X, 4=+X, 5=-Y, 6=-Z (opposites sum to 7).

Output: assets/dice/dice_NN.png + data/dice_catalog.json
(catalog lists, per die, the face ids sitting on values 1..6)
"""
import json
import random
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ICON_DIR = ROOT / "assets" / "icons"
OUT_DIR = ROOT / "assets" / "dice"
DB_PATH = ROOT / "data" / "face_database.json"
CATALOG_PATH = ROOT / "data" / "dice_catalog.json"

CELL = 256
CANVAS = 768

# die value -> (col, row) on the canvas; row 0 = y256 band, row 1 = y512 band
# Calibrated empirically in TTS (Ben's number-key test, 2026-10-22):
# the first derived mapping had values 1, 3 and 5 in each other's cells.
VALUE_TO_CELL = {
    1: (0, 1),
    2: (0, 0),
    3: (1, 1),
    4: (1, 0),
    5: (2, 0),
    6: (2, 1),
}

# Icons on values 1 and 6 appeared upside down in TTS (same calibration
# test), so those two cells are painted rotated 180 degrees.
VALUE_ROTATION = {1: 180, 6: 180}

POOL_ORDER = ["misses", "attacks", "defends", "statuses"]
RANGES = {"misses": (1, 2), "attacks": (1, 3), "defends": (1, 3), "statuses": (0, 2)}


def legal_compositions():
    comps = []
    for m in range(RANGES["misses"][0], RANGES["misses"][1] + 1):
        for a in range(RANGES["attacks"][0], RANGES["attacks"][1] + 1):
            for d in range(RANGES["defends"][0], RANGES["defends"][1] + 1):
                for s in range(RANGES["statuses"][0], RANGES["statuses"][1] + 1):
                    if m + a + d + s == 6:
                        comps.append({"misses": m, "attacks": a, "defends": d, "statuses": s})
    return comps


def find_icon(filename: str) -> Path:
    """Icons live in pool subfolders locally, flat names in the repo."""
    hits = list(ICON_DIR.rglob(filename))
    if not hits:
        raise FileNotFoundError(filename)
    return hits[0]


# Generated dice only ever carry the BASE form of each dice type
# (Ben, 2026-10-22): no Miss x2/x3, no Hit/Block +2..+5, no Crit x2.
# The variations stay in the database for the drafting/collection game.
BASE_FACE_IDS = {
    "miss", "chip", "break",          # misses: base Miss, Chip, Break
    "hit_1", "crit",                   # attacks: base Hit (+1), base Crit
    "block_1", "negate",               # defends: base Block (+1), Negate
    # statuses have no variations - all 9 are base forms
}


def main():
    db = json.loads(DB_PATH.read_text())
    pools = {
        name: [f for f in db["pools"][name]
               if name == "statuses" or f["id"] in BASE_FACE_IDS]
        for name in POOL_ORDER
    }
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    rng = random.Random(20261022)  # fixed seed: regenerating is reproducible
    catalog = []

    for i, comp in enumerate(legal_compositions(), start=1):
        faces = []  # face dicts, will be assigned to values 1..6 after shuffle
        for pool in POOL_ORDER:
            # Prefer distinct faces; a die may repeat a base face when a
            # composition asks for more of a pool than it has base types.
            pool_faces = pools[pool]
            picks = rng.sample(pool_faces, min(comp[pool], len(pool_faces)))
            while len(picks) < comp[pool]:
                picks.append(rng.choice(pool_faces))
            faces.extend(picks)
        rng.shuffle(faces)  # faces[v-1] sits on die value v

        canvas = Image.new("RGB", (CANVAS, CANVAS), (0, 0, 0))
        for value, face in enumerate(faces, start=1):
            col, row = VALUE_TO_CELL[value]
            icon = Image.open(find_icon(face["icon"])).convert("RGB")
            if icon.size != (CELL, CELL):
                icon = icon.resize((CELL, CELL), Image.NEAREST)
            if value in VALUE_ROTATION:
                icon = icon.rotate(VALUE_ROTATION[value])
            canvas.paste(icon, (col * CELL, 256 + row * CELL))

        tex_name = f"dice_{i:02d}.png"
        canvas.save(OUT_DIR / tex_name)
        catalog.append({
            "id": f"dice_{i:02d}",
            "texture": tex_name,
            "composition": comp,
            "faces": [f["id"] for f in faces],  # index 0 = value 1 ... index 5 = value 6
        })
        print(tex_name, comp, [f["id"] for f in faces])

    CATALOG_PATH.write_text(json.dumps({"dice": catalog}, indent=2) + "\n")
    print(f"\nWrote {len(catalog)} dice textures to {OUT_DIR} and catalog to {CATALOG_PATH}")


if __name__ == "__main__":
    main()
