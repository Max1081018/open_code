"""Draws the held-equipment art that no Kenney pack provides in a holdable
form: a hand torch (the pack's torch is a wall sconce) and two shields.

Kenney's style: flat fills, a soft dark outline, one highlight band and
one shade band per shape. Drawn at 4x and downsampled, so edges are clean.
Original artwork, released with the project (CC0, as the Kenney art is).

Run from godot/:  python3 tools/draw_equipment.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets/equipment")
S = 4
OUTLINE = (45, 40, 58, 255)


def canvas(w, h):
    return Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))


def finish(im, name):
    # Outline: dilate the silhouette, darken, put the art on top.
    alpha = im.split()[3]
    grown = alpha.filter(ImageFilter.MaxFilter(4 * S + 1))
    outline = Image.new("RGBA", im.size, OUTLINE)
    outline.putalpha(grown.point(lambda v: 150 if v > 0 else 0))
    base = Image.new("RGBA", im.size, (0, 0, 0, 0))
    base.alpha_composite(outline)
    base.alpha_composite(im)
    small = base.resize((im.width // S, im.height // S), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    small.save(os.path.join(OUT, name + ".png"))
    print("wrote", name, small.size)


def torch():
    w, h = 48, 160
    im = canvas(w, h)
    d = ImageDraw.Draw(im)
    cx = w * S // 2
    # Handle: a tapered stick, light on the left, shaded on the right.
    d.polygon([(cx - 7 * S, 38 * S), (cx + 7 * S, 38 * S), (cx + 5 * S, 154 * S), (cx - 5 * S, 154 * S)],
              fill=(150, 98, 60, 255))
    d.polygon([(cx + 1 * S, 38 * S), (cx + 7 * S, 38 * S), (cx + 5 * S, 154 * S), (cx + 1 * S, 154 * S)],
              fill=(122, 76, 46, 255))
    d.rectangle([cx - 5 * S, 40 * S, cx - 3 * S, 150 * S], fill=(178, 124, 80, 255))
    # Wrapped head: cloth bands soaked in pitch.
    for i, y in enumerate(range(14, 46, 8)):
        colour = (96, 70, 52, 255) if i % 2 == 0 else (120, 90, 64, 255)
        d.rounded_rectangle([cx - 13 * S, y * S, cx + 13 * S, (y + 9) * S], radius=4 * S, fill=colour)
    d.rounded_rectangle([cx - 11 * S, 14 * S, cx - 4 * S, 44 * S], radius=3 * S, fill=(140, 108, 78, 120))
    # Charred top.
    d.ellipse([cx - 13 * S, 6 * S, cx + 13 * S, 22 * S], fill=(58, 44, 40, 255))
    d.ellipse([cx - 8 * S, 9 * S, cx + 8 * S, 17 * S], fill=(230, 120, 50, 255))
    finish(im, "torch_held")


def shield(name, face, face_dark, rim, rim_light, boss):
    w = h = 128
    im = canvas(w, h)
    d = ImageDraw.Draw(im)
    pad = 8 * S
    box = [pad, pad, w * S - pad, h * S - pad]
    d.ellipse(box, fill=rim)
    inner = [box[0] + 9 * S, box[1] + 9 * S, box[2] - 9 * S, box[3] - 9 * S]
    d.ellipse(inner, fill=face)
    # Planks: vertical boards across the face.
    board = (inner[2] - inner[0]) / 5
    for i in range(1, 5):
        x = inner[0] + board * i
        d.line([(x, inner[1]), (x, inner[3])], fill=face_dark, width=2 * S)
    # Shade on the lower right, light on the upper left: it is round.
    shade = canvas(w, h)
    sd = ImageDraw.Draw(shade)
    sd.ellipse([inner[0] + 18 * S, inner[1] + 18 * S, inner[2] + 30 * S, inner[3] + 30 * S], fill=(0, 0, 0, 70))
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).ellipse(inner, fill=255)
    shade.putalpha(Image.composite(shade.split()[3], Image.new("L", im.size, 0), mask))
    im.alpha_composite(shade)
    d = ImageDraw.Draw(im)
    d.arc(box, 200, 290, fill=rim_light, width=4 * S)
    # Boss: the domed iron centre.
    c = w * S // 2
    d.ellipse([c - 18 * S, c - 18 * S, c + 18 * S, c + 18 * S], fill=boss)
    d.ellipse([c - 12 * S, c - 14 * S, c + 4 * S, c + 2 * S], fill=(255, 255, 255, 90))
    # Rivets round the rim.
    import math
    for k in range(10):
        a = k / 10 * math.tau
        rx, ry = c + math.cos(a) * 50.5 * S, c + math.sin(a) * 50.5 * S
        d.ellipse([rx - 2.5 * S, ry - 2.5 * S, rx + 2.5 * S, ry + 2.5 * S], fill=rim_light)
    finish(im, name)


if __name__ == "__main__":
    torch()
    shield("shield_wood", (172, 116, 70, 255), (128, 84, 50, 255), (120, 110, 118, 255),
           (196, 190, 200, 255), (150, 146, 160, 255))
    shield("shield_iron", (92, 112, 150, 255), (70, 86, 118, 255), (150, 152, 166, 255),
           (225, 228, 236, 255), (200, 170, 90, 255))
