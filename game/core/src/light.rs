//! Sky-light propagation.
//!
//! The map stores how much *open sky* reaches each tile, independent of the
//! time of day. The renderer multiplies that by the current sky brightness,
//! so dusk falling over the whole world costs one multiply per tile rather
//! than a full re-propagation.

use std::collections::VecDeque;

use crate::world::World;

/// Brightest possible light level.
pub const MAX_LIGHT: u8 = 15;

/// Light lost crossing one tile of open air.
const AIR_COST: u8 = 1;

/// Light lost crossing one tile of solid rock. Higher than air, so daylight
/// fades out within a few tiles of the surface: enough to see the ground you
/// are digging, not enough to light a cave.
const SOLID_COST: u8 = 3;

/// How far sky light reaches into the world.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LightMap {
    width: usize,
    height: usize,
    levels: Vec<u8>,
}

impl LightMap {
    pub fn width(&self) -> usize {
        self.width
    }

    pub fn height(&self) -> usize {
        self.height
    }

    /// Light level at `(x, y)`, or full light outside the world.
    pub fn level(&self, x: usize, y: usize) -> u8 {
        if x >= self.width || y >= self.height {
            return MAX_LIGHT;
        }
        self.levels[y * self.width + x]
    }

    /// Light at `(x, y)` as a fraction in `[0, 1]`.
    pub fn brightness(&self, x: usize, y: usize) -> f32 {
        self.level(x, y) as f32 / MAX_LIGHT as f32
    }
}

