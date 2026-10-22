#!/usr/bin/env python3
"""
Cozy pixel-art icon generator for Cozy Dice Roguelike (TTS).
Draws every icon on a 32x32 pixel grid, then upscales x8 with NEAREST
so the chunky pixels stay crisp at 256x256. One shared palette = all
pools blend together visually.

Run:  python3 tools/generate_icons.py
"""
from PIL import Image, ImageDraw
import os

SIZE = 32
SCALE = 8
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icons")

# --- Shared cozy palette -------------------------------------------------
INK    = (62, 39, 35, 255)      # warm dark brown outline
CREAM  = (255, 243, 214, 255)   # face cream
WOOD   = (164, 116, 74, 255)
WOOD_D = (139, 94, 60, 255)
SAGE   = (127, 176, 105, 255)
MOSS   = (88, 129, 87, 255)
ROSE   = (229, 152, 155, 255)
ROSE_D = (201, 109, 118, 255)
SKY    = (168, 197, 214, 255)
SKY_D  = (110, 155, 180, 255)
GOLD   = (255, 201, 113, 255)
EMBER  = (242, 132, 130, 255)
EMBER_D= (214, 90, 82, 255)
GREY   = (178, 176, 168, 255)
GREY_D = (130, 128, 120, 255)
WHITE  = (255, 251, 240, 255)
PURPLE = (178, 157, 217, 255)
PURPLE_D=(139, 119, 185, 255)

def canvas():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)

def face_bg(d, tint):
    """Soft rounded cream face with a tinted rim - same on every die face."""
    d.rounded_rectangle([1, 1, 30, 30], radius=6, fill=tint)
    d.rounded_rectangle([3, 3, 28, 28], radius=5, fill=CREAM)

