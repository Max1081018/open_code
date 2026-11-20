//! Compositing the tile world into chunk-sized images.
//!
//! Drawing one sprite per tile would mean thousands of draw calls per frame.
//! Instead each chunk is composited once into a single texture and redrawn as
//! one quad, and only re-composited when a tile inside it changes.

use crate::art::{
    edge_shade, tile_texture, variant_for, variant_seed, Exposure, Texture, TEXTURE_VARIANTS,
};
use crate::view::TILE_SOURCE_PX;
use crate::world::{Tile, World, WALL_DIMMING};

/// Keeps wall grain independent of every other noise field.
const WALL_GRAIN_SALT: u64 = 0x5A11_B00C_5A11_B00C;

/// Edge length of a chunk, in tiles.
pub const CHUNK_TILES: usize = 16;

/// Edge length of a composited chunk texture, in texels.
pub const CHUNK_TEXELS: u32 = CHUNK_TILES as u32 * TILE_SOURCE_PX;

/// A cache of per-material, per-variant tile textures.
///
/// Building these is the expensive part of compositing, so they are generated
/// once and shared across every chunk.
pub struct TileAtlas {
    seed: u64,
    /// Indexed by material, then by variant.
    textures: Vec<(Tile, Vec<Texture>)>,
}

impl TileAtlas {
    /// Generate every material's variants for `seed`.
    pub fn new(seed: u64) -> TileAtlas {
        let textures = [
            Tile::Dirt,
            Tile::Grass,
            Tile::Sand,
            Tile::Snow,
            Tile::Stone,
            Tile::CoalOre,
            Tile::CopperOre,
            Tile::IronOre,
            Tile::GoldOre,
        ]
        .into_iter()
        .map(|tile| {
            let variants = (0..TEXTURE_VARIANTS)
                .filter_map(|variant| tile_texture(tile, variant_seed(seed, variant)))
                .collect();
            (tile, variants)
        })
        .collect();

        TileAtlas { seed, textures }
    }

    /// The texture for `tile` at `variant`, or `None` for empty space.
    pub fn get(&self, tile: Tile, variant: u32) -> Option<&Texture> {
        let (_, variants) = self.textures.iter().find(|(kind, _)| *kind == tile)?;

        if variants.is_empty() {
            return None;
        }

        variants.get(variant as usize % variants.len())
    }

    pub fn seed(&self) -> u64 {
        self.seed
    }
}

/// Composite the chunk at `(chunk_x, chunk_y)` into a single RGBA texture.
///
/// Empty space is left fully transparent so the sky or background layer shows
/// through.
pub fn chunk_texture(
    world: &World,
    atlas: &TileAtlas,
    chunk_x: usize,
    chunk_y: usize,
) -> Texture {
    let size = CHUNK_TEXELS;
    // Zeroed, so untouched texels stay fully transparent.
    let mut pixels = vec![0u8; (size * size * 4) as usize];

    for ty in 0..CHUNK_TILES {
        for tx in 0..CHUNK_TILES {
            let wx = chunk_x * CHUNK_TILES + tx;
            let wy = chunk_y * CHUNK_TILES + ty;

            let tile = world.tile(wx, wy);

            // Paint the wall first, so a dug tunnel shows the material
            // behind it rather than open sky. Walls are dimmed and flat:
            // they must read as background, never compete with the tiles.
            if let Some(colour) = world.wall(wx, wy).colour() {
                let origin_x = tx as u32 * TILE_SOURCE_PX;
                let origin_y = ty as u32 * TILE_SOURCE_PX;

                for sy in 0..TILE_SOURCE_PX {
                    for sx in 0..TILE_SOURCE_PX {
                        // A little grain, so a wall is not a flat rectangle.
                        let grain = crate::noise::hash01(
                            atlas.seed ^ WALL_GRAIN_SALT,
                            ((wy * 4096 + wx) * 97 + (sy * TILE_SOURCE_PX + sx) as usize) as i64,
                        ) - 0.5;
                        let shade = WALL_DIMMING * (1.0 + grain * 0.16);

                        let i = (((origin_y + sy) * size + origin_x + sx) * 4) as usize;
                        pixels[i] = (colour[0] * shade) as u8;
                        pixels[i + 1] = (colour[1] * shade) as u8;
                        pixels[i + 2] = (colour[2] * shade) as u8;
                        pixels[i + 3] = 255;
                    }
                }
            }

            let Some(texture) = atlas.get(tile, variant_for(atlas.seed, wx, wy)) else {
                continue;
            };

            let exposure = exposure_at(world, wx, wy);
            let origin_x = tx as u32 * TILE_SOURCE_PX;
            let origin_y = ty as u32 * TILE_SOURCE_PX;

            for sy in 0..TILE_SOURCE_PX {
                for sx in 0..TILE_SOURCE_PX {
                    let [r, g, b, a] = texture.pixel(sx, sy);
                    let shade = edge_shade(exposure, sx, sy, TILE_SOURCE_PX);

                    let i = (((origin_y + sy) * size + origin_x + sx) * 4) as usize;
                    pixels[i] = (r as f32 * shade).clamp(0.0, 255.0) as u8;
                    pixels[i + 1] = (g as f32 * shade).clamp(0.0, 255.0) as u8;
                    pixels[i + 2] = (b as f32 * shade).clamp(0.0, 255.0) as u8;
                    pixels[i + 3] = a;
                }
            }
        }
    }

    Texture {
        width: size,
        height: size,
        pixels,
    }
}