/// Work out how much sky reaches every tile of `world`.
pub fn compute_sky_light(world: &World) -> LightMap {
    let width = world.width();
    let height = world.height();

    let mut levels = vec![0u8; width * height];
    let mut frontier = VecDeque::new();

    // Seed every tile with an unobstructed view of the sky.
    for x in 0..width {
        for y in 0..height {
            if world.tile(x, y).is_solid() {
                break;
            }

            levels[y * width + x] = MAX_LIGHT;
            frontier.push_back((x, y));
        }
    }

    while let Some((x, y)) = frontier.pop_front() {
        let here = levels[y * width + x];
        if here == 0 {
            continue;
        }

        let neighbours = [
            (x.checked_sub(1), Some(y)),
            (Some(x + 1), Some(y)),
            (Some(x), y.checked_sub(1)),
            (Some(x), Some(y + 1)),
        ];

        for (nx, ny) in neighbours {
            let (Some(nx), Some(ny)) = (nx, ny) else {
                continue;
            };
            if nx >= width || ny >= height {
                continue;
            }

            let solid = world.tile(nx, ny).is_solid();
            let candidate = here.saturating_sub(if solid { SOLID_COST } else { AIR_COST });

            if candidate > levels[ny * width + nx] {
                levels[ny * width + nx] = candidate;
                frontier.push_back((nx, ny));
            }
        }
    }

    LightMap {
        width,
        height,
        levels,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::Tile;

    const WIDTH: usize = 24;
    const HEIGHT: usize = 40;

    /// Open above `surface`, solid from it down.
    fn flat_world(surface: usize) -> World {
        let mut tiles = vec![Tile::Air; WIDTH * HEIGHT];
        for x in 0..WIDTH {
            for y in surface..HEIGHT {
                tiles[y * WIDTH + x] = Tile::Stone;
            }
        }
        World::from_tiles(WIDTH, HEIGHT, tiles)
    }

    #[test]
    fn open_sky_is_fully_lit() {
        let light = compute_sky_light(&flat_world(20));

        for x in 0..WIDTH {
            for y in 0..20 {
                assert_eq!(
                    light.level(x, y),
                    MAX_LIGHT,
                    "open air at ({x}, {y}) should be fully lit"
                );
            }
        }
    }

    #[test]
    fn the_ground_surface_catches_light_but_dims() {
        let light = compute_sky_light(&flat_world(20));

        let surface = light.level(10, 20);

        assert!(surface > 0, "the lit face of the ground should not be black");
        assert!(
            surface < MAX_LIGHT,
            "rock should be dimmer than open air, got {surface}"
        );
    }

    #[test]
    fn deep_rock_is_pitch_dark() {
        let light = compute_sky_light(&flat_world(20));

        assert_eq!(
            light.level(10, HEIGHT - 1),
            0,
            "rock far from any opening should be black"
        );
    }

    #[test]
    fn light_falls_off_steadily_with_depth() {
        let light = compute_sky_light(&flat_world(20));

        let mut previous = light.level(10, 20);
        for y in 21..26 {
            let current = light.level(10, y);
            assert!(
                current <= previous,
                "light should not brighten going down: {previous} then {current} at y={y}"
            );
            previous = current;
        }
    }

    #[test]
    fn a_shaft_carries_daylight_underground() {
        let mut tiles = vec![Tile::Air; WIDTH * HEIGHT];
        for x in 0..WIDTH {
            for y in 20..HEIGHT {
                tiles[y * WIDTH + x] = Tile::Stone;
            }
        }
        // A one-tile shaft straight down from the surface.
        for y in 20..30 {
            tiles[y * WIDTH + 12] = Tile::Air;
        }
        let world = World::from_tiles(WIDTH, HEIGHT, tiles);

        let light = compute_sky_light(&world);

        assert!(
            light.level(12, 24) > 0,
            "the shaft should carry some daylight to y=24"
        );
        assert!(
            light.level(4, 24) == 0,
            "rock away from the shaft should stay dark"
        );
    }

    /// A shaft dug straight down, with a side branch at the bottom.
    fn shaft_with_branch() -> World {
        let mut tiles = vec![Tile::Air; WIDTH * HEIGHT];
        for x in 0..WIDTH {
            for y in 20..HEIGHT {
                tiles[y * WIDTH + x] = Tile::Stone;
            }
        }
        for y in 20..30 {
            tiles[y * WIDTH + 12] = Tile::Air;
        }
        for x in 13..20 {
            tiles[28 * WIDTH + x] = Tile::Air;
        }
        World::from_tiles(WIDTH, HEIGHT, tiles)
    }

    #[test]
    fn a_straight_shaft_to_open_sky_stays_lit() {
        // Deliberate: sunlight reaches the bottom of a shaft dug straight
        // down. Natural caves still go dark, because they are not open to
        // the sky — only a shaft the player digs is.
        let light = compute_sky_light(&shaft_with_branch());

        assert_eq!(
            light.level(12, 28),
            MAX_LIGHT,
            "a straight shaft should carry full daylight down"
        );
    }

    #[test]
    fn light_dims_along_a_branch_leading_off_a_shaft() {
        let light = compute_sky_light(&shaft_with_branch());

        assert!(
            light.level(13, 28) > light.level(19, 28),
            "the far end of the branch should be darker than its mouth"
        );
        assert!(
            light.level(13, 28) > 0,
            "the mouth of the branch should catch light"
        );
    }

    #[test]
    fn a_sealed_cavern_stays_dark() {
        let mut tiles = vec![Tile::Stone; WIDTH * HEIGHT];
        // Open sky across the top so there is light to exclude.
        for x in 0..WIDTH {
            for y in 0..5 {
                tiles[y * WIDTH + x] = Tile::Air;
            }
        }
        // A pocket of air deep down, sealed on every side.
        for x in 10..14 {
            for y in 30..34 {
                tiles[y * WIDTH + x] = Tile::Air;
            }
        }
        let world = World::from_tiles(WIDTH, HEIGHT, tiles);

        let light = compute_sky_light(&world);

        assert_eq!(
            light.level(12, 32),
            0,
            "a sealed cavern should be pitch black"
        );
    }

    #[test]
    fn light_never_exceeds_the_maximum() {
        let light = compute_sky_light(&flat_world(20));

        for x in 0..WIDTH {
            for y in 0..HEIGHT {
                assert!(
                    light.level(x, y) <= MAX_LIGHT,
                    "level at ({x}, {y}) is out of range"
                );
            }
        }
    }

    #[test]
    fn brightness_is_a_unit_fraction_of_the_level() {
        let light = compute_sky_light(&flat_world(20));

        assert_eq!(light.brightness(5, 0), 1.0, "open sky is full brightness");
        assert_eq!(light.brightness(5, HEIGHT - 1), 0.0, "deep rock is zero");
    }

    #[test]
    fn a_world_with_no_sky_is_entirely_dark() {
        let world = World::from_tiles(WIDTH, HEIGHT, vec![Tile::Stone; WIDTH * HEIGHT]);

        let light = compute_sky_light(&world);

        for x in 0..WIDTH {
            for y in 0..HEIGHT {
                assert_eq!(light.level(x, y), 0, "({x}, {y}) should be black");
            }
        }
    }

    #[test]
    fn light_spreads_sideways_into_an_overhang() {
        let mut tiles = vec![Tile::Air; WIDTH * HEIGHT];
        for x in 0..WIDTH {
            for y in 20..HEIGHT {
                tiles[y * WIDTH + x] = Tile::Stone;
            }
        }
        // A horizontal tunnel running in from an open cliff face at x=0.
        for x in 0..10 {
            tiles[25 * WIDTH + x] = Tile::Air;
            tiles[24 * WIDTH + x] = Tile::Air;
        }
        // Open the cliff so the tunnel mouth sees sky.
        for y in 20..26 {
            tiles[y * WIDTH] = Tile::Air;
        }
        let world = World::from_tiles(WIDTH, HEIGHT, tiles);

        let light = compute_sky_light(&world);

        assert!(
            light.level(3, 25) > 0,
            "light should reach along the tunnel"
        );
        assert!(
            light.level(1, 25) > light.level(8, 25),
            "the tunnel mouth should be brighter than its far end"
        );
    }
}
