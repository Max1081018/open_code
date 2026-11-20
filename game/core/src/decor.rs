//! Scenery: trees, rocks, plants and crystals that fill out the world.
//!
//! Placement is deterministic from the world seed, so decoration never needs
//! storing in a save file and never shifts between sessions.

use crate::art::Texture;
use crate::biome::Biome;
use crate::paint::{draw_part, ramp_from, shade, Canvas};
use crate::world::World;

/// A piece of scenery.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash, PartialOrd, Ord)]
pub enum Prop {
    /// Broadleaf tree, for plains.
    Tree,
    /// Conifer, for tundra.
    Pine,
    /// Desert succulent.
    Cactus,
    /// Low shrub.
    Bush,
    /// Surface boulder.
    Rock,
    /// Cave fungus, faintly luminous.
    Mushroom,
    /// Cave crystal, brightly coloured.
    Crystal,
}

/// Every prop, for exhaustive tests and texture pre-generation.
pub const ALL_PROPS: [Prop; 7] = [
    Prop::Tree,
    Prop::Pine,
    Prop::Cactus,
    Prop::Bush,
    Prop::Rock,
    Prop::Mushroom,
    Prop::Crystal,
];

/// Distinct generated versions of each prop, chosen by position.
pub const PROP_VARIANTS: u32 = 3;

/// Columns either side that a prop keeps clear of other props.
pub const PROP_SPACING: usize = 3;

/// Footprint of a prop, in tiles.
pub fn prop_size_tiles(prop: Prop) -> (f32, f32) {
    match prop {
        Prop::Tree => (3.0, 4.0),
        Prop::Pine => (2.6, 4.6),
        Prop::Cactus => (1.5, 2.8),
        Prop::Bush => (1.7, 1.2),
        Prop::Rock => (1.5, 1.0),
        Prop::Mushroom => (1.2, 1.4),
        Prop::Crystal => (1.1, 1.6),
    }
}

/// Whether a prop gives off its own light, and how strongly.
pub fn prop_glow(prop: Prop) -> f32 {
    match prop {
        Prop::Crystal => 0.55,
        Prop::Mushroom => 0.25,
        _ => 0.0,
    }
}

/// Keeps prop placement independent of terrain and ore noise.
const DECOR_SALT: u64 = 0xD3C0_1234_D3C0_5678;
const CAVE_DECOR_SALT: u64 = 0xCA7E_9876_CA7E_5432;

/// Fraction of columns that carry scenery, before spacing thins it further.
fn density(biome: Biome) -> f32 {
    match biome {
        Biome::Plains => 0.34,
        Biome::Tundra => 0.26,
        Biome::Desert => 0.18,
    }
}

/// Each column's claim to a prop. The highest claim in a neighbourhood wins,
/// which spaces scenery out without needing to remember what came before.
fn claim(seed: u64, salt: u64, x: usize) -> f32 {
    crate::noise::hash01(seed ^ salt, x as i64)
}

/// Whether `x` outranks every column within [`PROP_SPACING`] of it.
fn wins_locally(seed: u64, salt: u64, x: usize, threshold: f32) -> bool {
    let mine = claim(seed, salt, x);
    if mine < threshold {
        return false;
    }

    (1..=PROP_SPACING).all(|offset| {
        let left = x
            .checked_sub(offset)
            .map(|other| claim(seed, salt, other) < mine)
            .unwrap_or(true);

        left && claim(seed, salt, x + offset) < mine
    })
}

/// Which prop, if any, stands on the surface of column `x`.
pub fn surface_prop(seed: u64, x: usize, biome: Biome) -> Option<Prop> {
    if !wins_locally(seed, DECOR_SALT, x, 1.0 - density(biome)) {
        return None;
    }

    let roll = crate::noise::hash01(seed ^ DECOR_SALT.rotate_left(17), x as i64);

    Some(match biome {
        Biome::Plains => {
            if roll < 0.45 {
                Prop::Tree
            } else if roll < 0.82 {
                Prop::Bush
            } else {
                Prop::Rock
            }
        }
        Biome::Tundra => {
            if roll < 0.62 {
                Prop::Pine
            } else if roll < 0.82 {
                Prop::Bush
            } else {
                Prop::Rock
            }
        }
        Biome::Desert => {
            if roll < 0.52 {
                Prop::Cactus
            } else {
                Prop::Rock
            }
        }
    })
}

