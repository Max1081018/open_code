//! The tile world: storage and generation.

use crate::biome::biome_at;
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
    Sand,
    Snow,
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

    /// Stable numeric id for save files. Values must never be reassigned.
    pub fn to_id(self) -> u8 {
        match self {
            Tile::Air => 0,
            Tile::Dirt => 1,
            Tile::Grass => 2,
            Tile::Stone => 3,
            Tile::CoalOre => 4,
            Tile::CopperOre => 5,
            Tile::IronOre => 6,
            Tile::GoldOre => 7,
            Tile::Sand => 8,
            Tile::Snow => 9,
        }
    }

    /// Recover a tile from its save-file id, or `None` if unrecognised.
    pub fn from_id(id: u8) -> Option<Tile> {
        Some(match id {
            0 => Tile::Air,
            1 => Tile::Dirt,
            2 => Tile::Grass,
            3 => Tile::Stone,
            4 => Tile::CoalOre,
            5 => Tile::CopperOre,
            6 => Tile::IronOre,
            7 => Tile::GoldOre,
            8 => Tile::Sand,
            9 => Tile::Snow,
            _ => return None,
        })
    }

    /// How much work it takes to break this tile, or `None` if there is
    /// nothing there to break.
    pub fn hardness(self) -> Option<f32> {
        match self {
            Tile::Air => None,
            Tile::Grass | Tile::Dirt => Some(1.0),
            // Loose material gives way faster than packed soil.
            Tile::Sand => Some(0.8),
            Tile::Snow => Some(0.6),
            Tile::Stone => Some(2.5),
            Tile::CoalOre => Some(3.0),
            Tile::CopperOre => Some(3.5),
            Tile::IronOre => Some(4.5),
            Tile::GoldOre => Some(6.0),
        }
    }

    /// Whether the tile is an ore deposit embedded in stone.
    pub fn is_ore(self) -> bool {
        matches!(
            self,
            Tile::CoalOre | Tile::CopperOre | Tile::IronOre | Tile::GoldOre
        )
    }
}

/// The background behind a tile.
///
/// Walls are what you see through a tunnel you have dug: the material is
/// still there behind you, so the hole does not read as open sky. Natural
/// caves have no wall, which is what makes them read as genuinely hollow.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum Wall {
    /// Open to whatever is behind the world.
    #[default]
    None,
    Soil,
    Rock,
    Sand,
}

impl Wall {
    /// The wall left behind when `tile` is dug out.
    pub fn behind(tile: Tile) -> Wall {
        match tile {
            Tile::Air => Wall::None,
            Tile::Dirt | Tile::Grass | Tile::Snow => Wall::Soil,
            Tile::Sand => Wall::Sand,
            _ => Wall::Rock,
        }
    }

    /// Base colour of the wall, before it is darkened for depth.
    pub fn colour(self) -> Option<[f32; 3]> {
        match self {
            Wall::None => None,
            Wall::Soil => Some([134.0, 96.0, 62.0]),
            Wall::Rock => Some([118.0, 118.0, 126.0]),
            Wall::Sand => Some([214.0, 192.0, 138.0]),
        }
    }
}

/// How much darker a wall is than the tile it sits behind.
pub const WALL_DIMMING: f32 = 0.42;

