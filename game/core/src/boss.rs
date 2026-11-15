//! Bosses: summoned set-piece fights that change behaviour as they weaken.

use crate::enemy::{
    blocked_ahead, heading_toward, Combat, EnemyKindId, CAVE_CRAWLER, DEEP_STALKER, GLOOM_BRUTE,
    SLIME,
};
use crate::item::{
    ItemId, COLOSSUS_TROPHY, CRACKED_IDOL, FROZEN_HEART, GOLD_BAR, HOLLOW_KING_TROPHY, IRON_BAR,
    RIMEWYRM_TROPHY, SUNSTONE, VOID_SHARD, WARDEN_TROPHY,
};
use crate::physics::{Body, Intent};
use crate::world::World;

/// What a boss does during one phase of a fight.
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Attack {
    /// Walks the player down.
    Stalk,
    /// Rushes, covering ground much faster.
    Charge,
    /// Calls in lesser monsters.
    Summon { minion: EnemyKindId, count: u32 },
}

/// One stage of a fight, entered as the boss's health falls.
#[derive(Clone, Copy, Debug)]
pub struct Phase {
    /// Active while the boss's health fraction is at or above this.
    /// The first phase must start at 1.0 so full health is covered.
    pub from_health: f32,
    pub attack: Attack,
    pub contact_damage: f32,
    /// Movement speed as a fraction of the player's.
    pub speed_scale: f32,
}

/// Static definition of one boss.
#[derive(Clone, Copy, Debug)]
pub struct BossKind {
    pub name: &'static str,
    pub max_health: f32,
    /// Ordered from full health downward.
    pub phases: &'static [Phase],
    /// Item consumed to call this boss.
    pub summoned_by: ItemId,
    pub loot: &'static [(ItemId, u32)],
}

/// Index into [`BOSSES`].
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug, Hash)]
pub struct BossKindId(pub u16);

pub const BOSSES: &[BossKind] = &[
    BossKind {
        name: "The Warden",
        max_health: 600.0,
        phases: &[
            Phase {
                from_health: 1.0,
                attack: Attack::Stalk,
                contact_damage: 18.0,
                speed_scale: 0.55,
            },
            Phase {
                from_health: 0.55,
                attack: Attack::Summon {
                    minion: SLIME,
                    count: 3,
                },
                contact_damage: 24.0,
                speed_scale: 0.7,
            },
            Phase {
                from_health: 0.25,
                attack: Attack::Charge,
                contact_damage: 32.0,
                speed_scale: 1.25,
            },
        ],
        summoned_by: CRACKED_IDOL,
        loot: &[(WARDEN_TROPHY, 1), (IRON_BAR, 12)],
    },
    BossKind {
        name: "Rimewyrm",
        max_health: 900.0,
        phases: &[
            Phase {
                from_health: 1.0,
                attack: Attack::Charge,
                contact_damage: 22.0,
                speed_scale: 0.9,
            },
            Phase {
                from_health: 0.5,
                attack: Attack::Summon {
                    minion: CAVE_CRAWLER,
                    count: 4,
                },
                contact_damage: 30.0,
                speed_scale: 1.1,
            },
        ],
        summoned_by: FROZEN_HEART,
        loot: &[(RIMEWYRM_TROPHY, 1), (IRON_BAR, 18)],
    },
    BossKind {
        name: "Sand Colossus",
        max_health: 1400.0,
        phases: &[
            Phase {
                from_health: 1.0,
                attack: Attack::Stalk,
                contact_damage: 28.0,
                speed_scale: 0.45,
            },
            Phase {
                from_health: 0.6,
                attack: Attack::Charge,
                contact_damage: 36.0,
                speed_scale: 1.0,
            },
            Phase {
                from_health: 0.3,
                attack: Attack::Summon {
                    minion: DEEP_STALKER,
                    count: 3,
                },
                contact_damage: 44.0,
                speed_scale: 1.15,
            },
        ],
        summoned_by: SUNSTONE,
        loot: &[(COLOSSUS_TROPHY, 1), (GOLD_BAR, 10)],
    },
    BossKind {
        name: "Hollow King",
        max_health: 2200.0,
        phases: &[
            Phase {
                from_health: 1.0,
                attack: Attack::Stalk,
                contact_damage: 34.0,
                speed_scale: 0.6,
            },
            Phase {
                from_health: 0.7,
                attack: Attack::Summon {
                    minion: GLOOM_BRUTE,
                    count: 2,
                },
                contact_damage: 42.0,
                speed_scale: 0.85,
            },
            Phase {
                from_health: 0.4,
                attack: Attack::Charge,
                contact_damage: 50.0,
                speed_scale: 1.3,
            },
            Phase {
                from_health: 0.15,
                attack: Attack::Summon {
                    minion: GLOOM_BRUTE,
                    count: 4,
                },
                contact_damage: 60.0,
                speed_scale: 1.4,
            },
        ],
        summoned_by: VOID_SHARD,
        loot: &[(HOLLOW_KING_TROPHY, 1), (GOLD_BAR, 25)],
    },
];

