#!/usr/bin/env python3
"""Assemble the game's art from the curated Kenney CC0 library.

Run from the godot/ directory:

    python3 tools/build_assets.py /path/to/kenney

Everything under assets/ that this produces is reproducible from the
Kenney mirror (https://github.com/shorepine/kenney), so the derived files
can always be regenerated rather than hand-edited.

What it does beyond copying:

* builds the terrain atlas: 8 materials x 16 neighbour masks of 128 px
  tiles, so the world can choose the correct edge piece for every cell;
* derives a SOIL material (grass soil with the grass cap replaced by an
  outlined soil edge) and a BASALT material (rock re-tinted for the deep
  layer), so underground tunnels never sprout grass and depth has its
  own colour;
* builds the ore/crack overlay atlas, embedding the very ore lumps the
  player picks up into transparent tiles;
* copies characters, enemies, items, scenery, UI, effects and fonts into
  one predictable layout.
"""

import colorsys
import os
import shutil
import sys

from PIL import Image, ImageDraw, ImageFilter

TILE = 128

# Neighbour mask: bit set means that side is OPEN (air).
UP, DOWN, LEFT, RIGHT = 1, 2, 4, 8

# Which New Platformer Pack piece to use for each of the 16 masks.
MASK_PIECES = {
    0: "block_center",
    UP: "block_top",
    DOWN: "block_bottom",
    LEFT: "block_left",
    RIGHT: "block_right",
    UP | LEFT: "block_top_left",
    UP | RIGHT: "block_top_right",
    DOWN | LEFT: "block_bottom_left",
    DOWN | RIGHT: "block_bottom_right",
    UP | DOWN: "horizontal_middle",
    UP | DOWN | LEFT: "horizontal_left",
    UP | DOWN | RIGHT: "horizontal_right",
    LEFT | RIGHT: "vertical_middle",
    LEFT | RIGHT | UP: "vertical_top",
    LEFT | RIGHT | DOWN: "vertical_bottom",
    UP | DOWN | LEFT | RIGHT: "block",
}

# Atlas rows, in order. Must match World.MATERIAL_ROW in GDScript.
MATERIALS = ["grass", "soil", "sand", "snow", "rock", "brick", "crystal", "basalt", "planks"]

# Kenney source name for each material that exists directly in the pack.
SOURCE = {
    "grass": "grass",
    "sand": "sand",
    "snow": "snow",
    "rock": "dirt",  # Kenney's "dirt" is the grey wavy stratum
    "brick": "stone",  # Kenney's "stone" is masonry: our ruins
    "crystal": "purple",
}

# Ore overlay columns. Must match World.ORE_COLUMN in GDScript.
ORES = [
    ("coal", "ore_coal"),
    ("copper", "ore_iron"),  # Kenney's teal "iron" reads as patinated copper
    ("iron", "ore_ironAlt"),
    ("silver", "ore_silver"),
    ("gold", "ore_gold"),
    ("glowshard", "ore_diamond"),
    ("ruby", "ore_ruby"),
    ("emerald", "ore_emerald"),
]
CRACK_STAGES = 3


