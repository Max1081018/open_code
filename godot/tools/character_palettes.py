"""Texture variants for the Quaternius characters (CC0), so the cast differs
in palette as well as in parts. Run from godot/:  python3 tools/character_palettes.py"""
import colorsys
from PIL import Image

Q = "assets/models/quaternius/"


def remap(src, dst, fn):
    im = Image.open(Q + src).convert("RGB")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b = (c / 255 for c in px[x, y])
            h, s, v = colorsys.rgb_to_hsv(r, g, b)
            h, s, v = fn(h, s, v)
            r, g, b = colorsys.hsv_to_rgb(h % 1.0, min(max(s, 0), 1), min(max(v, 0), 1))
            px[x, y] = (int(r * 255), int(g * 255), int(b * 255))
    im.save(Q + "variants/" + dst, optimize=True)
    print("wrote", dst)


def dusk(h, s, v):
    # The wanderer's cloak: greens turn to a deep charcoal teal.
    if 0.18 < h < 0.45 and s > 0.2:
        return 0.50, s * 0.45, v * 0.62
    return h, s * 0.85, v * 0.92


def steel(h, s, v):
    # Sir Aldous: cool steel and worn leather.
    if s < 0.3:
        return 0.6, 0.12, v * 0.95
    return h, s * 0.7, v * 0.9


def lavender(h, s, v):
    # Wren: undyed cloth becomes lavender wool.
    if s < 0.3 and v > 0.45:
        return 0.72, 0.32, v * 0.92
    return h, s, v


def ash(h, s, v):
    # The risen dead: grey-green, bloodless skin.
    return 0.22, s * 0.25, v * 0.62


def rust(h, s, v):
    # The Rusted Warden: oxidised plate.
    return 0.03, min(s * 1.1 + 0.2, 0.75), v * 0.6


def gloam(h, s, v):
    # The Gloam: violet-black rags.
    return 0.76, min(s * 0.8 + 0.25, 0.6), v * 0.45


remap("outfits/T_Ranger_BaseColor.png", "ranger_dusk.png", dusk)
remap("outfits/T_Ranger_3_BaseColor.png", "ranger_steel.png", steel)
remap("outfits/T_Peasant_BaseColor.png", "peasant_lavender.png", lavender)
remap("bodies/T_Superhero_Male_Dark.png", "skin_ash_male.png", ash)
remap("bodies/T_Superhero_Female_Dark_BaseColor.png", "skin_ash_female.png", ash)
remap("outfits/T_Ranger_BaseColor.png", "ranger_rust.png", rust)
remap("outfits/T_Peasant_2_BaseColor.png", "peasant_gloam.png", gloam)
remap("outfits/T_Peasant_2_BaseColor.png", "peasant_rags.png", lambda h, s, v: (h, s * 0.5, v * 0.7))