/// Which prop, if any, grows on a cave floor at `(x, y)`.
pub fn cave_prop(world: &World, seed: u64, x: usize, y: usize) -> Option<Prop> {
    // Needs open space to stand in and something solid to stand on.
    if world.tile(x, y).is_solid() || !world.tile(x, y + 1).is_solid() {
        return None;
    }

    // Must actually be underground. The open surface is also air over solid,
    // so without this check fungus and crystals sprout in broad daylight.
    match world.surface_y(x) {
        Some(surface) if y > surface => {}
        _ => return None,
    }

    if !wins_locally(seed, CAVE_DECOR_SALT ^ (y as u64), x, 0.62) {
        return None;
    }

    let roll = crate::noise::hash01(seed ^ CAVE_DECOR_SALT.rotate_left(23), (x + y) as i64);

    Some(if roll < 0.62 {
        Prop::Mushroom
    } else {
        Prop::Crystal
    })
}

/// Source pixels per tile, matching the terrain tile size.
const PX_PER_TILE: f32 = 48.0;

/// Colours for one prop variant.
struct PropPalette {
    primary: [f32; 3],
    secondary: [f32; 3],
}

fn palette(prop: Prop, variant: u32) -> PropPalette {
    // Variants shift hue slightly so a stand of trees is not uniform.
    let drift = variant as f32 * 9.0;

    match prop {
        Prop::Tree => PropPalette {
            primary: [62.0 + drift, 108.0 + drift * 1.4, 48.0],
            secondary: [92.0, 64.0, 42.0],
        },
        Prop::Pine => PropPalette {
            primary: [40.0 + drift, 86.0 + drift, 62.0 + drift],
            secondary: [74.0, 54.0, 40.0],
        },
        Prop::Cactus => PropPalette {
            primary: [74.0 + drift, 128.0 + drift, 72.0],
            secondary: [96.0, 150.0, 90.0],
        },
        Prop::Bush => PropPalette {
            primary: [70.0 + drift, 120.0 + drift, 56.0],
            secondary: [54.0, 94.0, 46.0],
        },
        Prop::Rock => PropPalette {
            primary: [112.0 + drift, 112.0 + drift, 122.0 + drift],
            secondary: [86.0, 86.0, 98.0],
        },
        Prop::Mushroom => PropPalette {
            primary: [196.0, 92.0 + drift, 104.0],
            secondary: [226.0, 214.0, 196.0],
        },
        Prop::Crystal => PropPalette {
            primary: [118.0 + drift, 196.0, 228.0],
            secondary: [70.0, 140.0, 196.0],
        },
    }
}

