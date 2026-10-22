# Cozy Dice Roguelike — Tabletop Simulator

A cozy roguelike dice-drafting & collecting board game for **Tabletop Simulator (TTS)**.

Press **Roll** at the bottom of the screen and the game builds you a brand-new custom d6 on the spot — drafting its six faces at random from four pools stored **in this repo**.

## The pools

| Pool | Faces per die | Dice types in the database |
|---|---|---|
| **Misses** | 1–2 | Miss (also x2, x3), Chip, Break |
| **Attacks** | 1–3 | Hit +1…+5, Crit, Crit x2 |
| **Defends** | 1–3 | Block +1…+5, Negate |
| **Statuses** | 0–2 | Burn, Bleed, Poison, Corrupt, Bless, Daze, Inspire, Recoup, Charge (effects TBD) |

Counts are composed inside those ranges and total exactly **6** — every pre-made die in the catalog is a legal, playable die.

The 27 face icons are cozy pixel art: master artworks (generated in Canva and with the built-in generator, masters kept outside the repo) are pixel-normalized, framed with pool-coloured rims (blue-grey = Misses, terracotta = Attacks, sage = Defends, lilac = Statuses) and stamped with pixel-font variation badges by `tools/build_faces.py`. `assets/icons/miss_stamp.png` is a round transparent Miss sticker reserved for the Chip mechanic.

## Repo layout

```
*.png (repo root)        <- the actual visual assets TTS loads from GitHub:
  roll_button.png          the Roll button icon
  miss_*.png               5 Miss faces    attack_*.png   5 Attack faces
  defend_*.png             5 Defend faces  status_*.png   5 Status faces
  preview_contact_sheet.png  all 21 icons on one sheet
  dice_01.png … dice_13.png  baked Custom Dice textures (one per legal composition)
  Korts player board for upload.png
                           the Korts player board art (spawned by the Player Mat
                           button; Global.lua URL-encodes its spaces as %20)
data/face_database.json  <- THE database: pools, names, values, effects, icon filenames
data/dice_catalog.json   <- the dice pool: per die, its texture + face ids by die value
scripts/
  Global.lua             <- paste into TTS: Modding > Scripting > Global (Lua)
  UI.xml                 <- paste into TTS: Modding > Scripting > Global (UI)
  CustomDie.lua          <- optional: script for a template-die pattern
tools/generate_icons.py  <- regenerates every icon (python3, needs Pillow;
                            locally it writes them under assets/icons/ -
                            upload the PNGs themselves to the repo root)
tools/generate_dice_textures.py
                         <- composes the dice_NN.png textures + dice catalog
                            from the face database (same upload rule)
```

## Set it up in Tabletop Simulator

1. **Push this repo to GitHub** (public repo — TTS loads images anonymously).
2. `scripts/Global.lua` already points `GITHUB_RAW_BASE` at this repo (`NommerTay/ozy-dice-roguelike`, branch `main`). The script builds every asset URL from that one line — if you fork or rename the repo, that's the only line to change.
3. In TTS, open your table/save:
   - **Modding → Scripting → Global → Lua:** paste `scripts/Global.lua`
   - **Modding → Scripting → Global → UI:** paste `scripts/UI.xml`
   - **Modding → Custom UI Assets → Add:** name it exactly `CozyRollButton`, URL = `https://raw.githubusercontent.com/NommerTay/ozy-dice-roguelike/main/roll_button.png` (Global UI images must be registered here — a raw URL in the XML won't load).
4. Click **Save & Play**. Two cream buttons sit at the bottom-centre of everyone's screen: **🎲 Roll** and **Player Mat**.
5. Click **Roll**: the script downloads `data/face_database.json` and `data/dice_catalog.json` from GitHub, picks one of the pre-made dice at random, spawns it as a real **Custom Dice** object with its baked texture, stores the faces in the die's GM Notes + description, rolls it, and broadcasts the top face's effect when it settles.
6. Click **Player Mat**: the script spawns the Korts player board as a real **Custom Tile** (flat rectangle, 3:2 like the 1920×1280 art) in front of you, using the board PNG from the repo root. One mat per player — clicking again replaces your old mat. Move/rotate it like any tile; resize via `MAT_SCALE` in `Global.lua`.

No GitHub access / bad URL? The button still works — `Global.lua` falls back to a small embedded copy of the database (and says so in the log).

## Adding a new face (the drafting/collecting loop)

1. Generate a new master artwork in the same cozy pixel style (cream parchment background, chunky pixels, no text) and save it with the masters.
2. Add the face to the `FACES` list in `tools/build_faces.py` (id, name, pool, master, badge, value, effect) and run it — it writes the rimmed/badged icon and the new `data/face_database.json`. Upload the new icon PNG to the repo root.
3. Re-run `tools/generate_dice_textures.py` so dice using the new face get composed, and upload the new/changed `dice_NN.png` textures + `data/dice_catalog.json`. No Lua change — every table loads the new catalog next time it starts.

## Known prototype notes

- The dice are genuine TTS **Custom Dice**: each die's 6 faces are baked into one texture image (`dice_01.png` … `dice_13.png` in the repo root) by `tools/generate_dice_textures.py` — one die per legal composition, since a Custom Dice texture can't be composed at click-time inside TTS. The texture layout (3×2 grid of faces under an unused top band, value→cell map in the generator) was verified against real Custom Dice save files. To grow the dice pool, re-run the generator with more dice per composition and upload the new textures.
- This is test #1: build-and-roll only. Drafting between rounds, collecting/trading dice, and status-effect bookkeeping are the next scripts.