def save(img, sub, name):
    path = os.path.join(OUT, sub, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((SIZE*SCALE, SIZE*SCALE), Image.NEAREST).save(path)
    print("wrote", path)

def px(d, pts, fill):
    for x, y in pts:
        d.rectangle([x, y, x, y], fill=fill)

# --- MISSES (soft grey / dusty blue - 'nothing happened, and that's ok') --
def miss_cloud():
    img, d = canvas(); face_bg(d, SKY_D)
    d.ellipse([8, 12, 24, 22], fill=GREY)
    d.ellipse([11, 9, 20, 18], fill=GREY)
    d.rectangle([8, 17, 24, 21], fill=GREY)
    px(d, [(12, 24), (16, 25), (20, 24)], SKY_D)  # little raindrops
    return img

def miss_cracked_egg():
    img, d = canvas(); face_bg(d, SKY_D)
    d.ellipse([10, 8, 22, 24], fill=WHITE, outline=INK, width=1)
    px(d, [(13, 14), (16, 17), (14, 20), (18, 21)], GREY_D)  # crack
    d.ellipse([13, 15, 19, 21], fill=GOLD)  # yolk peeking through
    return img

def miss_tangled_yarn():
    img, d = canvas(); face_bg(d, SKY_D)
    d.ellipse([9, 10, 23, 24], fill=ROSE)
    d.arc([9, 10, 23, 24], 20, 160, fill=ROSE_D, width=2)
    d.arc([9, 10, 23, 24], 200, 340, fill=ROSE_D, width=2)
    d.line([21, 22, 27, 27], fill=INK, width=1)  # loose strand
    d.line([27, 27, 24, 28], fill=INK, width=1)
    return img

def miss_dropped_mug():
    img, d = canvas(); face_bg(d, SKY_D)
    d.rectangle([10, 10, 20, 20], fill=SKY)          # tipped mug body
    d.arc([18, 12, 24, 19], 270, 90, fill=INK, width=1)
    d.ellipse([7, 22, 25, 26], fill=WOOD)             # spilled cocoa puddle
    px(d, [(12, 23), (18, 24)], WOOD_D)
    return img

def miss_butterfly():
    img, d = canvas(); face_bg(d, SKY_D)
    d.ellipse([8, 11, 15, 18], fill=PURPLE)   # it fluttered away instead
    d.ellipse([17, 11, 24, 18], fill=PURPLE)
    d.rectangle([15, 11, 17, 21], fill=INK)
    px(d, [(11, 25), (16, 27), (21, 25)], GREY_D)  # dotted flight path
    return img

# --- ATTACKS (warm terracotta / ember rim) --------------------------------
def atk_wooden_sword():
    img, d = canvas(); face_bg(d, EMBER_D)
    d.polygon([(16, 5), (19, 9), (17, 20), (15, 20), (13, 9)], fill=WOOD)
    d.rectangle([12, 20, 20, 22], fill=INK)       # crossguard
    d.rectangle([15, 22, 17, 27], fill=WOOD_D)    # handle
    return img

def atk_bow():
    img, d = canvas(); face_bg(d, EMBER_D)
    d.arc([8, 6, 22, 26], 270, 90, fill=WOOD_D, width=2)
    d.line([15, 6, 15, 26], fill=GREY_D, width=1)  # string
    d.line([10, 16, 26, 16], fill=INK, width=1)   # arrow
    d.polygon([(26, 16), (22, 13), (22, 19)], fill=GREY)
    return img

def atk_ember():
    img, d = canvas(); face_bg(d, EMBER_D)
    d.polygon([(16, 5), (21, 14), (23, 19), (20, 25), (12, 25), (9, 19), (11, 14)], fill=EMBER)
    d.polygon([(16, 13), (19, 18), (18, 23), (14, 23), (13, 18)], fill=GOLD)
    return img

def atk_acorn_sling():
    img, d = canvas(); face_bg(d, EMBER_D)
    d.line([10, 6, 15, 16], fill=WOOD_D, width=2)  # sling arms
    d.line([22, 6, 17, 16], fill=WOOD_D, width=2)
    d.ellipse([12, 14, 20, 22], fill=WOOD)         # acorn
    d.rectangle([12, 13, 20, 16], fill=WOOD_D)     # acorn cap
    return img

def atk_paw_swipe():
    img, d = canvas(); face_bg(d, EMBER_D)
    d.ellipse([11, 14, 21, 24], fill=WOOD)         # paw pad
    for x in (9, 14, 19):
        d.ellipse([x, 8, x+4, 13], fill=WOOD)      # toe beans
    px(d, [(23, 9), (25, 13), (24, 18)], INK)     # swipe marks
    return img

# --- DEFENDS (sage / moss rim) ---------------------------------------------
def def_wooden_shield():
    img, d = canvas(); face_bg(d, MOSS)
    d.polygon([(9, 7), (23, 7), (23, 16), (16, 26), (9, 16)], fill=WOOD)
    d.polygon([(11, 9), (21, 9), (21, 15), (16, 23), (11, 15)], fill=WOOD_D)
    d.ellipse([14, 12, 18, 16], fill=GOLD)
    return img

def def_knitted_blanket():
    img, d = canvas(); face_bg(d, MOSS)
    d.rounded_rectangle([8, 9, 24, 24], radius=3, fill=ROSE)
    for y in (13, 17, 21):
        d.line([8, y, 24, y], fill=ROSE_D, width=1)  # knit rows
    px(d, [(9, 25), (13, 25), (17, 25), (21, 25)], ROSE_D)  # fringe
    return img

def def_pot_lid():
    img, d = canvas(); face_bg(d, MOSS)
    d.ellipse([8, 9, 24, 25], fill=GREY)
    d.ellipse([11, 12, 21, 22], fill=WHITE)
    d.ellipse([14, 15, 18, 19], fill=GREY_D)  # lid knob-as-handle
    return img

def def_stone_wall():
    img, d = canvas(); face_bg(d, MOSS)
    d.rectangle([7, 10, 25, 25], fill=GREY)
    d.line([7, 15, 25, 15], fill=GREY_D, width=1)
    d.line([7, 20, 25, 20], fill=GREY_D, width=1)
    d.line([16, 10, 16, 15], fill=GREY_D, width=1)
    d.line([11, 15, 11, 20], fill=GREY_D, width=1)
    d.line([21, 15, 21, 20], fill=GREY_D, width=1)
    d.ellipse([19, 6, 25, 11], fill=SAGE)  # moss on top
    return img

def def_umbrella():
    img, d = canvas(); face_bg(d, MOSS)
    d.pieslice([7, 7, 25, 21], 180, 360, fill=SKY)
    px(d, [(9, 14), (15, 14), (21, 14)], SKY_D)
    d.line([16, 14, 16, 24], fill=INK, width=1)
    d.arc([13, 21, 19, 27], 0, 180, fill=INK, width=1)  # hook handle
    return img

# --- STATUSES (lilac rim) ---------------------------------------------------
def sta_poison_shroom():
    img, d = canvas(); face_bg(d, PURPLE_D)
    d.rectangle([14, 16, 18, 24], fill=WOOD)      # stem (drawn first, cap over top)
    d.pieslice([8, 7, 24, 19], 180, 360, fill=PURPLE)
    px(d, [(12, 10), (18, 9), (15, 13)], WHITE)  # spots
    return img

def sta_burn():
    img, d = canvas(); face_bg(d, PURPLE_D)
    d.rectangle([13, 16, 19, 25], fill=WOOD_D)    # little log
    d.polygon([(16, 6), (20, 13), (21, 18), (18, 22), (14, 22), (11, 18), (12, 13)], fill=EMBER)
    d.polygon([(16, 14), (18, 18), (17, 21), (15, 21), (14, 18)], fill=GOLD)
    return img

def sta_chill():
    img, d = canvas(); face_bg(d, PURPLE_D)
    for pts in ([(16, 7), (16, 25)], [(9, 11), (23, 21)], [(23, 11), (9, 21)]):
        d.line(pts, fill=SKY_D, width=2)
    d.ellipse([13, 13, 19, 19], fill=SKY)
    return img

def sta_stun():
    img, d = canvas(); face_bg(d, PURPLE_D)
    for cx, cy in ((10, 11), (21, 9), (16, 16)):
        d.polygon([(cx, cy-3), (cx+1, cy-1), (cx+3, cy-1), (cx+2, cy+1),
                   (cx+3, cy+3), (cx, cy+2), (cx-3, cy+3), (cx-2, cy+1),
                   (cx-3, cy-1), (cx-1, cy-1)], fill=GOLD)  # dizzy stars
    d.arc([10, 18, 22, 27], 180, 360, fill=INK, width=1)  # wobbly mouth line
    return img

def sta_bloom():
    img, d = canvas(); face_bg(d, PURPLE_D)
    d.line([16, 25, 16, 15], fill=MOSS, width=2)  # stem
    d.ellipse([10, 15, 16, 19], fill=SAGE)        # leaf
    for cx, cy in ((16, 7), (11, 11), (21, 11), (13, 14), (19, 14)):
        d.ellipse([cx-2, cy-2, cx+2, cy+2], fill=ROSE)  # petals
    d.ellipse([14, 10, 18, 14], fill=GOLD)        # centre
    return img

# --- ROLL BUTTON -------------------------------------------------------------
def roll_button():
    img, d = canvas()
    d.rounded_rectangle([1, 1, 30, 30], radius=7, fill=WOOD_D)
    d.rounded_rectangle([3, 3, 28, 28], radius=6, fill=CREAM)
    d.rounded_rectangle([8, 8, 24, 24], radius=4, fill=WHITE, outline=INK, width=1)
    for x, y in ((12, 12), (20, 12), (16, 16), (12, 20), (20, 20)):
        d.rectangle([x-1, y-1, x+1, y+1], fill=EMBER_D)  # die pips (a 5)
    return img

if __name__ == "__main__":
    save(miss_cloud(),        "misses",   "miss_cloud.png")
    save(miss_cracked_egg(),  "misses",   "miss_cracked_egg.png")
    save(miss_tangled_yarn(), "misses",   "miss_tangled_yarn.png")
    save(miss_dropped_mug(),  "misses",   "miss_dropped_mug.png")
    save(miss_butterfly(),    "misses",   "miss_butterfly.png")

    save(atk_wooden_sword(),  "attacks",  "attack_wooden_sword.png")
    save(atk_bow(),           "attacks",  "attack_bow.png")
    save(atk_ember(),         "attacks",  "attack_ember.png")
    save(atk_acorn_sling(),   "attacks",  "attack_acorn_sling.png")
    save(atk_paw_swipe(),     "attacks",  "attack_paw_swipe.png")

    save(def_wooden_shield(), "defends",  "defend_wooden_shield.png")
    save(def_knitted_blanket(),"defends", "defend_knitted_blanket.png")
    save(def_pot_lid(),       "defends",  "defend_pot_lid.png")
    save(def_stone_wall(),    "defends",  "defend_stone_wall.png")
    save(def_umbrella(),      "defends",  "defend_umbrella.png")

    save(sta_poison_shroom(), "statuses", "status_poison_shroom.png")
    save(sta_burn(),          "statuses", "status_burn.png")
    save(sta_chill(),         "statuses", "status_chill.png")
    save(sta_stun(),          "statuses", "status_stun.png")
    save(sta_bloom(),         "statuses", "status_bloom.png")

    save(roll_button(),       "",         "roll_button.png")
    print("Done: 21 icons")
