//! The tile world: storage and generation.

use crate::noise::{fbm_1d, fbm_2d};

/// How fast the surface height wanders as you walk sideways. Lower is flatter.
const SURFACE_FREQUENCY: f32 = 0.02;

/// Octaves of noise in the surface heightmap: broad hills plus finer bumps.
const SURFACE_OCTAVES: u32 = 5;

/// Depth of the soil column beneath the grass cap before stone begins.
const SOIL_DEPTH: usize = 5;

/// Cave noise is stretched horizontally so caverns run wider than they are
/// tall, which reads better than round blobs and is nicer to walk through.
const CAVE_FREQUENCY_X: f32 = 0.06;
const CAVE_FREQUENCY_Y: f32 = 0.09;
const CAVE_OCTAVES: u32 = 4;

/// Rock is carved where cave noise lands within this distance of the midpoint.
/// Band-carving yields winding tunnels; thresholding yields blobs.
const CAVE_BAND: f32 = 0.055;

/// Keeps the cave noise field independent of the surface heightmap.
const CAVE_SEED_SALT: u64 = 0x5CA7_7E57_CA7E_5A17;

/// Untouched rows at the very bottom of the world, so caves never breach it.
const BEDROCK_ROWS: usize = 2;

/// Solid rock between the soil and the highest a cave may reach.
const CAVE_CEILING_MARGIN: usize = 2;

/// A single tile of the world grid.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum Tile {
    /// Empty space the player can move through.
    #[default]
    Air,
    Dirt,
    Grass,
    Stone,
}

/// A generated tile world, addressed by `(x, y)` with `y = 0` at the top.
#[derive(Clone, Debug)]
pub struct World {
    width: usize,
    height: usize,
    tiles: Vec<Tile>,
}

impl World {
    /// Generate a world deterministically from `seed`.
    pub fn generate(seed: u64, width: usize, height: usize) -> World {
        let mut tiles = vec![Tile::Air; width * height];

        // Keep the rolling surface clear of both edges: open sky above, and
        // enough room below for the full soil column plus bedrock.
        let highest = 1;
        let lowest = height.saturating_sub(SOIL_DEPTH + 2).max(highest);

        let baseline = height as f32 / 3.0;
        let relief = (height as f32 * 0.12).max(4.0);

        let mut surfaces = vec![0usize; width];

        for x in 0..width {
            let roll = fbm_1d(seed, x as f32 * SURFACE_FREQUENCY, SURFACE_OCTAVES) - 0.5;
            let surface = (baseline + roll * 2.0 * relief).round() as isize;
            let surface = (surface.clamp(highest as isize, lowest as isize)) as usize;
            surfaces[x] = surface;

            for y in surface..height {
                tiles[y * width + x] = if y == surface {
                    Tile::Grass
                } else if y < surface + SOIL_DEPTH {
                    Tile::Dirt
                } else {
                    Tile::Stone
                };
            }
        }

        // Carve caves through stone only: the grass cap and soil stay intact,
        // and the bottom rows stay solid.
        let cave_floor = height.saturating_sub(BEDROCK_ROWS);
        let cave_seed = seed ^ CAVE_SEED_SALT;

        for x in 0..width {
            let cave_ceiling = surfaces[x] + SOIL_DEPTH + CAVE_CEILING_MARGIN;

            for y in cave_ceiling..cave_floor {
                let field = fbm_2d(
                    cave_seed,
                    x as f32 * CAVE_FREQUENCY_X,
                    y as f32 * CAVE_FREQUENCY_Y,
                    CAVE_OCTAVES,
                );

                if (field - 0.5).abs() < CAVE_BAND {
                    tiles[y * width + x] = Tile::Air;
                }
            }
        }

        World {
            width,
            height,
            tiles,
        }
    }

    /// The `y` of the topmost solid tile in column `x`, if the column has one.
    pub fn surface_y(&self, x: usize) -> Option<usize> {
        (0..self.height).find(|&y| self.tile(x, y) != Tile::Air)
    }

    pub fn width(&self) -> usize {
        self.width
    }

    pub fn height(&self) -> usize {
        self.height
    }

    /// The tile at `(x, y)`, or `Tile::Air` outside the world bounds.
    pub fn tile(&self, x: usize, y: usize) -> Tile {
        if x >= self.width || y >= self.height {
            return Tile::Air;
        }
        self.tiles[y * self.width + x]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_produces_world_of_requested_dimensions() {
        let world = World::generate(1, 64, 32);

        assert_eq!(world.width(), 64);
        assert_eq!(world.height(), 32);
    }

    #[test]
    fn generate_puts_open_sky_at_the_top_and_solid_rock_at_the_bottom() {
        let world = World::generate(7, 64, 64);

        for x in 0..world.width() {
            assert_eq!(
                world.tile(x, 0),
                Tile::Air,
                "column {x} should be open sky at the very top"
            );
            assert_eq!(
                world.tile(x, world.height() - 1),
                Tile::Stone,
                "column {x} should be solid rock at the very bottom"
            );
        }
    }

    #[test]
    fn topmost_solid_tile_of_every_column_is_grass() {
        let world = World::generate(7, 64, 64);

        for x in 0..world.width() {
            let surface = world
                .surface_y(x)
                .unwrap_or_else(|| panic!("column {x} has no solid ground at all"));

            assert_eq!(
                world.tile(x, surface),
                Tile::Grass,
                "column {x} should be capped with grass at y={surface}"
            );
        }
    }

    #[test]
    fn underground_is_riddled_with_cave_space() {
        let world = World::generate(7, 256, 160);

        let mut deep_tiles = 0usize;
        let mut open_tiles = 0usize;

        for x in 0..world.width() {
            let surface = world.surface_y(x).expect("every column has ground");

            // Start well below the soil so we are measuring caves, not sky.
            for y in (surface + 12)..world.height() {
                deep_tiles += 1;
                if world.tile(x, y) == Tile::Air {
                    open_tiles += 1;
                }
            }
        }

        let open_fraction = open_tiles as f32 / deep_tiles as f32;

        assert!(
            (0.05..0.40).contains(&open_fraction),
            "underground should be caved but not hollow; {:.1}% of deep rock is open",
            open_fraction * 100.0
        );
    }

    #[test]
    fn surface_height_varies_across_the_world() {
        let world = World::generate(7, 256, 128);

        let heights: std::collections::BTreeSet<usize> =
            (0..world.width()).filter_map(|x| world.surface_y(x)).collect();

        assert!(
            heights.len() >= 8,
            "terrain should roll, not be a flat plane; got {} distinct surface heights: {:?}",
            heights.len(),
            heights
        );
    }
}
