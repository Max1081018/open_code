//! Procedurally generated tile textures.
//!
//! Tiles are 48px rather than Terraria's 16px, which only pays off if the
//! extra room carries real detail. Each texture gets noise mottling, a
//! bevelled edge for depth, and — for ores — mineral flecks embedded in the
//! surrounding rock.

use crate::noise::fbm_2d;
use crate::view::TILE_SOURCE_PX;
use crate::world::Tile;

/// Strength of the lighting bevel at tile edges, as a fraction of brightness.
const BEVEL_STRENGTH: f32 = 0.28;

/// Width of the bevel, in texels.
const BEVEL_WIDTH: f32 = 6.0;

/// How strongly surface noise modulates brightness.
const MOTTLE_STRENGTH: f32 = 0.14;

/// Spatial frequency of the surface mottling.
const MOTTLE_FREQUENCY: f32 = 0.09;

/// Noise above this becomes a mineral fleck in an ore tile.
const FLECK_THRESHOLD: f32 = 0.62;

/// Frequency of the fleck field; high, so flecks are small and scattered.
const FLECK_FREQUENCY: f32 = 0.22;

/// How many distinct textures are baked per material.
///
/// One texture per material makes a wall of stone visibly repeat; a handful
/// of variants scattered by position breaks the pattern for very little
/// memory. Six is enough that the eye stops finding the period.
pub const TEXTURE_VARIANTS: u32 = 6;

/// Which texture variant the tile at `(x, y)` should use.
pub fn variant_for(seed: u64, x: usize, y: usize) -> u32 {
    let h = crate::noise::hash01_2d(seed ^ VARIANT_SALT, x as i64, y as i64);
    ((h * TEXTURE_VARIANTS as f32) as u32).min(TEXTURE_VARIANTS - 1)
}

/// Seed offset that turns a variant index into a distinct noise field.
pub fn variant_seed(seed: u64, variant: u32) -> u64 {
    seed ^ (variant as u64 + 1).wrapping_mul(0x9E37_79B9_7F4A_7C15)
}

const VARIANT_SALT: u64 = 0x7A91_0C3D_55E1_B2A4;

/// Which sides of a tile are open to the air.
///
/// Lighting lives here rather than in the material texture: a tile buried in
/// solid ground must blend seamlessly with its neighbours, while one at the
/// mouth of a cave should catch the light along its exposed edges.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Exposure {
    pub top: bool,
    pub bottom: bool,
    pub left: bool,
    pub right: bool,
}

impl Exposure {
    /// Nothing exposed: the tile is buried.
    pub fn buried() -> Exposure {
        Exposure::default()
    }

    pub fn is_buried(self) -> bool {
        self == Exposure::default()
    }
}

/// Brightness multiplier for texel `(x, y)` of a tile with this `exposure`.
///
/// Light comes from the upper left, so exposed top and left edges brighten
/// while exposed bottom and right edges fall into shadow. Unexposed edges
/// return exactly 1.0, leaving neighbouring tiles seamless.
pub fn edge_shade(exposure: Exposure, x: u32, y: u32, size: u32) -> f32 {
    let far_edge = size as f32 - 1.0;
    let (fx, fy) = (x as f32, y as f32);

    let ramp = |distance: f32| (1.0 - distance / BEVEL_WIDTH).max(0.0);

    let mut delta = 0.0;

    if exposure.top {
        delta += ramp(fy) * BEVEL_STRENGTH;
    }
    if exposure.left {
        delta += ramp(fx) * BEVEL_STRENGTH;
    }
    if exposure.bottom {
        delta -= ramp(far_edge - fy) * BEVEL_STRENGTH;
    }
    if exposure.right {
        delta -= ramp(far_edge - fx) * BEVEL_STRENGTH;
    }

    1.0 + delta
}

/// An RGBA8 image.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Texture {
    pub width: u32,
    pub height: u32,
    /// Row-major RGBA, four bytes per pixel.
    pub pixels: Vec<u8>,
}

impl Texture {
    pub fn pixel(&self, x: u32, y: u32) -> [u8; 4] {
        let i = ((y * self.width + x) * 4) as usize;
        [
            self.pixels[i],
            self.pixels[i + 1],
            self.pixels[i + 2],
            self.pixels[i + 3],
        ]
    }

    /// Mean of the three colour channels across the whole image.
    pub fn average_rgb(&self) -> [f32; 3] {
        let mut totals = [0.0f32; 3];
        let count = (self.width * self.height) as f32;

        for chunk in self.pixels.chunks_exact(4) {
            totals[0] += chunk[0] as f32;
            totals[1] += chunk[1] as f32;
            totals[2] += chunk[2] as f32;
        }

        [
            totals[0] / count,
            totals[1] / count,
            totals[2] / count,
        ]
    }
}

