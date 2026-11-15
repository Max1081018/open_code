//! Which enemies may appear, given depth and time of day.
//!
//! Placement (finding a patch of floor with headroom) stays in the frontend,
//! but the *rules* live here so they can be tested.

use crate::enemy::{EnemyKindId, ENEMIES};
use crate::world::World;

/// Tiles of headroom a standing enemy needs, matching the body height.
const REQUIRED_HEADROOM: usize = 2;

/// Find somewhere in `column` between rows `top` and `bottom` where an enemy
/// can stand: solid footing with [`REQUIRED_HEADROOM`] clear above it.
///
/// `roll` in `[0, 1)` picks among the spots found, so spawns do not always
/// land on the topmost ledge.
pub fn find_standing_spot(
    world: &World,
    column: usize,
    top: usize,
    bottom: usize,
    roll: f32,
) -> Option<usize> {
    if column >= world.width() {
        return None;
    }

    // Leave a row below in range, since the floor check looks at row + 1.
    let lowest = bottom.min(world.height().saturating_sub(2));

    let spots: Vec<usize> = (top..=lowest)
        .filter(|&row| {
            // The enemy's feet rest in `row`; it needs clear air for its
            // whole height, counting upward from there.
            let headroom = (0..REQUIRED_HEADROOM).all(|offset| {
                row.checked_sub(offset)
                    .is_some_and(|y| !world.tile(column, y).is_solid())
            });

            headroom && world.tile(column, row + 1).is_solid()
        })
        .collect();

    if spots.is_empty() {
        return None;
    }

    let index = ((roll.clamp(0.0, 1.0) * spots.len() as f32) as usize).min(spots.len() - 1);
    Some(spots[index])
}

/// Every enemy type allowed at this depth and time.
///
/// `depth` is a fraction of world height: 0.0 is the sky, 1.0 the bedrock.
pub fn eligible_kinds(depth: f32, is_night: bool) -> Vec<EnemyKindId> {
    ENEMIES
        .iter()
        .enumerate()
        .filter(|(_, enemy)| depth >= enemy.min_depth && (!enemy.nocturnal || is_night))
        .map(|(index, _)| EnemyKindId(index as u16))
        .collect()
}

