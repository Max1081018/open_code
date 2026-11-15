//! Platformer physics: gravity, walking, jumping, and tile collision.
//!
//! Coordinates are in tiles, with `y` increasing **downward** to match the
//! tile grid. Tile `(tx, ty)` occupies the unit square `[tx, tx+1]` by
//! `[ty, ty+1]`, so the walkable top surface of tile row `ty` sits at `y = ty`.

use crate::view::{PLAYER_HEIGHT_TILES, PLAYER_WIDTH_TILES};
use crate::world::World;

/// Downward acceleration, in tiles per second squared.
pub const GRAVITY: f32 = 70.0;

/// Fastest the body may fall, in tiles per second. Caps tunnelling risk and
/// keeps long drops readable.
pub const TERMINAL_FALL_SPEED: f32 = 40.0;

/// Ground movement speed, in tiles per second.
pub const WALK_SPEED: f32 = 8.0;

/// Upward launch speed on jump, in tiles per second. With `GRAVITY` this
/// clears a little over three tiles.
pub const JUMP_SPEED: f32 = 21.0;

/// Largest distance resolved in a single collision substep, in tiles. Smaller
/// than the body's thinnest dimension, so nothing can pass through a wall.
const MAX_SUBSTEP: f32 = 0.25;

/// Inward nudge applied to maximum edges during overlap tests, so touching a
/// tile face is not mistaken for intersecting it.
const EDGE_EPSILON: f32 = 1e-4;

/// What the controller is asking the body to do this frame.
#[derive(Clone, Copy, Debug, Default)]
pub struct Intent {
    /// -1 for left, +1 for right, 0 for still. Values between are honoured.
    pub move_dir: f32,
    pub jump: bool,
}

/// A moving axis-aligned box that collides with solid tiles.
#[derive(Clone, Copy, Debug)]
pub struct Body {
    /// Horizontal centre, in tiles.
    pub x: f32,
    /// Vertical position of the **feet** (the bottom edge), in tiles.
    pub y: f32,
    pub vx: f32,
    pub vy: f32,
    /// Whether the body is resting on solid ground, as of the last step.
    pub on_ground: bool,
}

impl Body {
    /// A body standing at `(x, y)`, where `y` is the feet position.
    pub fn new(x: f32, y: f32) -> Body {
        Body {
            x,
            y,
            vx: 0.0,
            vy: 0.0,
            on_ground: false,
        }
    }

    pub fn width(&self) -> f32 {
        PLAYER_WIDTH_TILES
    }

    pub fn height(&self) -> f32 {
        PLAYER_HEIGHT_TILES
    }

    pub fn left(&self) -> f32 {
        self.x - self.width() / 2.0
    }

    pub fn right(&self) -> f32 {
        self.x + self.width() / 2.0
    }

    /// Top edge. Smaller than `y` because `y` grows downward.
    pub fn top(&self) -> f32 {
        self.y - self.height()
    }

    pub fn bottom(&self) -> f32 {
        self.y
    }

    /// Advance the body by `dt` seconds under `intent`, colliding with `world`.
    pub fn step(&mut self, world: &World, intent: Intent, dt: f32) {
        self.vx = intent.move_dir.clamp(-1.0, 1.0) * WALK_SPEED;

        if intent.jump && self.on_ground {
            self.vy = -JUMP_SPEED;
            self.on_ground = false;
        }

        self.vy = (self.vy + GRAVITY * dt).min(TERMINAL_FALL_SPEED);

        let dx = self.vx * dt;
        let dy = self.vy * dt;

        // Split the frame so no single move exceeds MAX_SUBSTEP, which is
        // thinner than any tile. Without this, a fast fall steps straight
        // over a one-tile floor.
        let longest = dx.abs().max(dy.abs());
        let substeps = (longest / MAX_SUBSTEP).ceil().max(1.0) as usize;

        let step_x = dx / substeps as f32;
        let step_y = dy / substeps as f32;

        let mut grounded = false;
        for _ in 0..substeps {
            self.sweep_x(world, step_x);
            grounded |= self.sweep_y(world, step_y);
        }

        self.on_ground = grounded;
    }

    /// Move horizontally, snapping flush against a wall on contact.
    fn sweep_x(&mut self, world: &World, dx: f32) {
        if dx == 0.0 {
            return;
        }

        self.x += dx;

        if !self.overlaps_solid(world) {
            return;
        }

        if dx > 0.0 {
            self.x = self.right().floor() - self.width() / 2.0;
        } else {
            self.x = self.left().floor() + 1.0 + self.width() / 2.0;
        }
        self.vx = 0.0;
    }

    /// Move vertically. Returns whether this move landed the body on ground.
    fn sweep_y(&mut self, world: &World, dy: f32) -> bool {
        if dy == 0.0 {
            return false;
        }

        self.y += dy;

        if !self.overlaps_solid(world) {
            return false;
        }

        if dy > 0.0 {
            // Landing: drop the feet onto the top edge of the tile entered.
            self.y = self.bottom().floor();
            self.vy = 0.0;
            return true;
        }

        // Head hit a ceiling: push down so the top sits flush beneath it.
        self.y = self.top().floor() + 1.0 + self.height();
        self.vy = 0.0;
        false
    }

