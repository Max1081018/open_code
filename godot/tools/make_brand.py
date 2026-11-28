#!/usr/bin/env python3
"""Ethereal Tales brand pipeline: one master artwork -> every icon, the
splash and the in-game title logo.

    python3 tools/make_brand.py [MASTER.png]        (from godot/)

With no argument it rebuilds from assets/brand/icon_reference.png. Outputs:
  assets/brand/icon_master.png        full-bleed square master (corners trimmed)
  assets/brand/launcher_192.png       legacy launcher icon
  assets/brand/adaptive_fg_432.png    adaptive foreground: the art inside the
                                      launcher's safe zone, so the title stays
                                      readable under circle and squircle masks
  assets/brand/adaptive_bg_432.png    adaptive background: the art, blurred, to
                                      fill the layer's bleed
  assets/brand/icon_small_96.png      small-size version (her face and flower:
                                      the title is unreadable at 48 px)
  assets/brand/splash.png             boot splash, art centred on the brand dusk
  icon.png                            project / desktop icon (256)
  assets/ui/front/logo.png            in-game title "ETHEREAL TALES" (1143x174)
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BRAND = os.path.join(ROOT, "assets", "brand")
DUSK = (15, 11, 30)          # the splash and adaptive bleed colour


def full_bleed(src: Image.Image) -> Image.Image:
    """Trim the reference's rounded black corners: a clean square."""
    w, h = src.size
    side = min(w, h)
    im = src.crop(((w - side) // 2, (h - side) // 2, (w + side) // 2, (h + side) // 2)).convert("RGB")
    t = round(side * 0.034)   # the rounded corners reach ~3.1% in
    return im.crop((t, t, side - t, side - t))


def adaptive(master: Image.Image):
    # Android shows the middle 72 of the layer's 108 dp (circle masks less):
    # the art sits at 360 of 432 px so its title clears the mask.
    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    art = master.resize((360, 360), Image.LANCZOS).convert("RGBA")
    fg.paste(art, (36, 36))
    bg = master.resize((432, 432), Image.LANCZOS).filter(ImageFilter.GaussianBlur(14))
    return fg, bg


def small(master: Image.Image) -> Image.Image:
    s = master.size[0]
    # Her face, the violet eye and the flower in her hair (upper left third).
    box = (int(s * 0.10), int(s * 0.07), int(s * 0.62), int(s * 0.59))
    return master.crop(box).resize((96, 96), Image.LANCZOS)


def splash(master: Image.Image) -> Image.Image:
    w, h = 1920, 1080
    out = Image.new("RGB", (w, h), DUSK)
    # A soft violet glow behind the art.
    glow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(glow).ellipse((w / 2 - 620, h / 2 - 520, w / 2 + 620, h / 2 + 520), fill=120)
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    out = Image.composite(Image.new("RGB", (w, h), (70, 40, 120)), out, glow)
    art = master.resize((760, 760), Image.LANCZOS)
    mask = Image.new("L", (760, 760), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 759, 759), radius=64, fill=255)
    out.paste(art, ((w - 760) // 2, (h - 760) // 2), mask)
    return out


def logo() -> Image.Image:
    """The title, in the game's Cinzel: pale silver letters with a hairline
    gold edge, a four-point star over the gap, a gold rule beneath (the
    same language as the old logo, so the UI around it still fits)."""
    w, h = 1143, 174
    font = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "Cinzel.ttf"), 92)
    text = "ETHEREAL  TALES"
    spacing = 14
    widths = [font.getlength(c) for c in text]
    total = sum(widths) + spacing * (len(text) - 1)
    scale = 1.0
    if total > w - 20:
        scale = (w - 20) / total
        font = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "Cinzel.ttf"), int(92 * scale))
        widths = [font.getlength(c) for c in text]
        spacing = int(spacing * scale)
        total = sum(widths) + spacing * (len(text) - 1)
    big = 2  # draw at twice the size, then reduce: clean edges
    W, H = w * big, h * big
    fb = ImageFont.truetype(font.path, font.size * big)
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    x = (W - total * big) / 2
    y = 26 * big
    for i, c in enumerate(text):
        d.text((x, y), c, font=fb, fill=255)
        x += widths[i] * big + spacing * big
    # Silver fill: white at the top to soft lavender at the foot.
    grad = Image.new("RGBA", (W, H))
    gd = ImageDraw.Draw(grad)
    box = mask.getbbox()
    top, bottom = box[1], box[3]
    for yy in range(H):
        t = min(max((yy - top) / max(bottom - top, 1), 0.0), 1.0)
        gd.line([(0, yy), (W, yy)], fill=(int(250 - 18 * t), int(246 - 26 * t), int(255 - 4 * t), 255))
    edge = mask.filter(ImageFilter.MaxFilter(3))
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glow = Image.new("RGBA", (W, H), (150, 100, 230, 0))
    glow.putalpha(mask.filter(ImageFilter.GaussianBlur(10 * big)).point(lambda v: int(v * 0.35)))
    out = Image.alpha_composite(out, glow)
    gold = Image.new("RGBA", (W, H), (222, 196, 132, 255))
    gold.putalpha(edge)
    out = Image.alpha_composite(out, gold)
    fill = grad.copy()
    fill.putalpha(mask)
    out = Image.alpha_composite(out, fill)
    od = ImageDraw.Draw(out)
    # The star over the gap between the words.
    cx = W / 2
    sy = 14 * big
    r = 13 * big
    od.polygon([(cx, sy - r), (cx + r * 0.22, sy - r * 0.22), (cx + r, sy), (cx + r * 0.22, sy + r * 0.22),
                (cx, sy + r), (cx - r * 0.22, sy + r * 0.22), (cx - r, sy), (cx - r * 0.22, sy - r * 0.22)],
               fill=(240, 226, 186, 255))
    # The gold rule with its small drop at the centre.
    ry = bottom + 22 * big
    od.line([(W * 0.23, ry), (W * 0.77, ry)], fill=(214, 188, 124, 200), width=2 * big)
    od.polygon([(cx - 9 * big, ry), (cx, ry + 9 * big), (cx + 9 * big, ry)], fill=(214, 188, 124, 220))
    return out.resize((w, h), Image.LANCZOS)


def main() -> None:
    os.makedirs(BRAND, exist_ok=True)
    ref = os.path.join(BRAND, "icon_reference.png")
    if len(sys.argv) > 1:
        Image.open(sys.argv[1]).save(ref)
    master = full_bleed(Image.open(ref))
    master.save(os.path.join(BRAND, "icon_master.png"))
    master.resize((192, 192), Image.LANCZOS).save(os.path.join(BRAND, "launcher_192.png"))
    fg, bg = adaptive(master)
    fg.save(os.path.join(BRAND, "adaptive_fg_432.png"))
    bg.save(os.path.join(BRAND, "adaptive_bg_432.png"))
    small(master).save(os.path.join(BRAND, "icon_small_96.png"))
    splash(master).save(os.path.join(BRAND, "splash.png"))
    # Write fresh files (never in place: other checkouts may hard-link them).
    for path, img in [(os.path.join(ROOT, "icon.png"), master.resize((256, 256), Image.LANCZOS)),
                      (os.path.join(ROOT, "assets", "ui", "front", "logo.png"), logo())]:
        if os.path.exists(path):
            os.remove(path)
        img.save(path)
    print("brand assets written")


if __name__ == "__main__":
    main()