/// Keeps the fleck field independent of the surface mottling.
const FLECK_SALT: u64 = 0xF1EC_1234_F1EC_5678;

/// Fraction of tile height covered by the grass crown.
const CROWN_FRACTION: f32 = 1.0 / 3.0;

/// How far the grass/soil boundary wanders, in texels.
const CROWN_RAGGEDNESS: f32 = 3.0;

/// The colours a material is built from.
struct Palette {
    /// Body colour of the material.
    base: [f32; 3],
    /// Mineral speckle colour, for ores.
    fleck: Option<[f32; 3]>,
    /// Colour of the top band, for grass.
    crown: Option<[f32; 3]>,
}

fn palette_for(tile: Tile) -> Palette {
    const SOIL: [f32; 3] = [134.0, 96.0, 62.0];
    const ROCK: [f32; 3] = [118.0, 118.0, 126.0];

    match tile {
        Tile::Air => Palette {
            base: [0.0; 3],
            fleck: None,
            crown: None,
        },
        Tile::Dirt => Palette {
            base: SOIL,
            fleck: None,
            crown: None,
        },
        Tile::Grass => Palette {
            base: SOIL,
            fleck: None,
            crown: Some([84.0, 152.0, 58.0]),
        },
        Tile::Stone => Palette {
            base: ROCK,
            fleck: None,
            crown: None,
        },
        Tile::CoalOre => Palette {
            base: ROCK,
            fleck: Some([34.0, 34.0, 38.0]),
            crown: None,
        },
        Tile::CopperOre => Palette {
            base: ROCK,
            fleck: Some([198.0, 112.0, 58.0]),
            crown: None,
        },
        Tile::IronOre => Palette {
            base: ROCK,
            fleck: Some([196.0, 180.0, 160.0]),
            crown: None,
        },
        Tile::GoldOre => Palette {
            base: ROCK,
            fleck: Some([230.0, 188.0, 72.0]),
            crown: None,
        },
    }
}

/// Distinct per material, so two materials never share a noise field.
fn material_salt(tile: Tile) -> u64 {
    match tile {
        Tile::Air => 0,
        Tile::Dirt => 0x0001_D127_0001_D127,
        Tile::Grass => 0x0002_6025_0002_6025,
        Tile::Stone => 0x0003_570E_0003_570E,
        Tile::CoalOre => 0x0004_C0A1_0004_C0A1,
        Tile::CopperOre => 0x0005_C0BB_0005_C0BB,
        Tile::IronOre => 0x0006_1204_0006_1204,
        Tile::GoldOre => 0x0007_601D_0007_601D,
    }
}

/// Generate the texture for `tile`, or `None` for empty space.
pub fn tile_texture(tile: Tile, seed: u64) -> Option<Texture> {
    if !tile.is_solid() {
        return None;
    }

    let size = TILE_SOURCE_PX;
    let palette = palette_for(tile);
    let tile_seed = seed ^ material_salt(tile);

    let mut pixels = Vec::with_capacity((size * size * 4) as usize);

    for y in 0..size {
        for x in 0..size {
            let [r, g, b] = shade(&palette, tile_seed, x, y, size);
            pixels.extend_from_slice(&[r, g, b, 255]);
        }
    }

    Some(Texture {
        width: size,
        height: size,
        pixels,
    })
}

