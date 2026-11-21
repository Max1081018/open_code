"""Palette swaps for KayKit characters: their textures are an 8 x 4 grid of
gradient swatches, so a character is recoloured by remapping whole cells.

Run from godot/:  python3 tools/kaykit_palette.py
Writes assets/models/kaykit/textures/<name>.png
"""
import colorsys, os
from PIL import Image

SRC = "assets/models/kaykit/weapons"
OUT = "assets/models/kaykit/textures"
CELL_W, CELL_H = 128, 256  # 8 columns x 4 rows on a 1024 square

# name -> (source texture, {(col, row): (hue 0..1, saturation scale, value scale)})
SWAPS = {
    # Mira, the herbalist: the rogue's greens become plum and rose.
    "mira": ("rogue_texture.png", {(0, 1): (0.88, 0.9, 1.0), (1, 1): (0.92, 0.85, 1.05), (1, 2): (0.92, 0.85, 1.05)}),
    # Tobin, the travelling smith: leather instead of blue, a ginger beard.
    "tobin": ("barbarian_texture.png", {(0, 1): (0.07, 0.75, 0.85), (1, 1): (0.07, 0.75, 0.85), (2, 2): (0.07, 0.6, 0.8),
                                        (1, 0): (0.06, 1.6, 1.15)}),
}


def remap(cell: Image.Image, hue: float, sat: float, val: float) -> Image.Image:
    px = cell.load()
    for y in range(cell.height):
        for x in range(cell.width):
            r, g, b, a = px[x, y]
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            s2 = min(1.0, max(s, 0.25) * sat)
            v2 = min(1.0, v * val)
            r2, g2, b2 = colorsys.hsv_to_rgb(hue, s2, v2)
            px[x, y] = (int(r2 * 255), int(g2 * 255), int(b2 * 255), a)
    return cell


for name, (source, cells) in SWAPS.items():
    image = Image.open(os.path.join(SRC, source)).convert("RGBA")
    for (col, row), (hue, sat, val) in cells.items():
        box = (col * CELL_W, row * CELL_H, (col + 1) * CELL_W, (row + 1) * CELL_H)
        image.paste(remap(image.crop(box), hue, sat, val), box)
    image.save(os.path.join(OUT, name + ".png"))
    print("wrote", name)
