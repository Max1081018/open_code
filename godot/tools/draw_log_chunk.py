"""Draws assets/rendered/log-chunk.png (run: python3 tools/draw_log_chunk.py assets/rendered/log-chunk.png).
A chunk of split log: bark body, pale end grain with growth rings, dark outline."""
import sys
from PIL import Image, ImageDraw, ImageFilter
S = 4  # supersample
W, H = 96 * S, 64 * S
def chunk(seed, out):
    import random
    rnd = random.Random(seed)
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    o = 5 * S                     # outline width
    top, bot = 10 * S, 54 * S
    left, right = 24 * S, 72 * S
    ew = 15 * S                   # half-width of the end ellipse
    bark, bark_dark, bark_light = (122, 78, 46), (86, 52, 30), (152, 102, 62)
    # Outline silhouette first (slightly larger), then fills.
    d.rounded_rectangle((left - ew - o, top - o, right, bot + o), radius=14 * S, fill=(52, 30, 18))
    d.ellipse((right - ew - o, top - o, right + ew + o, bot + o), fill=(52, 30, 18))
    d.rounded_rectangle((left - ew, top, right, bot), radius=12 * S, fill=bark)
    # Bark ridges along the body, and a shade on the underside.
    d.rectangle((left - ew + 6 * S, bot - 12 * S, right, bot), fill=bark_dark)
    for i in range(6):
        y = top + rnd.randint(6, 40) * S
        x0 = left - ew + rnd.randint(4, 20) * S
        d.line((x0, y, x0 + rnd.randint(18, 40) * S, y + rnd.randint(-2, 2) * S), fill=bark_dark, width=3 * S)
    d.line((left - ew + 10 * S, top + 7 * S, right - 8 * S, top + 7 * S), fill=bark_light, width=4 * S)
    # The split end: pale wood with rings and a crack.
    d.ellipse((right - ew, top, right + ew, bot), fill=(232, 196, 140))
    cx, cy = right + 1 * S, (top + bot) // 2
    for r in (0.78, 0.55, 0.32):
        rx, ry = ew * r, (bot - top) / 2 * r
        d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), outline=(196, 150, 96), width=2 * S)
    d.ellipse((cx - 2 * S, cy - 2 * S, cx + 2 * S, cy + 2 * S), fill=(170, 120, 70))
    d.line((cx, cy, cx + ew * 0.7, cy - 10 * S), fill=(150, 104, 60), width=2 * S)
    im = im.resize((W // S, H // S), Image.LANCZOS)
    im.save(out)
chunk(1, sys.argv[1])