/// Draw a prop.
pub fn prop_texture(prop: Prop, variant: u32) -> Texture {
    let (tiles_w, tiles_h) = prop_size_tiles(prop);
    let width = (tiles_w * PX_PER_TILE) as u32;
    let height = (tiles_h * PX_PER_TILE) as u32;

    let mut canvas = Canvas::new(width, height);
    let colours = palette(prop, variant);
    let seed = 0x9E37 ^ ((prop as u64) << 8) ^ variant as u64;

    let w = width as i32;
    let h = height as i32;

    match prop {
        Prop::Tree => {
            // Trunk rising from the ground, then a layered canopy.
            let trunk_w = w / 6;
            draw_part(
                &mut canvas,
                w / 2 - trunk_w / 2,
                h / 2,
                trunk_w,
                h / 2,
                3.0,
                colours.secondary,
                seed,
            );

            for (index, (cx, cy, size)) in [
                (w / 2, h / 4, w * 5 / 8),
                (w / 4, h * 2 / 5, w / 2),
                (w * 3 / 4, h * 2 / 5, w / 2),
            ]
            .into_iter()
            .enumerate()
            {
                draw_part(
                    &mut canvas,
                    cx - size / 2,
                    cy - size / 2,
                    size,
                    size,
                    size as f32 / 2.0,
                    colours.primary,
                    seed ^ (index as u64 + 1) * 0x51,
                );
            }
        }

        Prop::Pine => {
            let trunk_w = w / 7;
            draw_part(
                &mut canvas,
                w / 2 - trunk_w / 2,
                h * 3 / 4,
                trunk_w,
                h / 4,
                2.0,
                colours.secondary,
                seed,
            );

            // Three stacked tiers, widening toward the base.
            for tier in 0..3 {
                let tier_w = w * (tier + 2) / 5;
                let tier_h = h / 3;
                let top = tier * tier_h + h / 12;

                draw_triangle(
                    &mut canvas,
                    w / 2,
                    top,
                    tier_w,
                    tier_h + h / 10,
                    colours.primary,
                    seed ^ (tier as u64 + 1) * 0x77,
                );
            }
        }

        Prop::Cactus => {
            let stem_w = w / 3;
            draw_part(
                &mut canvas,
                w / 2 - stem_w / 2,
                0,
                stem_w,
                h,
                stem_w as f32 / 2.0,
                colours.primary,
                seed,
            );

            // One arm each side, at different heights.
            let arm_w = w / 4;
            draw_part(&mut canvas, 0, h / 3, arm_w, h / 3, arm_w as f32 / 2.0, colours.primary, seed ^ 0x31);
            draw_part(
                &mut canvas,
                w - arm_w,
                h / 2,
                arm_w,
                h / 3,
                arm_w as f32 / 2.0,
                colours.primary,
                seed ^ 0x32,
            );
        }

        Prop::Bush => {
            for (index, (cx, size)) in
                [(w / 4, h * 3 / 4), (w / 2, h), (w * 3 / 4, h * 2 / 3)]
                    .into_iter()
                    .enumerate()
            {
                draw_part(
                    &mut canvas,
                    cx - size / 2,
                    h - size,
                    size,
                    size,
                    size as f32 / 2.0,
                    if index == 1 {
                        colours.primary
                    } else {
                        colours.secondary
                    },
                    seed ^ (index as u64 + 1) * 0x19,
                );
            }
        }

        Prop::Rock => {
            draw_part(
                &mut canvas,
                w / 8,
                h / 4,
                w * 3 / 4,
                h * 3 / 4,
                h as f32 / 3.0,
                colours.primary,
                seed,
            );
            draw_part(
                &mut canvas,
                w / 2,
                h / 2,
                w * 2 / 5,
                h / 2,
                h as f32 / 4.0,
                colours.secondary,
                seed ^ 0x41,
            );
        }

        Prop::Mushroom => {
            let stalk_w = w / 4;
            // `h - h / 2` rather than `h / 2`, so the stalk still reaches the
            // bottom row when the canvas height is odd.
            draw_part(
                &mut canvas,
                w / 2 - stalk_w / 2,
                h / 2,
                stalk_w,
                h - h / 2,
                2.0,
                colours.secondary,
                seed,
            );
            draw_part(
                &mut canvas,
                w / 8,
                h / 6,
                w * 3 / 4,
                h / 2,
                w as f32 / 3.0,
                colours.primary,
                seed ^ 0x61,
            );
        }

        Prop::Crystal => {
            // A cluster of angular shards of differing heights.
            for (index, (cx, cw, top)) in [
                (w / 2, w / 2, 0),
                (w / 5, w / 3, h / 3),
                (w * 4 / 5, w / 4, h / 2),
            ]
            .into_iter()
            .enumerate()
            {
                draw_triangle(
                    &mut canvas,
                    cx,
                    top,
                    cw,
                    h - top,
                    if index == 0 {
                        colours.primary
                    } else {
                        colours.secondary
                    },
                    seed ^ (index as u64 + 1) * 0x29,
                );
            }
        }
    }

    canvas.into_texture()
}