pub const WARDEN: BossKindId = BossKindId(0);
pub const RIMEWYRM: BossKindId = BossKindId(1);
pub const SAND_COLOSSUS: BossKindId = BossKindId(2);
pub const HOLLOW_KING: BossKindId = BossKindId(3);

pub fn kind(id: BossKindId) -> &'static BossKind {
    &BOSSES[id.0 as usize]
}

/// Which boss, if any, this item summons.
pub fn summoned_by(item: ItemId) -> Option<BossKindId> {
    BOSSES
        .iter()
        .position(|boss| boss.summoned_by == item)
        .map(|index| BossKindId(index as u16))
}

/// A boss in the world.
#[derive(Clone, Copy, Debug)]
pub struct Boss {
    pub kind: BossKindId,
    pub body: Body,
    pub combat: Combat,
}

impl Boss {
    pub fn new(kind_id: BossKindId, x: f32, y: f32) -> Boss {
        Boss {
            kind: kind_id,
            body: Body::new(x, y),
            combat: Combat::new(kind(kind_id).max_health),
        }
    }

    pub fn is_alive(&self) -> bool {
        self.combat.is_alive()
    }

    /// Health remaining, as a fraction of the boss's maximum.
    pub fn health_fraction(&self) -> f32 {
        if self.combat.max_health <= 0.0 {
            return 0.0;
        }
        (self.combat.health / self.combat.max_health).clamp(0.0, 1.0)
    }

    /// Index of the phase the fight is currently in.
    ///
    /// Phases are listed from full health downward, so the current one is the
    /// last whose threshold the boss has fallen to.
    pub fn phase_index(&self) -> usize {
        let health = self.health_fraction();

        kind(self.kind)
            .phases
            .iter()
            .enumerate()
            .filter(|(_, phase)| health <= phase.from_health)
            .map(|(index, _)| index)
            .next_back()
            .unwrap_or(0)
    }

    /// The phase the fight is currently in.
    pub fn phase(&self) -> &'static Phase {
        &kind(self.kind).phases[self.phase_index()]
    }

    pub fn loot(&self) -> &'static [(ItemId, u32)] {
        kind(self.kind).loot
    }
}