/// Which sides of the tile at `(x, y)` open onto empty space.
pub fn exposure_at(world: &World, x: usize, y: usize) -> Exposure {
    let open = |x: usize, y: usize| !world.tile(x, y).is_solid();

    Exposure {
        top: y == 0 || open(x, y - 1),
        bottom: open(x, y + 1),
        left: x == 0 || open(x - 1, y),
        right: open(x + 1, y),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn solid_world() -> World {
        World::from_tiles(
            CHUNK_TILES * 2,
            CHUNK_TILES * 2,
            vec![Tile::Stone; CHUNK_TILES * CHUNK_TILES * 4],
        )
    }

    fn empty_world() -> World {
        World::from_tiles(
            CHUNK_TILES * 2,
            CHUNK_TILES * 2,
            vec![Tile::Air; CHUNK_TILES * CHUNK_TILES * 4],
        )
    }

    #[test]
    fn atlas_supplies_a_texture_for_every_solid_material() {
        let atlas = TileAtlas::new(3);

        for tile in [
            Tile::Dirt,
            Tile::Grass,
            Tile::Stone,
            Tile::CoalOre,
            Tile::CopperOre,
            Tile::IronOre,
            Tile::GoldOre,
        ] {
            assert!(
                atlas.get(tile, 0).is_some(),
                "{tile:?} should have a texture in the atlas"
            );
        }
    }

    #[test]
    fn atlas_has_no_texture_for_empty_space() {
        let atlas = TileAtlas::new(3);

        assert!(atlas.get(Tile::Air, 0).is_none());
    }

    #[test]
    fn composited_chunk_is_one_chunk_square() {
        let world = solid_world();
        let atlas = TileAtlas::new(3);

        let chunk = chunk_texture(&world, &atlas, 0, 0);

        assert_eq!(chunk.width, CHUNK_TEXELS);
        assert_eq!(chunk.height, CHUNK_TEXELS);
        assert_eq!(chunk.pixels.len(), (CHUNK_TEXELS * CHUNK_TEXELS * 4) as usize);
    }

    #[test]
    fn empty_space_composites_as_fully_transparent() {
        let world = empty_world();
        let atlas = TileAtlas::new(3);

        let chunk = chunk_texture(&world, &atlas, 0, 0);

        for y in 0..chunk.height {
            for x in 0..chunk.width {
                assert_eq!(
                    chunk.pixel(x, y)[3],
                    0,
                    "air at ({x}, {y}) should be transparent"
                );
            }
        }
    }

    #[test]
    fn solid_ground_composites_as_fully_opaque() {
        let world = solid_world();
        let atlas = TileAtlas::new(3);

        let chunk = chunk_texture(&world, &atlas, 0, 0);

        for y in 0..chunk.height {
            for x in 0..chunk.width {
                assert_eq!(
                    chunk.pixel(x, y)[3],
                    255,
                    "stone at ({x}, {y}) should be opaque"
                );
            }
        }
    }

    #[test]
    fn each_chunk_shows_its_own_region_of_the_world() {
        // Left half stone, right half air, split down the chunk boundary.
        let width = CHUNK_TILES * 2;
        let height = CHUNK_TILES * 2;
        let mut tiles = vec![Tile::Air; width * height];
        for y in 0..height {
            for x in 0..CHUNK_TILES {
                tiles[y * width + x] = Tile::Stone;
            }
        }
        let world = World::from_tiles(width, height, tiles);
        let atlas = TileAtlas::new(3);

        let left = chunk_texture(&world, &atlas, 0, 0);
        let right = chunk_texture(&world, &atlas, 1, 0);

        assert_eq!(left.pixel(10, 10)[3], 255, "left chunk should hold stone");
        assert_eq!(right.pixel(10, 10)[3], 0, "right chunk should be empty");
    }

    #[test]
    fn a_dug_tunnel_shows_its_wall_rather_than_open_sky() {
        let mut world = World::generate(7, CHUNK_TILES * 4, CHUNK_TILES * 4);
        let atlas = TileAtlas::new(7);

        // Dig out a buried tile, which should leave its wall behind.
        let column = 20;
        let surface = world.surface_y(column).expect("ground");
        let dug = surface + 4;
        assert!(world.tile(column, dug).is_solid(), "precondition: solid");
        world.set_tile(column, dug, Tile::Air);

        let chunk = chunk_texture(&world, &atlas, column / CHUNK_TILES, dug / CHUNK_TILES);

        let px = (column % CHUNK_TILES) as u32 * TILE_SOURCE_PX + TILE_SOURCE_PX / 2;
        let py = (dug % CHUNK_TILES) as u32 * TILE_SOURCE_PX + TILE_SOURCE_PX / 2;

        assert_eq!(
            chunk.pixel(px, py)[3],
            255,
            "a dug tunnel should show the wall behind it, not the sky"
        );
    }

    #[test]
    fn a_wall_is_darker_than_the_tile_it_sits_behind() {
        let mut world = World::generate(7, CHUNK_TILES * 4, CHUNK_TILES * 4);
        let atlas = TileAtlas::new(7);

        let column = 20;
        let surface = world.surface_y(column).expect("ground");
        let dug = surface + 4;

        let solid = chunk_texture(&world, &atlas, column / CHUNK_TILES, dug / CHUNK_TILES);
        world.set_tile(column, dug, Tile::Air);
        let hollow = chunk_texture(&world, &atlas, column / CHUNK_TILES, dug / CHUNK_TILES);

        let px = (column % CHUNK_TILES) as u32 * TILE_SOURCE_PX + TILE_SOURCE_PX / 2;
        let py = (dug % CHUNK_TILES) as u32 * TILE_SOURCE_PX + TILE_SOURCE_PX / 2;

        let brightness = |t: &Texture| {
            let p = t.pixel(px, py);
            p[0] as u32 + p[1] as u32 + p[2] as u32
        };

        assert!(
            brightness(&hollow) < brightness(&solid),
            "the background must recede behind the foreground, not match it"
        );
    }

    #[test]
    fn compositing_is_deterministic() {
        let world = solid_world();
        let atlas = TileAtlas::new(3);

        assert_eq!(
            chunk_texture(&world, &atlas, 0, 0),
            chunk_texture(&world, &atlas, 0, 0)
        );
    }

    #[test]
    fn a_buried_tile_composites_flatter_than_an_exposed_one() {
        // One lone block of stone, so every side is exposed.
        let width = CHUNK_TILES;
        let mut tiles = vec![Tile::Air; width * width];
        tiles[5 * width + 5] = Tile::Stone;
        let lone = World::from_tiles(width, width, tiles);

        let buried = solid_world();
        let atlas = TileAtlas::new(3);

        let lone_chunk = chunk_texture(&lone, &atlas, 0, 0);
        let buried_chunk = chunk_texture(&buried, &atlas, 0, 0);

        // Top-left texel of tile (5,5) in each: exposed should be brighter.
        let px = 5 * TILE_SOURCE_PX;
        let exposed = lone_chunk.pixel(px, px)[0];
        let enclosed = buried_chunk.pixel(px, px)[0];

        assert!(
            exposed > enclosed,
            "an exposed corner should be lit brighter than a buried one; \
             {exposed} vs {enclosed}"
        );
    }

    #[test]
    fn exposure_reports_open_sides_only() {
        let width = CHUNK_TILES;
        let mut tiles = vec![Tile::Air; width * width];
        // Stone at (5,5) with solid stone above it only.
        tiles[5 * width + 5] = Tile::Stone;
        tiles[4 * width + 5] = Tile::Stone;
        let world = World::from_tiles(width, width, tiles);

        let exposure = exposure_at(&world, 5, 5);

        assert!(!exposure.top, "tile above is solid, so top is not exposed");
        assert!(exposure.bottom, "nothing below, so bottom is exposed");
        assert!(exposure.left, "nothing to the left");
        assert!(exposure.right, "nothing to the right");
    }
}
