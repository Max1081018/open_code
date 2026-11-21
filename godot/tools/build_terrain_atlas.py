"""Builds assets/tiles/terrain.png from real material textures (ambientCG,
CC0; sources in tools/terrain_src) instead of flat vector tiles.

Layout (as the game expects): 16 columns, one per neighbour mask (bit set =
that side open to air: 1 up, 2 down, 4 left, 8 right), 9 rows, one per
material, 128 px tiles. Every tile of a material shows the same seamless
texture, so neighbours join invisibly; exposed sides get soft shading (a
sunlit lip on top, shadow beneath, rounded outer corners) instead of black
outlines, and grass gets a ragged mossy cap.

Run from godot/:  python3 tools/build_terrain_atlas.py
(missing source textures are fetched from ambientCG first; they are not
kept in the repository).
"""
import io
import os
import urllib.request
import zipfile

import numpy as np
from PIL import Image, ImageEnhance

T = 128
SRC = "tools/terrain_src/"
UP, DOWN, LEFT, RIGHT = 1, 2, 4, 8
rng = np.random.default_rng(7)


def fetch(name):
    """ambientCG's 1K JPG set for `name`, keeping only the colour map."""
    path = SRC + name + ".jpg"
    if os.path.exists(path):
        return
    os.makedirs(SRC, exist_ok=True)
    url = "https://ambientcg.com/get?file=%s_1K-JPG.zip" % name
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    data = urllib.request.urlopen(request, timeout=60).read()
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        colour = next(n for n in z.namelist() if n.endswith("_Color.jpg"))
        with open(path, "wb") as f:
            f.write(z.read(colour))


def tex(name, tint=(1, 1, 1), contrast=1.0, bright=1.0, level=0.62):
    """A material's texture at tile size, its mean brightness set to `level`
    (the game's light and grading were tuned for bright art: photographic
    soil at its natural 0.3 would read as black once lit)."""
    fetch(name)
    im = Image.open(SRC + name + ".jpg").convert("RGB").resize((T, T), Image.LANCZOS)
    im = ImageEnhance.Contrast(im).enhance(contrast)
    a = np.asarray(im).astype(np.float32) / 255.0
    a = a * (level / max(float((a @ np.array([0.299, 0.587, 0.114])).mean()), 1e-3)) * bright
    return np.clip(a * np.array(tint, dtype=np.float32), 0, 1)


def hue_shift_violet(a):
    grey = a.mean(axis=2, keepdims=True)
    return np.clip(grey * np.array([0.78, 0.55, 1.15]) + 0.05, 0, 1)


# Material bodies (rows in order).
BODIES = {
    "grass": lambda: tex("Ground048", (1.0, 0.95, 0.9), 1.05, 0.95),
    "soil": lambda: tex("Ground048", (1.0, 0.95, 0.9), 1.05, 0.92),
    "sand": lambda: tex("Ground054", (1.05, 1.0, 0.9), 1.15, 1.05, 0.7),
    "snow": lambda: tex("Snow010A", (0.97, 0.99, 1.02), 1.25, 1.0, 0.86),
    "rock": lambda: tex("Rock058", (0.95, 0.97, 1.0), 1.15, 1.05),
    "brick": lambda: tex("Bricks089", (0.95, 0.95, 0.92), 1.1, 1.0),
    "crystal": lambda: hue_shift_violet(tex("Rock058", contrast=1.3, bright=1.15)),
    "basalt": lambda: tex("Rock058", (0.7, 0.55, 0.55), 1.25, 1.0, 0.42),
    "planks": lambda: tex("Planks012", (1.0, 0.95, 0.88), 1.1, 1.05),
}
MATERIALS = list(BODIES)
SQUARE = {"brick", "planks"}   # masonry and timber keep crisp corners
GRASS = tex("Grass004", (0.82, 0.95, 0.72), 1.2, 0.95, 0.6)