/// Draw an upright triangle with its apex at `(apex_x, top)`.
fn draw_triangle(
    canvas: &mut Canvas,
    apex_x: i32,
    top: i32,
    base_w: i32,
    height: i32,
    base: [f32; 3],
    seed: u64,
) {
    if height <= 0 || base_w <= 0 {
        return;
    }

    let ramp = ramp_from(base);

    for row in 0..height {
        let along = row as f32 / (height - 1).max(1) as f32;
        let half = ((base_w as f32 * along) / 2.0).round() as i32;

        for dx in -half..=half {
            let across = if half == 0 {
                0.0
            } else {
                dx as f32 / half as f32
            };

            // Light from upper left, and darker toward the silhouette.
            let mut tone = (-across * 0.45 + (1.0 - along) * 0.35) * 1.3;
            tone -= (across.abs().powi(3)) * 0.8;
            tone += (crate::noise::hash01(seed, (row * base_w + dx) as i64) - 0.5) * 0.22;

            canvas.put(apex_x + dx, top + row, shade(&ramp, tone));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::Tile;

    const SEED: u64 = 7;

    fn props_along(biome: Biome, count: usize) -> Vec<Option<Prop>> {
        (0..count).map(|x| surface_prop(SEED, x, biome)).collect()
    }

    #[test]
    fn placement_is_deterministic() {
        for x in 0..300 {
            assert_eq!(
                surface_prop(SEED, x, Biome::Plains),
                surface_prop(SEED, x, Biome::Plains),
                "column {x} changed"
            );
        }
    }

    #[test]
    fn scenery_is_scattered_rather_than_covering_the_ground() {
        let props = props_along(Biome::Plains, 600);
        let filled = props.iter().filter(|p| p.is_some()).count();
        let fraction = filled as f32 / props.len() as f32;

        assert!(
            fraction > 0.04,
            "the world should not be bare; only {:.1}% of columns have scenery",
            fraction * 100.0
        );
        assert!(
            fraction < 0.30,
            "scenery should not carpet the ground; {:.1}% of columns have it",
            fraction * 100.0
        );
    }

    #[test]
    fn props_keep_their_distance_from_one_another() {
        let props = props_along(Biome::Plains, 800);

        let occupied: Vec<usize> = props
            .iter()
            .enumerate()
            .filter(|(_, p)| p.is_some())
            .map(|(x, _)| x)
            .collect();

        for pair in occupied.windows(2) {
            assert!(
                pair[1] - pair[0] > PROP_SPACING,
                "props at {} and {} are too close to each other",
                pair[0],
                pair[1]
            );
        }
    }

    #[test]
    fn each_biome_grows_only_what_belongs_there() {
        for (biome, forbidden) in [
            (Biome::Desert, vec![Prop::Pine, Prop::Tree]),
            (Biome::Tundra, vec![Prop::Cactus]),
            (Biome::Plains, vec![Prop::Cactus, Prop::Pine]),
        ] {
            for prop in props_along(biome, 800).into_iter().flatten() {
                assert!(
                    !forbidden.contains(&prop),
                    "{prop:?} should not grow in {}",
                    biome.name()
                );
            }
        }
    }

    #[test]
    fn every_biome_grows_something() {
        for biome in [Biome::Plains, Biome::Desert, Biome::Tundra] {
            let kinds: std::collections::BTreeSet<Prop> =
                props_along(biome, 800).into_iter().flatten().collect();

            assert!(
                !kinds.is_empty(),
                "{} has no scenery at all",
                biome.name()
            );
        }
    }

    #[test]
    fn deserts_grow_cacti_and_tundra_grows_pines() {
        let desert: std::collections::BTreeSet<Prop> =
            props_along(Biome::Desert, 800).into_iter().flatten().collect();
        let tundra: std::collections::BTreeSet<Prop> =
            props_along(Biome::Tundra, 800).into_iter().flatten().collect();

        assert!(desert.contains(&Prop::Cactus), "no cacti in the desert");
        assert!(tundra.contains(&Prop::Pine), "no pines in the tundra");
    }

    #[test]
    fn caves_grow_fungus_and_crystals_on_their_floors() {
        // A genuine cave: a tunnel enclosed in solid rock, not the surface.
        let (width, height) = (400, 40);
        let mut tiles = vec![Tile::Stone; width * height];
        for x in 0..width {
            tiles[30 * width + x] = Tile::Air;
            tiles[31 * width + x] = Tile::Air;
        }
        let world = World::from_tiles(width, height, tiles);

        let found: std::collections::BTreeSet<Prop> = (0..width)
            .filter_map(|x| cave_prop(&world, SEED, x, 31))
            .collect();

        assert!(
            !found.is_empty(),
            "a long cave floor should grow something"
        );
        for prop in &found {
            assert!(
                matches!(prop, Prop::Mushroom | Prop::Crystal),
                "{prop:?} does not belong underground"
            );
        }
    }

    #[test]
    fn cave_scenery_never_sprouts_on_the_open_surface() {
        // The surface is also air sitting on solid ground, so it has to be
        // excluded explicitly or fungus grows in broad daylight.
        let (width, height) = (400, 40);
        let mut tiles = vec![Tile::Air; width * height];
        for x in 0..width {
            for y in 20..height {
                tiles[y * width + x] = Tile::Stone;
            }
        }
        let world = World::from_tiles(width, height, tiles);

        for x in 0..width {
            assert_eq!(
                cave_prop(&world, SEED, x, 19),
                None,
                "cave scenery appeared on the surface at column {x}"
            );
        }
    }

    #[test]
    fn nothing_grows_where_there_is_no_floor() {
        let world = World::from_tiles(100, 40, vec![Tile::Air; 100 * 40]);

        for x in 0..100 {
            assert_eq!(
                cave_prop(&world, SEED, x, 20),
                None,
                "scenery should not hang in mid-air at {x}"
            );
        }
    }

    #[test]
    fn nothing_grows_inside_solid_rock() {
        let world = World::from_tiles(100, 40, vec![Tile::Stone; 100 * 40]);

        for x in 0..100 {
            assert_eq!(cave_prop(&world, SEED, x, 20), None);
        }
    }

    #[test]
    fn crystals_glow_and_boulders_do_not() {
        assert!(prop_glow(Prop::Crystal) > 0.0);
        assert!(prop_glow(Prop::Mushroom) > 0.0);
        assert_eq!(prop_glow(Prop::Rock), 0.0);
        assert_eq!(prop_glow(Prop::Tree), 0.0);
    }

    #[test]
    fn trees_stand_taller_than_bushes() {
        assert!(prop_size_tiles(Prop::Tree).1 > prop_size_tiles(Prop::Bush).1);
        assert!(prop_size_tiles(Prop::Pine).1 > prop_size_tiles(Prop::Cactus).1);
    }

    #[test]
    fn every_prop_draws_at_its_declared_size() {
        for prop in ALL_PROPS {
            let (w, h) = prop_size_tiles(prop);
            let texture = prop_texture(prop, 0);

            let expected_w = (w * 48.0) as u32;
            let expected_h = (h * 48.0) as u32;

            assert_eq!(texture.width, expected_w, "{prop:?} width");
            assert_eq!(texture.height, expected_h, "{prop:?} height");
        }
    }

    #[test]
    fn every_prop_actually_draws_something() {
        for prop in ALL_PROPS {
            let texture = prop_texture(prop, 0);
            let drawn = texture
                .pixels
                .chunks_exact(4)
                .filter(|pixel| pixel[3] > 0)
                .count();

            assert!(drawn > 100, "{prop:?} drew almost nothing");
        }
    }

    #[test]
    fn props_stand_on_the_bottom_of_their_canvas() {
        // Otherwise they float above the ground they are placed on.
        for prop in ALL_PROPS {
            let texture = prop_texture(prop, 0);
            let footed = (0..texture.width)
                .filter(|&x| texture.pixel(x, texture.height - 1)[3] > 0)
                .count();

            assert!(footed > 0, "{prop:?} does not touch the ground");
        }
    }

    #[test]
    fn prop_variants_differ_from_one_another() {
        for prop in ALL_PROPS {
            let a = prop_texture(prop, 0);
            let b = prop_texture(prop, 1);

            let differing = a
                .pixels
                .chunks_exact(4)
                .zip(b.pixels.chunks_exact(4))
                .filter(|(x, y)| x != y)
                .count();

            assert!(differing > 20, "{prop:?} variants look identical");
        }
    }

    #[test]
    fn no_prop_pixel_is_pure_black_or_pure_white() {
        for prop in ALL_PROPS {
            for pixel in prop_texture(prop, 0).pixels.chunks_exact(4) {
                if pixel[3] == 0 {
                    continue;
                }
                assert!(
                    !(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0),
                    "{prop:?} has a pure black pixel"
                );
                assert!(
                    !(pixel[0] == 255 && pixel[1] == 255 && pixel[2] == 255),
                    "{prop:?} has a pure white pixel"
                );
            }
        }
    }

    #[test]
    fn prop_drawing_is_deterministic() {
        assert_eq!(prop_texture(Prop::Tree, 1), prop_texture(Prop::Tree, 1));
    }
}
