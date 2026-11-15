//! Enemies, their chase behaviour, and the damage rules shared with the player.

use crate::item::{ItemId, COAL, COPPER_ORE, GOLD_ORE, IRON_ORE};
use crate::physics::{Body, Intent};
use crate::world::World;

/// Seconds of immunity after taking a hit, so a body resting against an
/// enemy is not drained one frame at a time.
pub const INVULNERABLE_SECONDS: f32 = 0.8;

/// Index into [`ENEMIES`].
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug, Hash)]
pub struct EnemyKindId(pub u16);

/// Static definition of one enemy type.
#[derive(Clone, Copy, Debug)]
pub struct EnemyKind {
    pub name: &'static str,
    pub max_health: f32,
    pub contact_damage: f32,
    /// Walk speed as a fraction of the player's.
    pub speed_scale: f32,
    /// Fraction of world height above which this enemy never spawns.
    pub min_depth: f32,
    /// Whether it only appears on the surface after dark.
    pub nocturnal: bool,
    pub loot: &'static [(ItemId, u32)],
}

/// The enemy table, indexed by position.
pub const ENEMIES: &[EnemyKind] = &[
    EnemyKind {
        name: "Slime",
        max_health: 20.0,
        contact_damage: 6.0,
        speed_scale: 0.35,
        min_depth: 0.0,
        nocturnal: true,
        loot: &[(COAL, 1)],
    },
    EnemyKind {
        name: "Cave Crawler",
        max_health: 35.0,
        contact_damage: 10.0,
        speed_scale: 0.55,
        min_depth: 0.35,
        nocturnal: false,
        loot: &[(COPPER_ORE, 2)],
    },
    EnemyKind {
        name: "Deep Stalker",
        max_health: 70.0,
        contact_damage: 18.0,
        speed_scale: 0.75,
        min_depth: 0.6,
        nocturnal: false,
        loot: &[(IRON_ORE, 3)],
    },
    EnemyKind {
        name: "Gloom Brute",
        max_health: 140.0,
        contact_damage: 28.0,
        speed_scale: 0.5,
        min_depth: 0.8,
        nocturnal: false,
        loot: &[(GOLD_ORE, 2), (IRON_ORE, 4)],
    },
];

pub const SLIME: EnemyKindId = EnemyKindId(0);
pub const CAVE_CRAWLER: EnemyKindId = EnemyKindId(1);
pub const DEEP_STALKER: EnemyKindId = EnemyKindId(2);
pub const GLOOM_BRUTE: EnemyKindId = EnemyKindId(3);

pub fn kind(id: EnemyKindId) -> &'static EnemyKind {
    &ENEMIES[id.0 as usize]
}

/// Health plus the immunity window that follows a hit.
#[derive(Clone, Copy, Debug)]
pub struct Combat {
    pub health: f32,
    pub max_health: f32,
    /// Seconds of immunity remaining.
    pub invulnerable_for: f32,
}

impl Combat {
    pub fn new(max_health: f32) -> Combat {
        Combat {
            health: max_health,
            max_health,
            invulnerable_for: 0.0,
        }
    }

    pub fn is_alive(&self) -> bool {
        self.health > 0.0
    }

    /// Advance the immunity timer.
    pub fn tick(&mut self, dt: f32) {
        self.invulnerable_for = (self.invulnerable_for - dt).max(0.0);
    }

    /// Apply `amount` damage. Returns whether the hit actually landed;
    /// a hit during the immunity window is ignored.
    pub fn take_damage(&mut self, amount: f32) -> bool {
        if self.invulnerable_for > 0.0 {
            return false;
        }

        self.health = (self.health - amount).max(0.0);
        self.invulnerable_for = INVULNERABLE_SECONDS;
        true
    }
}

/// A living enemy in the world.
#[derive(Clone, Copy, Debug)]
pub struct Enemy {
    pub kind: EnemyKindId,
    pub body: Body,
    pub combat: Combat,
}

impl Enemy {
    pub fn new(kind_id: EnemyKindId, x: f32, y: f32) -> Enemy {
        Enemy {
            kind: kind_id,
            body: Body::new(x, y),
            combat: Combat::new(kind(kind_id).max_health),
        }
    }