/// How the boss moves this frame.
///
/// Pace comes from the current phase, so a boss that has dropped into a
/// charge visibly accelerates.
pub fn boss_intent(boss: &Boss, world: &World, target_x: f32) -> Intent {
    let direction = heading_toward(boss.body.x, target_x);
    let phase = boss.phase();

    Intent {
        move_dir: direction * phase.speed_scale,
        jump: boss.body.on_ground && blocked_ahead(&boss.body, world, direction),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::enemy::ENEMIES;
    use crate::world::Tile;

    const DT: f32 = 1.0 / 60.0;

    fn flat_world() -> World {
        let (width, height, surface) = (60, 40, 20);
        let mut tiles = vec![Tile::Air; width * height];
        for x in 0..width {
            for y in surface..height {
                tiles[y * width + x] = Tile::Stone;
            }
        }
        World::from_tiles(width, height, tiles)
    }

    /// Damage a boss down to the given fraction of its health.
    fn wound_to(boss: &mut Boss, fraction: f32) {
        let target = boss.combat.max_health * fraction;
        boss.combat.health = target;
    }

    #[test]
    fn every_boss_opens_at_full_health() {
        for index in 0..BOSSES.len() {
            let boss = Boss::new(BossKindId(index as u16), 10.0, 20.0);

            assert_eq!(boss.health_fraction(), 1.0);
            assert_eq!(
                boss.phase_index(),
                0,
                "{} should start in its first phase",
                kind(boss.kind).name
            );
        }
    }

    #[test]
    fn every_bosss_first_phase_covers_full_health() {
        for boss in BOSSES {
            assert_eq!(
                boss.phases[0].from_health, 1.0,
                "{} has no phase for full health",
                boss.name
            );
        }
    }

    #[test]
    fn phases_are_listed_from_full_health_downward() {
        for boss in BOSSES {
            for pair in boss.phases.windows(2) {
                assert!(
                    pair[0].from_health > pair[1].from_health,
                    "{} has phases out of order: {} then {}",
                    boss.name,
                    pair[0].from_health,
                    pair[1].from_health
                );
            }
        }
    }

    #[test]
    fn a_wounded_boss_moves_into_a_later_phase() {
        let mut boss = Boss::new(WARDEN, 10.0, 20.0);
        assert_eq!(boss.phase_index(), 0);

        wound_to(&mut boss, 0.4);

        assert_eq!(boss.phase_index(), 1, "40% health is the Warden's second phase");
    }

    #[test]
    fn a_nearly_dead_boss_is_in_its_final_phase() {
        let mut boss = Boss::new(HOLLOW_KING, 10.0, 20.0);

        wound_to(&mut boss, 0.05);

        assert_eq!(
            boss.phase_index(),
            kind(HOLLOW_KING).phases.len() - 1,
            "the last sliver of health should be the final phase"
        );
    }

    #[test]
    fn phases_only_ever_advance_as_health_falls() {
        let mut boss = Boss::new(HOLLOW_KING, 10.0, 20.0);
        let mut highest = 0;

        for step in (0..=100).rev() {
            wound_to(&mut boss, step as f32 / 100.0);
            let phase = boss.phase_index();

            assert!(
                phase >= highest,
                "phase went backwards from {highest} to {phase} at {step}% health"
            );
            highest = phase;
        }

        assert!(highest > 0, "the fight should have progressed at all");
    }

    #[test]
    fn later_phases_hit_harder() {
        for boss in BOSSES {
            for pair in boss.phases.windows(2) {
                assert!(
                    pair[1].contact_damage > pair[0].contact_damage,
                    "{} gets gentler as it weakens",
                    boss.name
                );
            }
        }
    }

    #[test]
    fn every_boss_outguns_every_ordinary_enemy() {
        let toughest = ENEMIES
            .iter()
            .map(|enemy| enemy.max_health)
            .fold(0.0f32, f32::max);

        for boss in BOSSES {
            assert!(
                boss.max_health > toughest * 3.0,
                "{} is not much of a boss at {} health",
                boss.name,
                boss.max_health
            );
        }
    }

    #[test]
    fn bosses_get_harder_down_the_list() {
        for pair in BOSSES.windows(2) {
            assert!(
                pair[1].max_health > pair[0].max_health,
                "{} should be tougher than {}",
                pair[1].name,
                pair[0].name
            );
        }
    }

    #[test]
    fn each_boss_answers_to_its_own_token() {
        for index in 0..BOSSES.len() {
            let id = BossKindId(index as u16);

            assert_eq!(
                summoned_by(kind(id).summoned_by),
                Some(id),
                "{} is not reachable from its token",
                kind(id).name
            );
        }
    }

    #[test]
    fn an_ordinary_item_summons_nothing() {
        assert_eq!(summoned_by(crate::item::STONE), None);
    }

    #[test]
    fn every_boss_drops_a_unique_trophy() {
        let trophies: std::collections::BTreeSet<ItemId> = BOSSES
            .iter()
            .filter_map(|boss| boss.loot.first().map(|&(item, _)| item))
            .collect();

        assert_eq!(
            trophies.len(),
            BOSSES.len(),
            "trophies should be one per boss, got {trophies:?}"
        );
    }

    #[test]
    fn a_boss_walks_toward_the_player() {
        let world = flat_world();
        let boss = Boss::new(WARDEN, 10.0, 20.0);

        let intent = boss_intent(&boss, &world, 40.0);

        assert!(intent.move_dir > 0.0, "should close the distance");
    }

    #[test]
    fn a_charging_boss_moves_faster_than_a_stalking_one() {
        let world = flat_world();

        let mut stalking = Boss::new(WARDEN, 10.0, 20.0);
        let mut charging = Boss::new(WARDEN, 10.0, 20.0);
        wound_to(&mut charging, 0.1);

        // Settle both so they are grounded.
        for _ in 0..10 {
            stalking.body.step(&world, Intent::default(), DT);
            charging.body.step(&world, Intent::default(), DT);
        }

        assert_eq!(stalking.phase().attack, Attack::Stalk);
        assert_eq!(charging.phase().attack, Attack::Charge);

        let stalk_speed = boss_intent(&stalking, &world, 50.0).move_dir.abs();
        let charge_speed = boss_intent(&charging, &world, 50.0).move_dir.abs();

        assert!(
            charge_speed > stalk_speed,
            "a charge ({charge_speed}) should outpace a stalk ({stalk_speed})"
        );
    }

    #[test]
    fn a_dead_boss_reports_itself_dead() {
        let mut boss = Boss::new(WARDEN, 10.0, 20.0);

        wound_to(&mut boss, 0.0);

        assert!(!boss.is_alive());
        assert_eq!(boss.health_fraction(), 0.0);
    }

    #[test]
    fn summoning_phases_call_for_real_enemies() {
        for boss in BOSSES {
            for phase in boss.phases {
                if let Attack::Summon { minion, count } = phase.attack {
                    assert!(
                        (minion.0 as usize) < ENEMIES.len(),
                        "{} summons an enemy that does not exist",
                        boss.name
                    );
                    assert!(count > 0, "{} summons nothing", boss.name);
                }
            }
        }
    }
}
