"""Draws the app icons: a chunky low-poly fish rising to a hook over the sea.

Writes assets/icon/icon_192.png (legacy launcher), icon_fg_432.png and
icon_bg_432.png (Android adaptive), plus icon.png for the project.
Run: python3 tools/make_icon.py
"""
import math
from PIL import Image, ImageDraw, ImageFilter

SEA_TOP = (86, 200, 226)
SEA_BOT = (22, 92, 148)
BODY = (247, 162, 61)
BODY_DARK = (214, 118, 40)
BELLY = (255, 225, 170)
FIN = (240, 124, 48)
INK = (28, 42, 62)
LINE = (255, 255, 255)


def lerp(a, b, t):
    return tuple(int(round(x + (y - x) * t)) for x, y in zip(a, b))


def background(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(size):
        d.line([(0, y), (size, y)], fill=lerp(SEA_TOP, SEA_BOT, (y / size) ** 1.15))
    # a couple of lighter water bands so it isn't a flat gradient
    for k, (cy, h, a) in enumerate([(0.52, 0.055, 34), (0.70, 0.045, 26), (0.86, 0.04, 20)]):
        band = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        bd = ImageDraw.Draw(band)
        y0 = size * cy
        pts = []
        for x in range(0, size + 8, 8):
            pts.append((x, y0 + math.sin(x / size * math.pi * 3 + k) * size * 0.012))
        pts += [(size, y0 + size * h), (0, y0 + size * h)]
        bd.polygon(pts, fill=(255, 255, 255, a))
        img = Image.alpha_composite(img, band)
    return img


def fish(size, scale=1.0):
    """A low-poly fish on a transparent layer, centred, nose up-right."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2
    u = size * 0.0075 * scale          # one unit

    def P(x, y):
        return (c + x * u, c + y * u)

    # tail
    d.polygon([P(-46, 0), P(-66, -22), P(-70, 24)], fill=FIN)
    d.polygon([P(-46, 0), P(-66, -22), P(-58, 2)], fill=lerp(FIN, INK, 0.18))
    # top fin
    d.polygon([P(-10, -22), P(6, -42), P(20, -20)], fill=FIN)
    # bottom fin
    d.polygon([P(-6, 20), P(-16, 36), P(10, 24)], fill=lerp(FIN, INK, 0.12))
    # body: faceted diamond
    body = [P(44, -2), P(16, -28), P(-20, -24), P(-46, 0), P(-20, 26), P(16, 26)]
    d.polygon(body, fill=BODY)
    # darker top facet, pale belly
    d.polygon([P(44, -2), P(16, -28), P(-20, -24), P(-46, 0)], fill=BODY_DARK)
    d.polygon([P(-46, 0), P(-20, 26), P(16, 26), P(30, 10)], fill=BELLY)
    # gill plate
    d.polygon([P(22, -24), P(14, 24), P(26, 20), P(32, -18)], fill=lerp(BODY, (255, 255, 255), 0.25))
    # eye
    d.ellipse([P(28, -14)[0], P(28, -14)[1], P(40, -2)[0], P(40, -2)[1]], fill=(255, 255, 255))
    d.ellipse([P(32, -11)[0], P(32, -11)[1], P(39, -4)[0], P(39, -4)[1]], fill=INK)
    return img


def hook_and_line(size, scale=1.0):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2
    u = size * 0.0075 * scale
    w = max(2, int(size * 0.018 * scale))
    x = c + 44 * u
    d.line([(x, 0), (x, c - 30 * u)], fill=LINE, width=w)
    # hook: a J under the line
    box = [x - 17 * u, c - 42 * u, x + 13 * u, c - 12 * u]
    d.arc(box, start=0, end=180, fill=LINE, width=w)
    d.line([(x + 13 * u, c - 27 * u), (x + 13 * u, c - 34 * u)], fill=LINE, width=w)
    return img


def compose(size, with_bg=True, fish_scale=1.0, shadow=True):
    img = background(size) if with_bg else Image.new("RGBA", (size, size), (0, 0, 0, 0))
    f = fish(size, fish_scale)
    h = hook_and_line(size, fish_scale)
    f = f.rotate(-14, resample=Image.BICUBIC, center=(size / 2, size / 2))
    layer = Image.alpha_composite(h, f)
    if shadow:
        sh = layer.split()[3].point(lambda a: int(a * 0.33))
        s = Image.new("RGBA", (size, size), (10, 30, 55, 0))
        s.putalpha(sh)
        s = s.filter(ImageFilter.GaussianBlur(size * 0.018))
        s = s.transform(s.size, Image.AFFINE, (1, 0, -size * 0.012, 0, 1, -size * 0.022))
        img = Image.alpha_composite(img, s)
    return Image.alpha_composite(img, layer)


def rounded(img, radius_frac=0.22):
    size = img.size[0]
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1],
                                           radius=int(size * radius_frac), fill=255)
    out = img.copy()
    out.putalpha(mask)
    return out


if __name__ == "__main__":
    # Legacy launcher icon and project icon: full square, rounded.
    rounded(compose(192, fish_scale=0.84)).save("assets/icon/icon_192.png")
    rounded(compose(512, fish_scale=0.84)).save("assets/icon/icon.png")
    # Adaptive: background fills the square, foreground sits in the safe zone
    # (the launcher crops up to a third of each edge).
    background(432).save("assets/icon/icon_bg_432.png")
    compose(432, with_bg=False, fish_scale=0.58).save("assets/icon/icon_fg_432.png")
    print("icons written")
