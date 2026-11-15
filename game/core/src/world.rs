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

/// Octaves for ore seams: few, so deposits come out as chunky blobs rather
/// than single scattered pixels.
const ORE_OCTAVES: u32 = 2;

/// One kind of ore deposit and the rules governing where it appears.
struct OreSeam {
    tile: Tile,
    /// Fraction of world height above which this ore never appears.
    min_depth: f32,
    /// Spatial scale of the deposits; higher means smaller, tighter clumps.
    frequency: f32,
    /// Noise above this becomes ore. Higher is rarer.
    threshold: f32,
    salt: u64,
}

/// Checked in order, so the most precious ore wins a contested tile.
const ORE_SEAMS: [OreSeam; 4] = [
    OreSeam {
        tile: Tile::GoldOre,
        min_depth: 0.62,
        frequency: 0.14,
        threshold: 0.90,
        salt: 0x6_01D_6017_601D,
    },
    OreSeam {
        tile: Tile::IronOre,
        min_depth: 0.40,
        frequency: 0.13,
        threshold: 0.885,
        salt: 0x1_205_1205_1205,
    },
    OreSeam {
        tile: Tile::CopperOre,
        min_depth: 0.0,
        frequency: 0.12,
        threshold: 0.87,
        salt: 0xC_0BB_3700_0BB3,
    },
    OreSeam {
        tile: Tile::CoalOre,
        min_depth: 0.0,
        frequency: 0.11,
        threshold: 0.86,
        salt: 0xC_0A1_C0A1_C0A1,
    },
];

/// A single tile of the world grid.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum Tile {
    /// Empty space the player can move through.
    #[default]
    Air,
    Dirt,
    Grass,
    Stone,
    CoalOre,
    CopperOre,
    IronOre,
    GoldOre,
}

impl Tile {
    /// Whether the tile blocks movement.
    pub fn is_solid(self) -> bool {
        self != Tile::Air
    }

    /// Whether the tile is an ore deposit embedded in stone.
    pub fn is_ore(self) -> bool {
        matches!(
            self,
            Tile::CoalOre | Tile::CopperOre | Tile::IronOre | Tile::GoldOre
        )
    }
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

        // Seed ore into stone, after carving, so deposits never hang in open air.
        for x in 0..width {
            for y in 0..height {
                if tiles[y * width + x] != Tile::Stone {
                    continue;
                }

                let depth = y as f32 / height as f32;

                for seam in &ORE_SEAMS {
                    if depth < seam.min_depth {
                        continue;
                    }

                    let field = fbm_2d(
                        seed ^ seam.salt,
                        x as f32 * seam.frequency,
                        y as f32 * seam.frequency,
                        ORE_OCTAVES,
                    );

                    if field > seam.threshold {
                        tiles[y * width + x] = seam.tile;
                        break;
                    }
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
    fn generate_puts_open_sky_at_the_top_and_a_sealed_floor_at_the_bottom() {
        let world = World::generate(7, 64, 64);

        for x in 0..world.width() {
            assert_eq!(
                world.tile(x, 0),
                Tile::Air,
                "column {x} should be open sky at the very top"
            );
            assert!(
                world.tile(x, world.height() - 1).is_solid(),
                "column {x} should have a sealed floor so the player cannot fall out; \
                 found {:?}",
                world.tile(x, world.height() - 1)
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
    fn stone_holds_a_modest_scattering_of_ore() {
        let world = World::generate(7, 256, 160);

        let mut rock = 0usize;
        let mut ore = 0usize;

        for x in 0..world.width() {
            for y in 0..world.height() {
                let tile = world.tile(x, y);
                if tile == Tile::Stone || tile.is_ore() {
                    rock += 1;
                    if tile.is_ore() {
                        ore += 1;
                    }
                }
            }
        }

        let ore_fraction = ore as f32 / rock as f32;

        assert!(
            (0.005..0.12).contains(&ore_fraction),
            "ore should be worth hunting for but not paving the caves; \
             {:.2}% of rock is ore",
            ore_fraction * 100.0
        );
    }

    #[test]
    fn every_ore_kind_appears_somewhere() {
        let world = World::generate(7, 256, 160);

        for kind in [
            Tile::CoalOre,
            Tile::CopperOre,
            Tile::IronOre,
            Tile::GoldOre,
        ] {
            let found = (0..world.width())
                .any(|x| (0..world.height()).any(|y| world.tile(x, y) == kind));

            assert!(found, "{kind:?} never spawned anywhere in the world");
        }
    }

    #[test]
    fn gold_is_confined_to_the_deep_rock() {
        let world = World::generate(7, 256, 160);
        let too_shallow = world.height() * 3 / 5;

        for x in 0..world.width() {
            for y in 0..too_shallow {
                assert_ne!(
                    world.tile(x, y),
                    Tile::GoldOre,
                    "gold at ({x}, {y}) is shallower than y={too_shallow}"
                );
            }
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