    pub fn is_alive(&self) -> bool {
        self.combat.is_alive()
    }

    /// What this enemy leaves behind when killed.
    pub fn loot(&self) -> &'static [(ItemId, u32)] {
        kind(self.kind).loot
    }
}

/// Close enough to the target that shuffling back and forth looks silly.
const CHASE_DEADZONE: f32 = 0.25;

/// How far ahead of its leading edge an enemy checks for obstacles, in tiles.
/// Looking a little further than its own body means it hops a step *before*
/// grinding into the wall, which reads as intent rather than stupidity.
const OBSTACLE_LOOKAHEAD: f32 = 0.8;

/// Walk toward `target_x`, hopping over whatever is in the way.
pub fn chase_intent(enemy: &Enemy, world: &World, target_x: f32) -> Intent {
    let delta = target_x - enemy.body.x;

    let move_dir = if delta.abs() < CHASE_DEADZONE {
        0.0
    } else {
        delta.signum()
    };

    let mut jump = false;

    if enemy.body.on_ground && move_dir != 0.0 {
        let probe_x = if move_dir > 0.0 {
            enemy.body.right() + OBSTACLE_LOOKAHEAD
        } else {
            enemy.body.left() - OBSTACLE_LOOKAHEAD
        };

        // Shin height: the row just above the one being stood on.
        let probe_y = enemy.body.bottom() - 0.5;

        if probe_x >= 0.0 && probe_y >= 0.0 {
            jump = world
                .tile(probe_x as usize, probe_y as usize)
                .is_solid();
        }
    }

    Intent { move_dir, jump }
}