def ragged(n, base, amp, seed):
    """An irregular edge depth per column (or row), smooth-ish noise."""
    r = np.random.default_rng(seed)
    pts = r.uniform(-1, 1, n // 8 + 2)
    xs = np.linspace(0, len(pts) - 1, n)
    return base + amp * np.interp(xs, np.arange(len(pts)), pts)


def tile(material, mask, body):
    rgb = body.copy()
    alpha = np.ones((T, T), np.float32)
    y, x = np.mgrid[0:T, 0:T].astype(np.float32)
    shade = np.ones((T, T), np.float32)
    # Exposed sides: shadow toward the edge, strongest beneath an overhang.
    if mask & DOWN:
        shade *= 1.0 - 0.5 * np.clip(1 - (T - 1 - y) / 18.0, 0, 1) ** 2
    if mask & LEFT:
        shade *= 1.0 - 0.32 * np.clip(1 - x / 14.0, 0, 1) ** 2
    if mask & RIGHT:
        shade *= 1.0 - 0.32 * np.clip(1 - (T - 1 - x) / 14.0, 0, 1) ** 2
    if mask & UP:
        # The sunlit lip, then a band of shade just under it.
        shade *= 1.0 + 0.22 * np.clip(1 - y / 3.0, 0, 1) - 0.12 * np.exp(-((y - 7) / 4.0) ** 2)
    rgb = rgb * shade[..., None]
    if material == "grass" and mask & UP:
        depth = ragged(T, 22, 7, mask * 31 + 3)
        cap = y < depth[None, :]
        under = (y >= depth[None, :]) & (y < depth[None, :] + 4)
        grass = GRASS * (1.0 + 0.25 * np.clip(1 - y / 4.0, 0, 1))[..., None]
        rgb = np.where(cap[..., None], grass, rgb)
        rgb = np.where(under[..., None], rgb * 0.55, rgb)
    if material == "snow" and mask & UP:
        rgb = rgb * (1.0 + 0.12 * np.clip(1 - y / 10.0, 0, 1))[..., None]
    # Rounded outer corners where two adjacent sides are open; a slightly
    # ragged silhouette on natural materials.
    radius = 5.0 if material in SQUARE else 16.0
    for vert, horiz, cy, cx in [(UP, LEFT, radius, radius), (UP, RIGHT, radius, T - 1 - radius),
                                (DOWN, LEFT, T - 1 - radius, radius), (DOWN, RIGHT, T - 1 - radius, T - 1 - radius)]:
        if mask & vert and mask & horiz:
            region = ((y < cy) if vert == UP else (y > cy)) & ((x < cx) if horiz == LEFT else (x > cx))
            d = np.sqrt((y - cy) ** 2 + (x - cx) ** 2)
            alpha = np.where(region, np.clip(radius + 0.5 - d, 0, 1), alpha)
    if material not in SQUARE:
        for side, axis_len in [(UP, None), (LEFT, None), (RIGHT, None)]:
            if mask & side:
                cut = ragged(T, 1.5, 1.5, mask * 7 + side)
                if side == UP:
                    alpha = np.where(y < cut[None, :], 0, alpha)
                elif side == LEFT:
                    alpha = np.where(x < cut[:, None], 0, alpha)
                else:
                    alpha = np.where(x > T - 1 - cut[:, None], 0, alpha)
    out = np.concatenate([np.clip(rgb, 0, 1), alpha[..., None]], axis=2)
    return Image.fromarray((out * 255).astype(np.uint8), "RGBA")


def main():
    atlas = Image.new("RGBA", (T * 16, T * len(MATERIALS)), (0, 0, 0, 0))
    for row, material in enumerate(MATERIALS):
        body = BODIES[material]()
        for mask in range(16):
            atlas.paste(tile(material, mask, body), (mask * T, row * T))
    atlas.save("assets/tiles/terrain.png", optimize=True)
    print("terrain atlas: %d materials x 16 masks" % len(MATERIALS))


main()