/// Colour of one texel: material colour, mottled, flecked, then bevelled.
#[allow(unused_variables)]
fn shade(palette: &Palette, seed: u64, x: u32, y: u32, size: u32) -> [u8; 3] {
    let mut colour = palette.base;

    // Grass sits in a ragged band across the top rather than a ruled line.
    if let Some(crown) = palette.crown {
        let wobble = fbm_2d(seed, x as f32 * 0.14, 0.0, 2) - 0.5;
        let depth = size as f32 * CROWN_FRACTION + wobble * 2.0 * CROWN_RAGGEDNESS;

        if (y as f32) < depth {
            colour = crown;
        }
    }

    // Mineral flecks embedded in the rock.
    if let Some(fleck) = palette.fleck {
        let field = fbm_2d(
            seed ^ FLECK_SALT,
            x as f32 * FLECK_FREQUENCY,
            y as f32 * FLECK_FREQUENCY,
            2,
        );

        if field > FLECK_THRESHOLD {
            colour = fleck;
        }
    }

    let mottle = fbm_2d(
        seed,
        x as f32 * MOTTLE_FREQUENCY,
        y as f32 * MOTTLE_FREQUENCY,
        3,
    ) - 0.5;

    // No bevel here on purpose: edge lighting depends on which sides are
    // open to the air, which is a property of the tile's place in the world,
    // not of the material. See `edge_shade`.
    let brightness = 1.0 + mottle * 2.0 * MOTTLE_STRENGTH;

    [
        (colour[0] * brightness).clamp(0.0, 255.0) as u8,
        (colour[1] * brightness).clamp(0.0, 255.0) as u8,
        (colour[2] * brightness).clamp(0.0, 255.0) as u8,
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn texture_of(tile: Tile) -> Texture {
        tile_texture(tile, 1).unwrap_or_else(|| panic!("{tile:?} should have a texture"))
    }

    fn luminance(rgb: [f32; 3]) -> f32 {
        0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
    }

    fn colour_distance(a: [f32; 3], b: [f32; 3]) -> f32 {
        ((a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2) + (a[2] - b[2]).powi(2)).sqrt()
    }

    /// Mean luminance of `rows`, taken from the top if `from_top`.
    fn band_luminance(texture: &Texture, rows: u32, from_top: bool) -> f32 {
        let mut total = 0.0;
        let mut count = 0.0;

        for row in 0..rows {
            let y = if from_top {
                row
            } else {
                texture.height - 1 - row
            };
            for x in 0..texture.width {
                let p = texture.pixel(x, y);
                total += luminance([p[0] as f32, p[1] as f32, p[2] as f32]);
                count += 1.0;
            }
        }

        total / count
    }

    fn channel_variance(texture: &Texture) -> f32 {
        let mean = texture.average_rgb();
        let mut sum = 0.0;
        let mut count = 0.0;

        for chunk in texture.pixels.chunks_exact(4) {
            for channel in 0..3 {
                let d = chunk[channel] as f32 - mean[channel];
                sum += d * d;
                count += 1.0;
            }
        }

        sum / count
    }

    #[test]
    fn variant_choice_is_deterministic_and_within_range() {
        for x in 0..40 {
            for y in 0..40 {
                let chosen = variant_for(5, x, y);

                assert_eq!(chosen, variant_for(5, x, y), "variant at ({x}, {y}) changed");
                assert!(
                    chosen < TEXTURE_VARIANTS,
                    "variant {chosen} out of range at ({x}, {y})"
                );
            }
        }
    }

    #[test]
    fn every_variant_gets_used_across_a_patch_of_ground() {
        let mut seen = vec![false; TEXTURE_VARIANTS as usize];

        for x in 0..40 {
            for y in 0..40 {
                seen[variant_for(5, x, y) as usize] = true;
            }
        }

        assert!(
            seen.iter().all(|&used| used),
            "all {TEXTURE_VARIANTS} variants should appear; got {seen:?}"
        );
    }

    #[test]
    fn neighbouring_tiles_do_not_all_share_one_variant() {
        let row: Vec<u32> = (0..24).map(|x| variant_for(5, x, 10)).collect();
        let distinct: std::collections::BTreeSet<u32> = row.iter().copied().collect();

        assert!(
            distinct.len() >= 4,
            "a row of ground should mix variants, got {distinct:?}"
        );
    }

    #[test]
    fn variant_seeds_produce_visibly_different_textures() {
        let a = tile_texture(Tile::Stone, variant_seed(1, 0)).expect("stone texture");
        let b = tile_texture(Tile::Stone, variant_seed(1, 1)).expect("stone texture");

        assert_ne!(a, b, "two variants should not be pixel-identical");
    }

    #[test]
    fn empty_space_has_no_texture() {
        assert_eq!(tile_texture(Tile::Air, 1), None);
    }

    #[test]
    fn textures_are_generated_at_the_configured_tile_size() {
        let texture = texture_of(Tile::Stone);

        assert_eq!(texture.width, TILE_SOURCE_PX);
        assert_eq!(texture.height, TILE_SOURCE_PX);
        assert_eq!(
            texture.pixels.len(),
            (TILE_SOURCE_PX * TILE_SOURCE_PX * 4) as usize
        );
    }

    #[test]
    fn solid_tiles_are_fully_opaque() {
        for tile in [Tile::Dirt, Tile::Grass, Tile::Stone, Tile::GoldOre] {
            let texture = texture_of(tile);

            for y in 0..texture.height {
                for x in 0..texture.width {
                    assert_eq!(
                        texture.pixel(x, y)[3],
                        255,
                        "{tile:?} pixel ({x}, {y}) should be opaque"
                    );
                }
            }
        }
    }

    #[test]
    fn generation_is_deterministic_for_a_given_seed() {
        assert_eq!(tile_texture(Tile::Stone, 42), tile_texture(Tile::Stone, 42));
    }

    #[test]
    fn soil_rock_and_grass_are_clearly_different_materials() {
        let dirt = texture_of(Tile::Dirt).average_rgb();
        let grass = texture_of(Tile::Grass).average_rgb();
        let stone = texture_of(Tile::Stone).average_rgb();

        for (name, a, b) in [
            ("dirt/grass", dirt, grass),
            ("dirt/stone", dirt, stone),
            ("grass/stone", grass, stone),
        ] {
            let distance = colour_distance(a, b);
            assert!(
                distance >= 20.0,
                "{name} should be visually distinct; colour distance only {distance:.1}"
            );
        }
    }

    #[test]
    fn every_ore_reads_differently_from_the_rock_around_it() {
        let stone = texture_of(Tile::Stone).average_rgb();

        for ore in [
            Tile::CoalOre,
            Tile::CopperOre,
            Tile::IronOre,
            Tile::GoldOre,
        ] {
            let distance = colour_distance(texture_of(ore).average_rgb(), stone);
            assert!(
                distance >= 3.0,
                "{ore:?} should stand out from plain stone; distance only {distance:.1}"
            );
        }
    }

    #[test]
    fn ore_flecks_make_the_surface_busier_than_plain_rock() {
        let stone = channel_variance(&texture_of(Tile::Stone));
        let gold = channel_variance(&texture_of(Tile::GoldOre));

        assert!(
            gold > stone * 1.5,
            "gold flecks should add visible texture; variance {gold:.1} vs stone {stone:.1}"
        );
    }

    #[test]
    fn a_buried_tile_is_shaded_flat_so_it_blends_with_its_neighbours() {
        let size = TILE_SOURCE_PX;

        for y in 0..size {
            for x in 0..size {
                assert_eq!(
                    edge_shade(Exposure::buried(), x, y, size),
                    1.0,
                    "buried tile should be unshaded at ({x}, {y})"
                );
            }
        }
    }

    #[test]
    fn an_exposed_top_edge_catches_the_light() {
        let size = TILE_SOURCE_PX;
        let exposure = Exposure {
            top: true,
            ..Exposure::default()
        };

        let lit = edge_shade(exposure, size / 2, 0, size);

        assert!(lit > 1.0, "exposed top should brighten, got {lit}");
    }

    #[test]
    fn an_exposed_bottom_edge_falls_into_shadow() {
        let size = TILE_SOURCE_PX;
        let exposure = Exposure {
            bottom: true,
            ..Exposure::default()
        };

        let shaded = edge_shade(exposure, size / 2, size - 1, size);

        assert!(shaded < 1.0, "exposed bottom should darken, got {shaded}");
    }

    #[test]
    fn edge_lighting_fades_to_neutral_toward_the_tile_centre() {
        let size = TILE_SOURCE_PX;
        let exposure = Exposure {
            top: true,
            left: true,
            bottom: true,
            right: true,
        };

        let centre = edge_shade(exposure, size / 2, size / 2, size);

        assert!(
            (centre - 1.0).abs() < 1e-6,
            "tile centre should be unshaded, got {centre}"
        );
    }

    #[test]
    fn an_unexposed_edge_stays_seamless_even_when_another_side_is_open() {
        let size = TILE_SOURCE_PX;
        // Only the bottom is open, so the top edge must stay untouched or the
        // seam against the tile above it will show.
        let exposure = Exposure {
            bottom: true,
            ..Exposure::default()
        };

        let top_edge = edge_shade(exposure, size / 2, 0, size);

        assert_eq!(top_edge, 1.0, "unexposed top must not be shaded");
    }

    #[test]
    fn exposed_tiles_read_as_three_dimensional_once_shaded() {
        let texture = texture_of(Tile::Stone);
        let size = TILE_SOURCE_PX;
        let exposure = Exposure {
            top: true,
            bottom: true,
            left: true,
            right: true,
        };

        let shaded_band = |rows: u32, from_top: bool| {
            let mut total = 0.0;
            let mut count = 0.0;
            for row in 0..rows {
                let y = if from_top { row } else { size - 1 - row };
                for x in 0..size {
                    let p = texture.pixel(x, y);
                    let shade = edge_shade(exposure, x, y, size);
                    total += luminance([p[0] as f32, p[1] as f32, p[2] as f32]) * shade;
                    count += 1.0;
                }
            }
            total / count
        };

        let top = shaded_band(3, true);
        let bottom = shaded_band(3, false);

        assert!(
            top > bottom + 8.0,
            "a fully exposed tile should be lit top and shadowed bottom; \
             top {top:.1} vs bottom {bottom:.1}"
        );
    }

    #[test]
    fn grass_is_green_on_top_and_earthy_underneath() {
        let texture = texture_of(Tile::Grass);

        let top = texture.pixel(texture.width / 2, 1);
        let bottom = texture.pixel(texture.width / 2, texture.height - 2);

        assert!(
            top[1] > top[0],
            "grass crown should be green-dominant, got {top:?}"
        );
        assert!(
            bottom[0] > bottom[1],
            "grass underside should be earth-dominant, got {bottom:?}"
        );
    }
}