/// A generated tile world, addressed by `(x, y)` with `y = 0` at the top.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct World {
    width: usize,
    height: usize,
    tiles: Vec<Tile>,
    walls: Vec<Wall>,
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

            let biome = biome_at(seed, x);

            for y in surface..height {
                tiles[y * width + x] = if y == surface {
                    biome.surface_tile()
                } else if y < surface + SOIL_DEPTH {
                    biome.soil_tile()
                } else {
                    Tile::Stone
                };
            }
        }

        // Walls are taken from the solid terrain *before* caves are cut, so
        // a tunnel the player digs still has material behind it.
        let mut walls: Vec<Wall> = tiles.iter().map(|&tile| Wall::behind(tile)).collect();

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
                    // A natural cavern is open space, not a dug tunnel.
                    walls[y * width + x] = Wall::None;
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
            walls,
        }
    }

    /// The `y` of the topmost solid tile in column `x`, if the column has one.
    pub fn surface_y(&self, x: usize) -> Option<usize> {
        (0..self.height).find(|&y| self.tile(x, y) != Tile::Air)
    }

    /// Build a world directly from a tile grid, row-major, `y = 0` at the top.
    ///
    /// Used by tests and, later, by save-file loading.
    pub fn from_tiles(width: usize, height: usize, tiles: Vec<Tile>) -> World {
        assert_eq!(
            tiles.len(),
            width * height,
            "tile grid must hold exactly width * height tiles"
        );

        World {
            width,
            height,
            walls: vec![Wall::None; tiles.len()],
            tiles,
        }
    }

    /// The wall behind `(x, y)`, or `Wall::None` outside the world.
    pub fn wall(&self, x: usize, y: usize) -> Wall {
        if x >= self.width || y >= self.height {
            return Wall::None;
        }
        self.walls[y * self.width + x]
    }

    /// Overwrite the wall behind `(x, y)`. Out-of-bounds writes are ignored.
    pub fn set_wall(&mut self, x: usize, y: usize, wall: Wall) {
        if x >= self.width || y >= self.height {
            return;
        }
        self.walls[y * self.width + x] = wall;
    }

    /// Recompute walls from the seed that produced this world.
    ///
    /// Walls never change during play, so they are not written to save
    /// files; a loaded world rebuilds them from its seed instead.
    pub fn rebuild_walls(&mut self, seed: u64) {
        let fresh = World::generate(seed, self.width, self.height);
        self.walls = fresh.walls;
    }

    pub fn width(&self) -> usize {
        self.width
    }

    pub fn height(&self) -> usize {
        self.height
    }

    /// Overwrite the tile at `(x, y)`. Out-of-bounds writes are ignored.
    pub fn set_tile(&mut self, x: usize, y: usize, tile: Tile) {
        if x >= self.width || y >= self.height {
            return;
        }
        self.tiles[y * self.width + x] = tile;
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
    fn topmost_solid_tile_of_every_column_matches_its_biome() {
        const SEED: u64 = 7;
        let world = World::generate(SEED, 64, 64);

        for x in 0..world.width() {
            let surface = world
                .surface_y(x)
                .unwrap_or_else(|| panic!("column {x} has no solid ground at all"));

            let biome = crate::biome::biome_at(SEED, x);

            assert_eq!(
                world.tile(x, surface),
                biome.surface_tile(),
                "column {x} is in {} but is capped with {:?} at y={surface}",
                biome.name(),
                world.tile(x, surface)
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
    fn every_tile_round_trips_through_its_save_id() {
        for tile in [
            Tile::Air,
            Tile::Dirt,
            Tile::Grass,
            Tile::Stone,
            Tile::CoalOre,
            Tile::CopperOre,
            Tile::IronOre,
            Tile::GoldOre,
        ] {
            assert_eq!(
                Tile::from_id(tile.to_id()),
                Some(tile),
                "{tile:?} did not survive its id"
            );
        }
    }

    #[test]
    fn distinct_tiles_have_distinct_save_ids() {
        let ids: std::collections::BTreeSet<u8> = [
            Tile::Air,
            Tile::Dirt,
            Tile::Grass,
            Tile::Stone,
            Tile::CoalOre,
            Tile::CopperOre,
            Tile::IronOre,
            Tile::GoldOre,
        ]
        .into_iter()
        .map(|tile| tile.to_id())
        .collect();

        assert_eq!(ids.len(), 8, "ids must be unique, got {ids:?}");
    }

    #[test]
    fn an_unrecognised_save_id_is_rejected() {
        assert_eq!(Tile::from_id(250), None);
    }

    #[test]
    fn dug_ground_leaves_a_wall_behind_it() {
        let world = World::generate(7, 128, 96);

        // Find a solid tile a few rows under the surface.
        let column = 40;
        let surface = world.surface_y(column).expect("ground");
        let buried = surface + 3;

        assert!(world.tile(column, buried).is_solid(), "precondition");
        assert_ne!(
            world.wall(column, buried),
            Wall::None,
            "buried ground should have material behind it, or a dug tunnel \
             would show open sky"
        );
    }

    #[test]
    fn open_sky_has_no_wall_behind_it() {
        let world = World::generate(7, 128, 96);

        for x in (0..128).step_by(7) {
            assert_eq!(
                world.wall(x, 0),
                Wall::None,
                "the sky at column {x} should not be walled"
            );
        }
    }

    #[test]
    fn natural_caves_are_hollow_rather_than_walled() {
        let world = World::generate(7, 256, 160);

        // A carved cave is air well below the surface with no wall.
        let hollow = (0..world.width()).any(|x| {
            let Some(surface) = world.surface_y(x) else {
                return false;
            };
            ((surface + 14)..world.height()).any(|y| {
                !world.tile(x, y).is_solid() && world.wall(x, y) == Wall::None
            })
        });

        assert!(
            hollow,
            "natural caverns should read as genuinely hollow, not papered over"
        );
    }

    #[test]
    fn walls_match_the_material_that_was_there() {
        assert_eq!(Wall::behind(Tile::Stone), Wall::Rock);
        assert_eq!(Wall::behind(Tile::Dirt), Wall::Soil);
        assert_eq!(Wall::behind(Tile::Grass), Wall::Soil);
        assert_eq!(Wall::behind(Tile::Sand), Wall::Sand);
        assert_eq!(Wall::behind(Tile::Air), Wall::None);
        // Ore sits in rock, so its wall is rock.
        assert_eq!(Wall::behind(Tile::GoldOre), Wall::Rock);
    }

    #[test]
    fn only_open_wall_has_no_colour() {
        assert_eq!(Wall::None.colour(), None);

        for wall in [Wall::Soil, Wall::Rock, Wall::Sand] {
            assert!(wall.colour().is_some(), "{wall:?} needs a colour to draw");
        }
    }

    #[test]
    fn mining_a_tile_does_not_remove_the_wall_behind_it() {
        let mut world = World::generate(7, 128, 96);
        let column = 40;
        let surface = world.surface_y(column).expect("ground");
        let buried = surface + 3;

        let before = world.wall(column, buried);
        world.set_tile(column, buried, Tile::Air);

        assert_eq!(
            world.wall(column, buried),
            before,
            "digging should leave the background intact"
        );
    }

    #[test]
    fn walls_can_be_rebuilt_from_the_seed() {
        let original = World::generate(7, 96, 64);

        // A world loaded from a save has tiles but no walls.
        let mut loaded = World::from_tiles(96, 64, (0..96 * 64).map(|i| original.tile(i % 96, i / 96)).collect());
        assert_eq!(loaded.wall(40, 40), Wall::None, "precondition");

        loaded.rebuild_walls(7);

        for x in (0..96).step_by(5) {
            for y in (0..64).step_by(5) {
                assert_eq!(loaded.wall(x, y), original.wall(x, y), "at ({x}, {y})");
            }
        }
    }

    #[test]
    fn from_tiles_preserves_the_supplied_grid() {
        let world = World::from_tiles(2, 2, vec![Tile::Air, Tile::Stone, Tile::Dirt, Tile::Grass]);

        assert_eq!(world.width(), 2);
        assert_eq!(world.height(), 2);
        assert_eq!(world.tile(0, 0), Tile::Air);
        assert_eq!(world.tile(1, 0), Tile::Stone);
        assert_eq!(world.tile(0, 1), Tile::Dirt);
        assert_eq!(world.tile(1, 1), Tile::Grass);
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
