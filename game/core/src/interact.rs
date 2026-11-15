//! Breaking and placing tiles: the core interaction loop.

use crate::physics::Body;
use crate::world::{Tile, World};

/// How far the player can reach to mine or place, in tiles, measured from
/// body centre to tile centre. Generous enough to feel good with a thumb.
pub const REACH_TILES: f32 = 5.5;

/// Progress toward breaking one tile. Progress is per-target: aiming
/// somewhere else abandons the half-dug tile.
#[derive(Clone, Debug, Default)]
pub struct MiningState {
    target: Option<(usize, usize)>,
    progress: f32,
}

impl MiningState {
    pub fn new() -> MiningState {
        MiningState {
            target: None,
            progress: 0.0,
        }
    }

    /// Accumulated work on the current target, in hardness units.
    pub fn progress(&self) -> f32 {
        self.progress
    }

    pub fn target(&self) -> Option<(usize, usize)> {
        self.target
    }

    /// Abandon the current dig.
    pub fn cancel(&mut self) {
        self.target = None;
        self.progress = 0.0;
    }

    /// Apply `dt` seconds of digging at `tile_pos` with a tool of
    /// `tool_power`. Returns the tile that broke, if this finished it.
    pub fn mine(
        &mut self,
        world: &mut World,
        body: &Body,
        tile_pos: (usize, usize),
        tool_power: f32,
        dt: f32,
    ) -> Option<Tile> {
        if !can_reach(body, tile_pos) {
            self.cancel();
            return None;
        }

        let tile = world.tile(tile_pos.0, tile_pos.1);
        let Some(hardness) = tile.hardness() else {
            // Nothing there to dig.
            self.cancel();
            return None;
        };

        if self.target != Some(tile_pos) {
            self.target = Some(tile_pos);
            self.progress = 0.0;
        }

        self.progress += tool_power * dt;

        if self.progress >= hardness {
            world.set_tile(tile_pos.0, tile_pos.1, Tile::Air);
            self.cancel();
            return Some(tile);
        }

        None
    }
}

/// Whether `tile_pos` is within arm's reach of `body`, measured centre to centre.
pub fn can_reach(body: &Body, tile_pos: (usize, usize)) -> bool {
    let body_centre_y = body.y - body.height() / 2.0;

    let dx = (tile_pos.0 as f32 + 0.5) - body.x;
    let dy = (tile_pos.1 as f32 + 0.5) - body_centre_y;

    dx * dx + dy * dy <= REACH_TILES * REACH_TILES
}

/// Put `tile` at `tile_pos`. Fails if out of reach, out of bounds, already
/// occupied, or if it would entomb the player.
pub fn place(world: &mut World, body: &Body, tile_pos: (usize, usize), tile: Tile) -> bool {
    // Placing air is mining, and goes through MiningState instead.
    if !tile.is_solid() {
        return false;
    }

    if tile_pos.0 >= world.width() || tile_pos.1 >= world.height() {
        return false;
    }

    if !can_reach(body, tile_pos) {
        return false;
    }

    if world.tile(tile_pos.0, tile_pos.1).is_solid() {
        return false;
    }

    if overlaps_body(body, tile_pos) {
        return false;
    }

    world.set_tile(tile_pos.0, tile_pos.1, tile);
    true
}

/// Whether the unit square at `tile_pos` intersects the body's box.
fn overlaps_body(body: &Body, tile_pos: (usize, usize)) -> bool {
    let left = tile_pos.0 as f32;
    let top = tile_pos.1 as f32;

    body.right() > left
        && body.left() < left + 1.0
        && body.bottom() > top
        && body.top() < top + 1.0
}

#[cfg(test)]
mod tests {
    use super::*;

    const DT: f32 = 1.0 / 60.0;

    fn world_of_stone() -> World {
        World::from_tiles(32, 32, vec![Tile::Stone; 32 * 32])
    }

    fn open_world() -> World {
        World::from_tiles(32, 32, vec![Tile::Air; 32 * 32])
    }

    /// A body standing near the middle, so most nearby tiles are in reach.
    fn nearby_body() -> Body {
        Body::new(16.0, 16.0)
    }

    fn dig_until_broken(
        state: &mut MiningState,
        world: &mut World,
        body: &Body,
        pos: (usize, usize),
        power: f32,
        max_frames: usize,
    ) -> Option<Tile> {
        for _ in 0..max_frames {
            if let Some(tile) = state.mine(world, body, pos, power, DT) {
                return Some(tile);
            }
        }
        None
    }

    #[test]
    fn air_has_no_hardness_and_cannot_be_mined() {
        assert_eq!(Tile::Air.hardness(), None);
    }

    #[test]
    fn precious_ore_is_harder_than_plain_rock_which_is_harder_than_soil() {
        let dirt = Tile::Dirt.hardness().expect("dirt is breakable");
        let stone = Tile::Stone.hardness().expect("stone is breakable");
        let iron = Tile::IronOre.hardness().expect("iron is breakable");
        let gold = Tile::GoldOre.hardness().expect("gold is breakable");

        assert!(dirt < stone, "dirt {dirt} should yield faster than stone {stone}");
        assert!(stone < iron, "stone {stone} should yield faster than iron {iron}");
        assert!(iron < gold, "iron {iron} should yield faster than gold {gold}");
    }