/// Whether two bodies' boxes intersect, for contact damage.
pub fn bodies_overlap(a: &Body, b: &Body) -> bool {
    a.right() > b.left()
        && a.left() < b.right()
        && a.bottom() > b.top()
        && a.top() < b.bottom()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::Tile;

    const DT: f32 = 1.0 / 60.0;

    fn flat_world() -> World {
        let (width, height, surface) = (40, 40, 20);
        let mut tiles = vec![Tile::Air; width * height];
        for x in 0..width {
            for y in surface..height {
                tiles[y * width + x] = Tile::Stone;
            }
        }
        World::from_tiles(width, height, tiles)
    }

    #[test]
    fn deeper_enemies_are_more_dangerous_than_surface_ones() {
        let slime = kind(SLIME);
        let brute = kind(GLOOM_BRUTE);

        assert!(brute.max_health > slime.max_health);
        assert!(brute.contact_damage > slime.contact_damage);
        assert!(brute.min_depth > slime.min_depth);
    }

    #[test]
    fn only_the_slime_is_nocturnal() {
        assert!(kind(SLIME).nocturnal);
        assert!(!kind(CAVE_CRAWLER).nocturnal);
        assert!(!kind(DEEP_STALKER).nocturnal);
    }

    #[test]
    fn a_new_enemy_starts_at_full_health_and_alive() {
        let enemy = Enemy::new(CAVE_CRAWLER, 5.0, 20.0);

        assert!(enemy.is_alive());
        assert_eq!(enemy.combat.health, kind(CAVE_CRAWLER).max_health);
    }

    #[test]
    fn damage_reduces_health() {
        let mut combat = Combat::new(50.0);

        let landed = combat.take_damage(20.0);

        assert!(landed);
        assert_eq!(combat.health, 30.0);
        assert!(combat.is_alive());
    }

    #[test]
    fn health_reaching_zero_is_death() {
        let mut combat = Combat::new(20.0);

        combat.take_damage(20.0);

        assert!(!combat.is_alive(), "zero health should be dead");
    }

    #[test]
    fn health_never_falls_below_zero() {
        let mut combat = Combat::new(20.0);

        combat.take_damage(500.0);

        assert_eq!(combat.health, 0.0, "overkill should clamp, not go negative");
    }

    #[test]
    fn a_second_hit_during_immunity_is_ignored() {
        let mut combat = Combat::new(50.0);
        combat.take_damage(10.0);

        let landed = combat.take_damage(10.0);

        assert!(!landed, "immunity should swallow the second hit");
        assert_eq!(combat.health, 40.0, "health must not drop twice");
    }

    #[test]
    fn immunity_wears_off_and_the_next_hit_lands() {
        let mut combat = Combat::new(50.0);
        combat.take_damage(10.0);

        for _ in 0..((INVULNERABLE_SECONDS / DT) as usize + 2) {
            combat.tick(DT);
        }

        let landed = combat.take_damage(10.0);

        assert!(landed, "immunity should have expired");
        assert_eq!(combat.health, 30.0);
    }

    #[test]
    fn an_enemy_walks_toward_a_player_on_its_right() {
        let world = flat_world();
        let enemy = Enemy::new(CAVE_CRAWLER, 10.0, 20.0);

        let intent = chase_intent(&enemy, &world, 20.0);

        assert!(intent.move_dir > 0.0, "should head right, got {}", intent.move_dir);
    }

    #[test]
    fn an_enemy_walks_toward_a_player_on_its_left() {
        let world = flat_world();
        let enemy = Enemy::new(CAVE_CRAWLER, 10.0, 20.0);

        let intent = chase_intent(&enemy, &world, 2.0);

        assert!(intent.move_dir < 0.0, "should head left, got {}", intent.move_dir);
    }

    #[test]
    fn an_enemy_standing_on_its_target_stops_shuffling() {
        let world = flat_world();
        let enemy = Enemy::new(CAVE_CRAWLER, 10.0, 20.0);

        let intent = chase_intent(&enemy, &world, 10.0);

        assert_eq!(intent.move_dir, 0.0, "already there, should hold still");
    }

    #[test]
    fn an_enemy_jumps_when_a_wall_blocks_the_chase() {
        let mut tiles = vec![Tile::Air; 40 * 40];
        for x in 0..40 {
            for y in 20..40 {
                tiles[y * 40 + x] = Tile::Stone;
            }
        }
        // A wall just to the enemy's right.
        for y in 18..20 {
            tiles[y * 40 + 12] = Tile::Stone;
        }
        let world = World::from_tiles(40, 40, tiles);

        let mut enemy = Enemy::new(CAVE_CRAWLER, 11.0, 20.0);
        // Let it settle so it is grounded.
        for _ in 0..10 {
            enemy.body.step(&world, Intent::default(), DT);
        }

        let intent = chase_intent(&enemy, &world, 30.0);

        assert!(intent.jump, "should hop the wall rather than grind into it");
    }

    #[test]
    fn an_airborne_enemy_does_not_try_to_jump_again() {
        let world = flat_world();
        // Spawned high up, so it is falling, not grounded.
        let enemy = Enemy::new(CAVE_CRAWLER, 10.0, 5.0);

        let intent = chase_intent(&enemy, &world, 30.0);

        assert!(!intent.jump, "cannot jump in mid-air");
    }

    #[test]
    fn enemies_fall_and_land_like_the_player() {
        let world = flat_world();
        let mut enemy = Enemy::new(CAVE_CRAWLER, 10.0, 5.0);

        for _ in 0..300 {
            enemy.body.step(&world, Intent::default(), DT);
        }

        assert!((enemy.body.y - 20.0).abs() < 0.01, "should rest on the ground");
        assert!(enemy.body.on_ground);
    }

    #[test]
    fn touching_bodies_overlap() {
        let a = Body::new(10.0, 20.0);
        let b = Body::new(10.2, 20.0);

        assert!(bodies_overlap(&a, &b));
    }

    #[test]
    fn bodies_standing_apart_do_not_overlap() {
        let a = Body::new(10.0, 20.0);
        let b = Body::new(14.0, 20.0);

        assert!(!bodies_overlap(&a, &b));
    }

    #[test]
    fn bodies_at_the_same_spot_but_different_heights_do_not_overlap() {
        let a = Body::new(10.0, 20.0);
        let b = Body::new(10.0, 30.0);

        assert!(!bodies_overlap(&a, &b), "one is well below the other");
    }

    #[test]
    fn a_killed_enemy_leaves_loot() {
        let enemy = Enemy::new(GLOOM_BRUTE, 5.0, 20.0);

        let loot = enemy.loot();

        assert!(!loot.is_empty(), "a brute should be worth killing");
        assert!(loot.iter().any(|&(item, _)| item == GOLD_ORE));
    }
}
