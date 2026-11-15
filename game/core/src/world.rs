//! The tile world: storage and generation.

use crate::noise::fbm_1d;

/// How fast the surface height wanders as you walk sideways. Lower is flatter.
const SURFACE_FREQUENCY: f32 = 0.02;

/// Octaves of noise in the surface heightmap: broad hills plus finer bumps.
const SURFACE_OCTAVES: u32 = 5;

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
        let soil_depth = 5;

        // Keep the rolling surface clear of both edges: open sky above, and
        // enough room below for the full soil column plus bedrock.
        let highest = 1;
        let lowest = height.saturating_sub(soil_depth + 2).max(highest);

        let baseline = height as f32 / 3.0;
        let relief = (height as f32 * 0.12).max(4.0);

        for x in 0..width {
            let roll = fbm_1d(seed, x as f32 * SURFACE_FREQUENCY, SURFACE_OCTAVES) - 0.5;
            let surface = (baseline + roll * 2.0 * relief).round() as isize;
            let surface = (surface.clamp(highest as isize, lowest as isize)) as usize;

            for y in surface..height {
                tiles[y * width + x] = if y == surface {
                    Tile::Grass
                } else if y < surface + soil_depth {
                    Tile::Dirt
                } else {
                    Tile::Stone
                };
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