    #[test]
    fn mining_accumulates_progress_without_breaking_instantly() {
        let mut world = world_of_stone();
        let body = nearby_body();
        let mut state = MiningState::new();

        let broken = state.mine(&mut world, &body, (17, 16), 1.0, DT);

        assert!(broken.is_none(), "one frame should not break stone");
        assert!(state.progress() > 0.0, "progress should have accumulated");
        assert_eq!(state.target(), Some((17, 16)));
    }

    #[test]
    fn mining_long_enough_breaks_the_tile_and_yields_what_it_was() {
        let mut world = world_of_stone();
        let body = nearby_body();
        let mut state = MiningState::new();

        let broken = dig_until_broken(&mut state, &mut world, &body, (17, 16), 1.0, 600);

        assert_eq!(broken, Some(Tile::Stone), "should yield the stone it broke");
    }

    #[test]
    fn a_broken_tile_leaves_open_air_behind() {
        let mut world = world_of_stone();
        let body = nearby_body();
        let mut state = MiningState::new();

        dig_until_broken(&mut state, &mut world, &body, (17, 16), 1.0, 600)
            .expect("tile should break");

        assert_eq!(world.tile(17, 16), Tile::Air);
    }

    #[test]
    fn aiming_at_a_new_tile_abandons_the_previous_dig() {
        let mut world = world_of_stone();
        let body = nearby_body();
        let mut state = MiningState::new();

        for _ in 0..10 {
            state.mine(&mut world, &body, (17, 16), 1.0, DT);
        }
        let banked = state.progress();
        assert!(banked > 0.0, "precondition: progress was banked");

        state.mine(&mut world, &body, (18, 16), 1.0, DT);

        assert!(
            state.progress() < banked,
            "switching target should reset progress, was {banked}, now {}",
            state.progress()
        );
        assert_eq!(state.target(), Some((18, 16)));
    }

    #[test]
    fn mining_empty_air_achieves_nothing() {
        let mut world = open_world();
        let body = nearby_body();
        let mut state = MiningState::new();

        let broken = dig_until_broken(&mut state, &mut world, &body, (17, 16), 1.0, 600);

        assert_eq!(broken, None, "air cannot be mined");
        assert_eq!(state.progress(), 0.0);
    }

    #[test]
    fn a_stronger_tool_breaks_rock_in_fewer_swings() {
        let body = nearby_body();

        let count_frames = |power: f32| {
            let mut world = world_of_stone();
            let mut state = MiningState::new();
            for frame in 1..=600 {
                if state.mine(&mut world, &body, (17, 16), power, DT).is_some() {
                    return frame;
                }
            }
            panic!("tool of power {power} never broke the stone");
        };

        let weak = count_frames(1.0);
        let strong = count_frames(4.0);

        assert!(
            strong < weak,
            "stronger tool should be quicker: {strong} frames vs {weak}"
        );
    }

    #[test]
    fn tiles_out_of_reach_cannot_be_mined() {
        let mut world = world_of_stone();
        let body = nearby_body();
        let mut state = MiningState::new();

        let far = (16 + REACH_TILES.ceil() as usize + 3, 16);
        let broken = dig_until_broken(&mut state, &mut world, &body, far, 1.0, 600);

        assert_eq!(broken, None, "should not reach a tile {far:?} away");
        assert_eq!(world.tile(far.0, far.1), Tile::Stone, "tile must be untouched");
    }

    #[test]
    fn reach_covers_nearby_tiles_but_not_distant_ones() {
        let body = nearby_body();

        assert!(can_reach(&body, (17, 16)), "adjacent tile should be in reach");
        assert!(
            !can_reach(&body, (16 + REACH_TILES.ceil() as usize + 3, 16)),
            "distant tile should be out of reach"
        );
    }

    #[test]
    fn placing_into_empty_space_succeeds() {
        let mut world = open_world();
        let body = nearby_body();

        let placed = place(&mut world, &body, (19, 16), Tile::Dirt);

        assert!(placed, "placing into air should succeed");
        assert_eq!(world.tile(19, 16), Tile::Dirt);
    }

    #[test]
    fn placing_into_an_occupied_tile_fails() {
        let mut world = world_of_stone();
        let body = nearby_body();

        let placed = place(&mut world, &body, (19, 16), Tile::Dirt);

        assert!(!placed, "cannot place into solid rock");
        assert_eq!(world.tile(19, 16), Tile::Stone, "existing tile must survive");
    }

    #[test]
    fn placing_out_of_reach_fails() {
        let mut world = open_world();
        let body = nearby_body();

        let far = (16 + REACH_TILES.ceil() as usize + 3, 16);
        let placed = place(&mut world, &body, far, Tile::Dirt);

        assert!(!placed, "cannot place a tile out of reach");
        assert_eq!(world.tile(far.0, far.1), Tile::Air);
    }

    #[test]
    fn placing_a_tile_inside_the_player_fails() {
        let mut world = open_world();
        let body = nearby_body();

        // The body's feet are at y = 16, so it occupies the tile above.
        let placed = place(&mut world, &body, (16, 15), Tile::Dirt);

        assert!(!placed, "must not entomb the player");
        assert_eq!(world.tile(16, 15), Tile::Air);
    }
}