def out(*parts):
    path = os.path.join("assets", *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def tile(kenney, name):
    return Image.open(
        os.path.join(kenney, "2d/New Platformer Pack/Sprites/Tiles/Double", name + ".png")
    ).convert("RGBA")


def recapped(image, fill_rgb, hue_low, hue_high):
    """Replace a coloured cap (grass, dirt crust) with `fill_rgb`.

    Kenney's top pieces wear a cap of another material: grass on soil, an
    orange dirt crust on the grey stratum. Underground, a cap like that
    reads as the wrong material growing on every cave floor, so it is
    recoloured to the body material while the outline is kept.
    """
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if hue_low < h < hue_high and s > 0.30 and v > 0.25:
                # Shade the substitute like the grass it replaces, so the
                # cap's highlight becomes a lit soil lip rather than a slab.
                shade = 0.82 + 0.30 * v
                pixels[x, y] = tuple(min(255, int(c * shade)) for c in fill_rgb) + (a,)
    return image


def grassless(image, soil_rgb):
    return recapped(image, soil_rgb, 0.20, 0.48)


def crustless(image, rock_rgb):
    return recapped(image, rock_rgb, 0.0, 0.13)


def tinted(image, multiply):
    """Multiply every pixel by an RGB factor, preserving outlines' darkness."""
    r, g, b, a = image.split()
    r = r.point(lambda v: min(255, int(v * multiply[0])))
    g = g.point(lambda v: min(255, int(v * multiply[1])))
    b = b.point(lambda v: min(255, int(v * multiply[2])))
    return Image.merge("RGBA", (r, g, b, a))


def build_terrain(kenney):
    atlas = Image.new("RGBA", (TILE * 16, TILE * len(MATERIALS)), (0, 0, 0, 0))

    soil_rgb = tile(kenney, "terrain_grass_block_center").getpixel((64, 64))[:3]
    rock_rgb = tile(kenney, "terrain_dirt_block_center").getpixel((64, 64))[:3]

    for row, material in enumerate(MATERIALS):
        for mask in range(16):
            piece = MASK_PIECES[mask]
            if material == "soil":
                image = grassless(tile(kenney, f"terrain_grass_{piece}"), soil_rgb)
            elif material == "rock":
                image = crustless(tile(kenney, f"terrain_dirt_{piece}"), rock_rgb)
            elif material == "planks":
                # A crate-like block with its own outline on every side:
                # placed wood reads as built, not grown, which is right.
                image = tile(kenney, "block_planks")
            elif material == "basalt":
                image = tinted(
                    crustless(tile(kenney, f"terrain_dirt_{piece}"), rock_rgb),
                    (0.62, 0.52, 0.60),
                )
            else:
                image = tile(kenney, f"terrain_{SOURCE[material]}_{piece}")
            atlas.paste(image, (mask * TILE, row * TILE))

    atlas.save(out("tiles", "terrain.png"))
    print(f"terrain atlas: {len(MATERIALS)} materials x 16 masks")

    # Inventory icons for blocks: the fully outlined lone-block piece is
    # exactly what a carried block should look like.
    lone = UP | DOWN | LEFT | RIGHT
    for row, material in enumerate(MATERIALS):
        atlas.crop((lone * TILE, row * TILE, (lone + 1) * TILE, (row + 1) * TILE)).save(
            out("blocks", material + ".png")
        )


def build_overlay(kenney):
    """Ores embedded as lumps, plus three crack stages for mining."""
    columns = len(ORES) + CRACK_STAGES
    atlas = Image.new("RGBA", (TILE * columns, TILE * 2), (0, 0, 0, 0))

    # Two placement patterns per ore, chosen per cell in game, so a seam
    # of ore does not stamp the same three lumps on every tile.
    patterns = [
        [(10, 12, 64), (62, 50, 58), (22, 80, 38)],
        [(56, 6, 58), (6, 52, 62), (70, 78, 40)],
    ]

    for column, (_, icon) in enumerate(ORES):
        source = Image.open(
            os.path.join(kenney, "2d/Voxel Pack/Items", icon + ".png")
        ).convert("RGBA")
        for row, pattern in enumerate(patterns):
            for index, (x, y, size) in enumerate(pattern):
                lump = source.resize((size, size), Image.LANCZOS)
                if index % 2:
                    lump = lump.transpose(Image.FLIP_LEFT_RIGHT)
                # A soft contact shadow seats the lump in the rock.
                shadow = Image.new("RGBA", lump.size, (20, 18, 30, 0))
                shadow.putalpha(lump.getchannel("A").point(lambda a: int(a * 0.45)))
                shadow = shadow.filter(ImageFilter.GaussianBlur(3))
                cell = (column * TILE, row * TILE)
                atlas.alpha_composite(shadow, (cell[0] + x + 3, cell[1] + y + 4))
                atlas.alpha_composite(lump, (cell[0] + x, cell[1] + y))

    # Cracks: branching dark lines that grow with each stage.
    strokes = [
        [((64, 64), (40, 30)), ((64, 64), (92, 42)), ((64, 64), (58, 100))],
        [((40, 30), (22, 16)), ((92, 42), (112, 30)), ((58, 100), (80, 116)),
         ((64, 64), (24, 74))],
        [((22, 16), (8, 30)), ((112, 30), (118, 60)), ((80, 116), (104, 104)),
         ((24, 74), (10, 96)), ((64, 64), (102, 84))],
    ]
    for stage in range(CRACK_STAGES):
        layer = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        for upto in range(stage + 1):
            for start, end in strokes[upto]:
                draw.line([start, end], fill=(28, 22, 36, 210), width=6 - upto)
                draw.line([start, end], fill=(255, 255, 255, 40), width=1)
        column = len(ORES) + stage
        for row in range(2):
            atlas.alpha_composite(layer, (column * TILE, row * TILE))

    atlas.save(out("tiles", "overlay.png"))
    print(f"overlay atlas: {len(ORES)} ores + {CRACK_STAGES} crack stages")


def build_liquids(kenney):
    """Water and lava, body and surface, in one strip: [water, water_top, lava, lava_top]."""
    atlas = Image.new("RGBA", (TILE * 4, TILE), (0, 0, 0, 0))
    for column, name in enumerate(["water", "water_top", "lava", "lava_top"]):
        atlas.paste(tile(kenney, name), (column * TILE, 0))
    atlas.save(out("tiles", "liquid.png"))
    print("liquid atlas: water, lava")


def _key_out_sky(image):
    """Make the sky transparent by flooding from the top edge.

    The flood follows the sky's smooth gradient and stops at any sharp
    colour step, which is every hill outline. A threshold on paleness was
    tried first: it also ate the pale far hills whole, and a per-column
    scan left sky trapped under cactus arms as white boxes.
    """
    from collections import deque

    pixels = image.load()
    width, height = image.size
    seen = bytearray(width * height)
    queue = deque()
    for x in range(width):
        queue.append((x, 0))
        seen[x] = 1
    while queue:
        x, y = queue.popleft()
        here = pixels[x, y]
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if not (0 <= nx < width and 0 <= ny < height) or seen[ny * width + nx]:
                continue
            there = pixels[nx, ny]
            if sum(abs(here[c] - there[c]) for c in range(3)) <= 9:
                seen[ny * width + nx] = 1
                queue.append((nx, ny))
    for y in range(height):
        for x in range(width):
            if seen[y * width + x]:
                r, g, b, _ = pixels[x, y]
                pixels[x, y] = (r, g, b, 0)


def build_parallax(kenney):
    """Hills with their baked-in sky made transparent.

    Kenney's backdrops each carry their own opaque sky, so two of them can
    never be layered: the near one hides the far one completely. Keying out
    the sky lets far hills, near hills and a live, time-of-day sky stack.
    """
    source = os.path.join(kenney, "2d/New Platformer Pack/Sprites/Backgrounds/Double")
    for name in ["background_color_hills", "background_color_trees", "background_color_desert",
                 "background_color_mushrooms", "background_fade_hills", "background_fade_trees",
                 "background_fade_desert", "background_fade_mushrooms"]:
        image = Image.open(os.path.join(source, name + ".png")).convert("RGBA")
        _key_out_sky(image)
        image.save(out("scenery", "parallax", name.replace("background_", "") + ".png"))
    print("parallax: 8 keyed backdrops")


def copy_tree(source, destination, names=None, rename=None):
    os.makedirs(destination, exist_ok=True)
    copied = 0
    for name in sorted(os.listdir(source)):
        if not name.endswith(".png"):
            continue
        stem = name[:-4]
        if names is not None and stem not in names:
            continue
        target = rename(stem) if rename else stem
        shutil.copyfile(os.path.join(source, name), os.path.join(destination, target + ".png"))
        copied += 1
    return copied


def build_characters(kenney):
    toon = os.path.join(kenney, "2d/Toon Characters")
    cast = {
        "player": ("Male adventurer", "character_maleAdventurer_"),
        "guide": ("Female adventurer", "character_femaleAdventurer_"),
        "zombie": ("Zombie", "character_zombie_"),
        "robot": ("Robot", "character_robot_"),
    }
    for folder, (source, prefix) in cast.items():
        n = copy_tree(
            os.path.join(toon, source, "Poses HD"),
            os.path.join("assets", "characters", folder),
            rename=lambda stem, p=prefix: stem.replace(p, ""),
        )
        print(f"characters/{folder}: {n} poses")

    n = copy_tree(
        os.path.join(kenney, "2d/New Platformer Pack/Sprites/Enemies/Double"),
        os.path.dirname(out("enemies", "x")),
    )
    print(f"enemies: {n} frames")


def build_items(kenney):
    n = copy_tree(os.path.join(kenney, "2d/Voxel Pack/Items"), os.path.dirname(out("items", "x")))
    expansion = os.path.join(kenney, "2d/Voxel Expansion Pack/Retina")
    n += copy_tree(
        expansion,
        os.path.dirname(out("items", "x")),
        names={name[:-4] for name in os.listdir(expansion) if name.startswith("item_")},
        rename=lambda stem: stem.replace("item_", ""),
    )
    print(f"items: {n} icons")


def build_props(kenney):
    tiles = os.path.join(kenney, "2d/New Platformer Pack/Sprites/Tiles/Double")
    wanted = {
        "torch_on_a", "torch_on_b", "torch_off", "ladder_top", "ladder_middle",
        "ladder_bottom", "door_closed", "door_closed_top", "door_open", "door_open_top",
        "bridge_logs", "bridge", "block_planks", "block_plank", "bricks_brown",
        "bricks_grey", "brick_brown", "brick_grey", "sign", "sign_left", "sign_right",
        "mushroom_red", "mushroom_brown", "rock", "bush", "cactus", "grass",
        "grass_purple", "snow", "gem_blue", "gem_green", "gem_red", "gem_yellow",
        "coin_gold", "coin_silver", "coin_bronze", "heart", "star", "key_yellow",
        "lava", "lava_top", "lava_top_low", "water", "water_top", "water_top_low",
        "fence", "fence_broken", "chain", "window", "spikes", "flag_red_a", "flag_red_b",
        "hud_heart", "hud_heart_half", "hud_heart_empty", "hud_coin",
    }
    n = copy_tree(tiles, os.path.dirname(out("props", "x")), names=wanted)
    print(f"props: {n} sprites")


def build_scenery(kenney):
    retina = os.path.join(kenney, "2d/Background Elements Remastered/Retina")
    n = copy_tree(retina, os.path.dirname(out("scenery", "x")))
    backgrounds = os.path.join(kenney, "2d/New Platformer Pack/Sprites/Backgrounds/Double")
    n += copy_tree(backgrounds, os.path.dirname(out("scenery", "backgrounds", "x")))
    print(f"scenery: {n} images")


def build_ui(kenney):
    adventure = os.path.join(kenney, "ui/UI Pack - Adventure/Double")
    if not os.path.isdir(adventure):
        adventure = os.path.join(kenney, "ui/UI Pack - Adventure")
    n = copy_tree(adventure, os.path.dirname(out("ui", "panels", "x")))

    controls = os.path.join(kenney, "ui/Mobile Controls/Sprites")
    style = os.path.join(controls, "Style A")
    large = [d for d in os.listdir(style) if d.startswith("Large")]
    n += copy_tree(
        os.path.join(style, large[0]) if large else style,
        os.path.dirname(out("ui", "controls", "x")),
    )
    icons = os.path.join(controls, "Icons")
    large = [d for d in os.listdir(icons) if d.startswith("Large")]
    n += copy_tree(
        os.path.join(icons, large[0]) if large else icons,
        os.path.dirname(out("ui", "icons", "x")),
    )
    print(f"ui: {n} images")


def build_fx(kenney):
    particles = os.path.join(kenney, "2d/Particle Pack/PNG (Transparent)")
    wanted = {
        "circle_05", "dirt_01", "dirt_02", "dirt_03", "smoke_01", "smoke_04", "smoke_07",
        "spark_01", "spark_04", "spark_05", "star_01", "star_04", "star_06", "light_01",
        "light_02", "light_03", "slash_01", "slash_02", "slash_03", "slash_04",
        "magic_01", "magic_03", "magic_05", "flame_01", "flame_04", "twirl_01",
        "trace_01", "muzzle_02", "scorch_01",
    }
    n = copy_tree(particles, os.path.dirname(out("fx", "x")), names=wanted)

    masks = os.path.join(kenney, "2d/Light Masks/Transparent")
    n += copy_tree(
        masks,
        os.path.dirname(out("fx", "lights", "x")),
        names={"circle_a", "circle_b", "circle_c", "circle_a_streaks", "circle_b_noise"},
    )
    print(f"fx: {n} sprites")


def build_fonts(fonts):
    for name in ["Fredoka.ttf", "LilitaOne-Regular.ttf", "OFL.txt", "LilitaOne-OFL.txt"]:
        source = os.path.join(fonts, name)
        if os.path.exists(source):
            shutil.copyfile(source, out("fonts", name))
    print("fonts: Fredoka, Lilita One")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    kenney = sys.argv[1]
    fonts = sys.argv[2] if len(sys.argv) > 2 else None

    shutil.copyfile(os.path.join(kenney, "LICENSE.txt"), out("KENNEY-LICENSE.txt"))
    build_terrain(kenney)
    build_overlay(kenney)
    build_liquids(kenney)
    build_parallax(kenney)
    build_characters(kenney)
    build_items(kenney)
    build_props(kenney)
    build_scenery(kenney)
    build_ui(kenney)
    build_fx(kenney)
    if fonts:
        build_fonts(fonts)
    return 0


if __name__ == "__main__":
    sys.exit(main())