    /// Whether the body's box currently intersects any solid tile.
    ///
    /// Maximum edges are nudged inward by `EDGE_EPSILON` so that merely
    /// *touching* a tile face does not count as overlapping it — otherwise a
    /// body resting exactly on the ground would register as stuck inside it.
    fn overlaps_solid(&self, world: &World) -> bool {
        let min_x = self.left().floor() as isize;
        let max_x = (self.right() - EDGE_EPSILON).floor() as isize;
        let min_y = self.top().floor() as isize;
        let max_y = (self.bottom() - EDGE_EPSILON).floor() as isize;

        for ty in min_y..=max_y {
            for tx in min_x..=max_x {
                if tx < 0 || ty < 0 {
                    continue;
                }
                if world.tile(tx as usize, ty as usize).is_solid() {
                    return true;
                }
            }
        }

        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::Tile;

    const DT: f32 = 1.0 / 60.0;

    /// A world with open sky above `surface` and solid stone from it down.
    fn flat_world(width: usize, height: usize, surface: usize) -> World {
        let mut tiles = vec![Tile::Air; width * height];
        for x in 0..width {
            for y in surface..height {
                tiles[y * width + x] = Tile::Stone;
            }
        }
        World::from_tiles(width, height, tiles)
    }

    fn settle(body: &mut Body, world: &World, frames: usize) {
        for _ in 0..frames {
            body.step(world, Intent::default(), DT);
        }
    }

    #[test]
    fn body_accelerates_downward_under_gravity() {
        let world = flat_world(16, 32, 20);
        let mut body = Body::new(8.0, 5.0);

        body.step(&world, Intent::default(), DT);

        assert!(body.vy > 0.0, "should be falling, vy = {}", body.vy);
        assert!(body.y > 5.0, "should have moved down, y = {}", body.y);
    }

    #[test]
    fn falling_body_comes_to_rest_on_the_ground() {
        let world = flat_world(16, 32, 20);
        let mut body = Body::new(8.0, 5.0);

        settle(&mut body, &world, 300);

        assert!(
            (body.y - 20.0).abs() < 0.01,
            "feet should rest on the surface at y=20, got {}",
            body.y
        );
        assert_eq!(body.vy, 0.0, "vertical speed should be zero at rest");
        assert!(body.on_ground, "should report standing on ground");
    }

    #[test]
    fn falling_speed_is_capped_at_terminal_velocity() {
        let world = flat_world(16, 4096, 4000);
        let mut body = Body::new(8.0, 5.0);

        settle(&mut body, &world, 600);

        assert!(
            body.vy <= TERMINAL_FALL_SPEED + 1e-3,
            "fall speed {} exceeded terminal {}",
            body.vy,
            TERMINAL_FALL_SPEED
        );
    }

    #[test]
    fn body_cannot_walk_through_a_solid_wall() {
        let mut world_tiles = vec![Tile::Air; 16 * 32];
        for x in 0..16 {
            for y in 20..32 {
                world_tiles[y * 16 + x] = Tile::Stone;
            }
        }
        // A wall column at x = 10, standing on the ground.
        for y in 17..20 {
            world_tiles[y * 16 + 10] = Tile::Stone;
        }
        let world = World::from_tiles(16, 32, world_tiles);

        let mut body = Body::new(8.0, 20.0);
        for _ in 0..180 {
            body.step(&world, Intent { move_dir: 1.0, jump: false }, DT);
        }

        assert!(
            body.right() <= 10.0 + 1e-3,
            "body pushed into the wall at x=10; right edge is {}",
            body.right()
        );
    }

    #[test]
    fn body_jumps_only_when_standing_on_ground() {
        let world = flat_world(16, 32, 20);
        let mut body = Body::new(8.0, 20.0);
        settle(&mut body, &world, 5);
        assert!(body.on_ground, "precondition: body starts grounded");

        body.step(&world, Intent { move_dir: 0.0, jump: true }, DT);
        assert!(body.vy < 0.0, "jump from ground should move upward");

        // Mid-air jump requests must be ignored.
        let airborne_vy = body.vy;
        body.step(&world, Intent { move_dir: 0.0, jump: true }, DT);
        assert!(
            body.vy > airborne_vy,
            "a second jump in mid-air should not add lift; vy went {airborne_vy} -> {}",
            body.vy
        );
    }

    #[test]
    fn fast_body_does_not_tunnel_through_a_thin_floor() {
        let mut tiles = vec![Tile::Air; 16 * 256];
        // One-tile-thick floor far below the spawn point.
        for x in 0..16 {
            tiles[200 * 16 + x] = Tile::Stone;
        }
        let world = World::from_tiles(16, 256, tiles);

        let mut body = Body::new(8.0, 5.0);
        settle(&mut body, &world, 600);

        assert!(
            (body.y - 200.0).abs() < 0.01,
            "body should land on the thin floor at y=200, got {}",
            body.y
        );
    }

    #[test]
    fn body_squeezes_through_a_one_tile_gap() {
        // Solid everywhere from y=20 down, except a single-tile shaft at x=8.
        let mut tiles = vec![Tile::Air; 16 * 32];
        for x in 0..16 {
            for y in 20..30 {
                tiles[y * 16 + x] = Tile::Stone;
            }
        }
        for y in 20..30 {
            tiles[y * 16 + 8] = Tile::Air;
        }
        let world = World::from_tiles(16, 32, tiles);

        let mut body = Body::new(8.5, 19.0);
        settle(&mut body, &world, 300);

        assert!(
            body.y > 25.0,
            "body should fall down the one-tile shaft, stopped at y = {}",
            body.y
        );
    }
}
