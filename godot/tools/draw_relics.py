"""Draws the relic icons (assets/items/relic_<name>.png): a gold-rimmed amulet
on a short chain, a coloured gem, and a white glyph for what it does.
Same outlined toon style as the other drawn items.

Run from godot/:  python3 tools/draw_relics.py
"""
import math
from PIL import Image, ImageDraw

S = 4
N = 128 * S
OUT = "assets/items/relic_%s.png"
INK = (46, 28, 30, 255)

# name -> (gem colour, glyph)
RELICS = {
    "featherbone": ((150, 205, 255), "feather"),
    "ember_heart": ((236, 84, 46), "flame"),
    "deepsong": ((80, 196, 170), "rings"),
    "moth_lantern": ((246, 214, 110), "moth"),
    "bulwark": ((120, 132, 168), "shield"),
    "swiftroot": ((120, 200, 96), "arrow"),
    "seers_eye": ((176, 120, 236), "eye"),
    "luckstone": ((96, 220, 120), "clover"),
}


def p(x, y):
    return (x * S, y * S)


def glyph(d, kind, c=(255, 252, 240, 255)):
    cx, cy = 64, 76
    if kind == "feather":
        d.polygon([p(cx - 4, cy + 22), p(cx - 14, cy - 2), p(cx + 2, cy - 24), p(cx + 12, cy - 4), p(cx + 2, cy + 18)], fill=c)
        d.line([p(cx - 2, cy + 24), p(cx + 4, cy - 18)], fill=INK, width=3 * S)
    elif kind == "flame":
        d.polygon([p(cx, cy - 26), p(cx + 14, cy), p(cx + 10, cy + 18), p(cx - 10, cy + 18), p(cx - 14, cy), p(cx - 4, cy - 8)], fill=c)
        d.polygon([p(cx, cy - 4), p(cx + 6, cy + 8), p(cx, cy + 16), p(cx - 6, cy + 8)], fill=(255, 180, 80, 255))
    elif kind == "rings":
        for r in (8, 15, 22):
            d.arc([p(cx - r, cy - r), p(cx + r, cy + r)], 200, 340, fill=c, width=4 * S)
        d.ellipse([p(cx - 5, cy - 1), p(cx + 5, cy + 9)], fill=c)
    elif kind == "moth":
        d.ellipse([p(cx - 22, cy - 16), p(cx - 2, cy + 6)], fill=c)
        d.ellipse([p(cx + 2, cy - 16), p(cx + 22, cy + 6)], fill=c)
        d.ellipse([p(cx - 16, cy + 2), p(cx - 2, cy + 18)], fill=c)
        d.ellipse([p(cx + 2, cy + 2), p(cx + 16, cy + 18)], fill=c)
        d.rectangle([p(cx - 2, cy - 14), p(cx + 2, cy + 18)], fill=INK)
    elif kind == "shield":
        d.polygon([p(cx - 18, cy - 20), p(cx + 18, cy - 20), p(cx + 16, cy + 4), p(cx, cy + 22), p(cx - 16, cy + 4)], fill=c)
        d.line([p(cx, cy - 16), p(cx, cy + 16)], fill=INK, width=3 * S)
        d.line([p(cx - 13, cy - 4), p(cx + 13, cy - 4)], fill=INK, width=3 * S)
    elif kind == "arrow":
        for dx in (-10, 4):
            d.polygon([p(cx + dx, cy - 18), p(cx + dx + 16, cy), p(cx + dx, cy + 18), p(cx + dx, cy + 8), p(cx + dx + 6, cy), p(cx + dx, cy - 8)], fill=c)
    elif kind == "eye":
        d.polygon([p(cx - 24, cy), p(cx - 8, cy - 14), p(cx + 8, cy - 14), p(cx + 24, cy), p(cx + 8, cy + 14), p(cx - 8, cy + 14)], fill=c)
        d.ellipse([p(cx - 9, cy - 9), p(cx + 9, cy + 9)], fill=(110, 60, 170, 255))
        d.ellipse([p(cx - 4, cy - 4), p(cx + 4, cy + 4)], fill=INK)
    elif kind == "clover":
        for a in range(4):
            ang = a * math.pi / 2 + math.pi / 4
            x, y = cx + math.cos(ang) * 10, cy - 2 + math.sin(ang) * 10
            d.ellipse([p(x - 9, y - 9), p(x + 9, y + 9)], fill=c)
        d.line([p(cx, cy + 4), p(cx + 6, cy + 22)], fill=c, width=4 * S)


for name, (gem, kind) in RELICS.items():
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Chain loop and bail.
    d.ellipse([p(52, 4), p(76, 28)], outline=INK, width=9 * S)
    d.ellipse([p(52, 4), p(76, 28)], outline=(236, 190, 80, 255), width=4 * S)
    # Rim: ink outline, gold, darker inner bevel; then the gem.
    d.ellipse([p(16, 26), p(112, 122)], fill=INK)
    d.ellipse([p(21, 31), p(107, 117)], fill=(240, 194, 82, 255))
    d.ellipse([p(29, 39), p(99, 109)], fill=(178, 120, 40, 255))
    d.ellipse([p(33, 43), p(95, 105)], fill=gem + (255,))
    # A highlight across the gem.
    d.chord([p(38, 46), p(90, 98)], 200, 290, fill=tuple(min(255, int(v * 0.5 + 128)) for v in gem) + (255,))
    glyph(d, kind)
    im = im.resize((128, 128), Image.LANCZOS)
    im.save(OUT % name)
    print("drew", name)