/// Pick one eligible enemy using `roll`, a value in `[0, 1)`.
pub fn choose_kind(depth: f32, is_night: bool, roll: f32) -> Option<EnemyKindId> {
    let eligible = eligible_kinds(depth, is_night);

    if eligible.is_empty() {
        return None;
    }

    // Clamped, so a roll that rounds up to the length cannot index past the end.
    let index = ((roll.clamp(0.0, 1.0) * eligible.len() as f32) as usize).min(eligible.len() - 1);

    Some(eligible[index])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::enemy::{kind, CAVE_CRAWLER, GLOOM_BRUTE, SLIME};
    use crate::world::Tile;

    const WIDTH: usize = 16;
    const HEIGHT: usize = 64;

    /// Air above `surface`, solid from it down.
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
    fn a_spot_is_found_on_open_ground() {
        let world = flat_world(30);

        let spot = find_standing_spot(&world, 5, 10, 50, 0.0);

        assert_eq!(
            spot,
            Some(29),
            "an enemy stands in the air tile directly above the ground"
        );
    }

    #[test]
    fn solid_rock_offers_nowhere_to_stand() {
        let world = World::from_tiles(WIDTH, HEIGHT, vec![Tile::Stone; WIDTH * HEIGHT]);

        assert_eq!(find_standing_spot(&world, 5, 2, 60, 0.5), None);
    }

    #[test]
    fn open_sky_offers_nowhere_to_stand() {
        let world = World::from_tiles(WIDTH, HEIGHT, vec![Tile::Air; WIDTH * HEIGHT]);

        assert_eq!(
            find_standing_spot(&world, 5, 2, 60, 0.5),
            None,
            "nothing to stand on"
        );
    }

    #[test]
    fn a_single_tile_gap_is_too_cramped_to_stand_in() {
        // Solid everywhere except one lone air tile at (5, 30).
        let mut tiles = vec![Tile::Stone; WIDTH * HEIGHT];
        tiles[30 * WIDTH + 5] = Tile::Air;
        let world = World::from_tiles(WIDTH, HEIGHT, tiles);

        assert_eq!(
            find_standing_spot(&world, 5, 2, 60, 0.0),
            None,
            "a two-tile-tall enemy cannot fit in a one-tile gap"
        );
    }

    #[test]
    fn a_two_tile_gap_is_enough_to_stand_in() {
        let mut tiles = vec![Tile::Stone; WIDTH * HEIGHT];
        tiles[30 * WIDTH + 5] = Tile::Air;
        tiles[29 * WIDTH + 5] = Tile::Air;
        let world = World::from_tiles(WIDTH, HEIGHT, tiles);

        assert_eq!(find_standing_spot(&world, 5, 2, 60, 0.0), Some(30));
    }

    #[test]
    fn the_search_stays_inside_the_requested_range() {
        let world = flat_world(30);

        // The ground at 29 is outside this window, so nothing should be found.
        assert_eq!(find_standing_spot(&world, 5, 2, 20, 0.5), None);
    }

    #[test]
    fn a_roll_at_the_top_of_the_range_still_returns_a_spot() {
        let world = flat_world(30);

        assert!(find_standing_spot(&world, 5, 10, 50, 0.999_999).is_some());
    }


    const SURFACE: f32 = 0.1;
    const CAVES: f32 = 0.45;
    const DEEP: f32 = 0.95;

    #[test]
    fn the_surface_is_safe_in_daylight() {
        let eligible = eligible_kinds(SURFACE, false);

        assert!(
            eligible.is_empty(),
            "nothing should hunt the surface by day, got {eligible:?}"
        );
    }

    #[test]
    fn slimes_come_out_on_the_surface_after_dark() {
        let eligible = eligible_kinds(SURFACE, true);

        assert_eq!(eligible, vec![SLIME]);
    }

    #[test]
    fn caves_are_dangerous_regardless_of_the_hour() {
        let by_day = eligible_kinds(CAVES, false);

        assert!(
            by_day.contains(&CAVE_CRAWLER),
            "crawlers do not care about the sun, got {by_day:?}"
        );
    }

    #[test]
    fn brutes_are_confined_to_the_deepest_rock() {
        assert!(!eligible_kinds(CAVES, true).contains(&GLOOM_BRUTE));
        assert!(eligible_kinds(DEEP, true).contains(&GLOOM_BRUTE));
    }

    #[test]
    fn deeper_ground_offers_more_kinds_than_shallow() {
        let shallow = eligible_kinds(CAVES, true).len();
        let deep = eligible_kinds(DEEP, true).len();

        assert!(deep > shallow, "deep {deep} should exceed shallow {shallow}");
    }

    #[test]
    fn every_eligible_kind_actually_permits_this_depth() {
        for depth_step in 0..20 {
            let depth = depth_step as f32 / 20.0;

            for night in [false, true] {
                for id in eligible_kinds(depth, night) {
                    let enemy = kind(id);

                    assert!(
                        depth >= enemy.min_depth,
                        "{} spawned at {depth}, above its floor of {}",
                        enemy.name,
                        enemy.min_depth
                    );
                    assert!(
                        !enemy.nocturnal || night,
                        "{} is nocturnal but spawned by day",
                        enemy.name
                    );
                }
            }
        }
    }

    #[test]
    fn choosing_from_nothing_yields_nothing() {
        assert_eq!(choose_kind(SURFACE, false, 0.5), None);
    }

    #[test]
    fn a_choice_is_always_one_of_the_eligible_kinds() {
        for roll_step in 0..50 {
            let roll = roll_step as f32 / 50.0;
            let eligible = eligible_kinds(DEEP, true);

            let chosen = choose_kind(DEEP, true, roll).expect("deep rock is populated");

            assert!(
                eligible.contains(&chosen),
                "roll {roll} chose {chosen:?}, not among {eligible:?}"
            );
        }
    }

    #[test]
    fn a_roll_at_the_very_top_of_the_range_still_picks_something() {
        // Guards the classic off-by-one where roll * len indexes past the end.
        let chosen = choose_kind(DEEP, true, 0.999_999);

        assert!(chosen.is_some(), "a roll just under 1.0 must still choose");
    }

    #[test]
    fn choices_spread_across_the_available_kinds() {
        let seen: std::collections::BTreeSet<EnemyKindId> = (0..50)
            .filter_map(|step| choose_kind(DEEP, true, step as f32 / 50.0))
            .collect();

        assert!(
            seen.len() >= 3,
            "rolls across the range should reach several kinds, got {seen:?}"
        );
    }
}
