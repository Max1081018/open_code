//! Quests: a chain of objectives that gives the game direction.
//!
//! Progress is driven by events reported from gameplay rather than by the
//! quest log inspecting the world, so a quest can count things that happened
//! rather than only things that are currently true.

use crate::boss::BossKindId;
use crate::enemy::EnemyKindId;
use crate::item::{Inventory, ItemId};
use crate::world::Tile;

/// Something the player must do.
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Objective {
    /// Break a number of tiles of one kind.
    Mine { tile: Tile, count: u32 },
    /// Hold a number of one item at once.
    Hold { item: ItemId, count: u32 },
    /// Craft a number of one item.
    Craft { item: ItemId, count: u32 },
    /// Kill a number of one enemy.
    Slay { kind: EnemyKindId, count: u32 },
    /// Kill one boss.
    SlayBoss { kind: BossKindId },
    /// Reach a depth, as a fraction of world height.
    Descend { depth: f32 },
}

impl Objective {
    /// How many steps this objective takes.
    pub fn required(self) -> u32 {
        match self {
            Objective::Mine { count, .. }
            | Objective::Hold { count, .. }
            | Objective::Craft { count, .. }
            | Objective::Slay { count, .. } => count,
            Objective::SlayBoss { .. } | Objective::Descend { .. } => 1,
        }
    }
}

/// Something that happened, which may advance an objective.
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum QuestEvent {
    Mined(Tile),
    Crafted(ItemId),
    Slew(EnemyKindId),
    SlewBoss(BossKindId),
    /// Current depth as a fraction of world height.
    DepthReached(f32),
}

/// One quest.
#[derive(Clone, Copy, Debug)]
pub struct Quest {
    pub name: &'static str,
    pub blurb: &'static str,
    pub objective: Objective,
    pub reward: &'static [(ItemId, u32)],
    /// Quest that must be finished first, by index into [`QUESTS`].
    pub requires: Option<usize>,
}

use crate::boss::WARDEN;
use crate::enemy::{CAVE_CRAWLER, SLIME};
use crate::item::{
    COAL, COPPER_BAR, COPPER_ORE, COPPER_PICKAXE, CRACKED_IDOL, DIRT, GOLD_BAR, GOLD_ORE,
    IRON_BAR, IRON_ORE, STONE,
};

/// The quest chain, in order. Each unlocks the next.
pub const QUESTS: &[Quest] = &[
    Quest {
        name: "Breaking Ground",
        blurb: "Everything starts with a hole. Dig out some earth.",
        objective: Objective::Mine {
            tile: Tile::Dirt,
            count: 12,
        },
        reward: &[(STONE, 10)],
        requires: None,
    },
    Quest {
        name: "Down to the Rock",
        blurb: "Below the soil the world turns to stone. Cut into it.",
        objective: Objective::Mine {
            tile: Tile::Stone,
            count: 25,
        },
        reward: &[(COAL, 6)],
        requires: Some(0),
    },
    Quest {
        name: "Prospector",
        blurb: "Copper runs in veins near the surface. Find some.",
        objective: Objective::Hold {
            item: COPPER_ORE,
            count: 12,
        },
        reward: &[(COAL, 8)],
        requires: Some(1),
    },
    Quest {
        name: "First Smelt",
        blurb: "Ore is not a tool. Put it through a furnace.",
        objective: Objective::Craft {
            item: COPPER_BAR,
            count: 4,
        },
        reward: &[(STONE, 20)],
        requires: Some(2),
    },
    Quest {
        name: "A Proper Pick",
        blurb: "Bare hands only go so far. Work the bars at an anvil.",
        objective: Objective::Craft {
            item: COPPER_PICKAXE,
            count: 1,
        },
        reward: &[(IRON_ORE, 10)],
        requires: Some(3),
    },
    Quest {
        name: "Night Watch",
        blurb: "Slimes come out after dark. Thin them out.",
        objective: Objective::Slay {
            kind: SLIME,
            count: 8,
        },
        reward: &[(COAL, 10)],
        requires: Some(1),
    },
    Quest {
        name: "Into the Deep",
        blurb: "The good metal is a long way down. Go and find it.",
        objective: Objective::Descend { depth: 0.55 },
        reward: &[(IRON_BAR, 4)],
        requires: Some(4),
    },
    Quest {
        name: "Something in the Dark",
        blurb: "You are not alone down here. Clear the crawlers out.",
        objective: Objective::Slay {
            kind: CAVE_CRAWLER,
            count: 6,
        },
        reward: &[(GOLD_ORE, 8)],
        requires: Some(6),
    },
    Quest {
        name: "Gold Standard",
        blurb: "Gold is soft, but it holds an edge no copper can.",
        objective: Objective::Craft {
            item: GOLD_BAR,
            count: 3,
        },
        reward: &[(CRACKED_IDOL, 1)],
        requires: Some(7),
    },
    Quest {
        name: "The Warden Falls",
        blurb: "Something old guards the deep. Put it down.",
        objective: Objective::SlayBoss { kind: WARDEN },
        reward: &[(GOLD_BAR, 15), (DIRT, 1)],
        requires: Some(8),
    },
];

/// Per-quest progress and reward state.
#[derive(Clone, Debug)]
pub struct QuestLog {
    progress: Vec<u32>,
    claimed: Vec<bool>,
    /// Deepest fraction reached so far, for descent objectives.
    deepest: f32,
}

impl Default for QuestLog {
    fn default() -> Self {
        Self::new()
    }
}

impl QuestLog {
    pub fn new() -> QuestLog {
        QuestLog {
            progress: vec![0; QUESTS.len()],
            claimed: vec![false; QUESTS.len()],
            deepest: 0.0,
        }
    }

    pub fn progress(&self, index: usize) -> u32 {
        self.progress.get(index).copied().unwrap_or(0)
    }

    pub fn is_complete(&self, index: usize) -> bool {
        match QUESTS.get(index) {
            Some(quest) => self.progress(index) >= quest.objective.required(),
            None => false,
        }
    }

    /// Whether the quest's prerequisite has been finished.
    pub fn is_available(&self, index: usize) -> bool {
        match QUESTS.get(index) {
            Some(quest) => match quest.requires {
                None => true,
                Some(previous) => self.is_complete(previous),
            },
            None => false,
        }
    }

    pub fn is_claimed(&self, index: usize) -> bool {
        self.claimed.get(index).copied().unwrap_or(false)
    }

    /// The quest the player should be working on: the first available one
    /// that is not yet finished.
    pub fn active(&self) -> Option<usize> {
        (0..QUESTS.len()).find(|&index| self.is_available(index) && !self.is_complete(index))
    }

    /// Raise a quest's progress, never lowering it and never overshooting.
    fn advance_to(&mut self, index: usize, value: u32) {
        let Some(quest) = QUESTS.get(index) else {
            return;
        };

        let capped = value.min(quest.objective.required());

        if capped > self.progress[index] {
            self.progress[index] = capped;
        }
    }

    /// Note something that happened, advancing any objective it matches.
    ///
    /// Progress is counted on every quest, including locked ones, so work
    /// done early is banked rather than lost.
    pub fn record(&mut self, event: QuestEvent) {
        if let QuestEvent::DepthReached(fraction) = event {
            self.deepest = self.deepest.max(fraction);
        }

        for index in 0..QUESTS.len() {
            let matched = match (QUESTS[index].objective, event) {
                (Objective::Mine { tile, .. }, QuestEvent::Mined(broken)) => broken == tile,
                (Objective::Craft { item, .. }, QuestEvent::Crafted(made)) => made == item,
                (Objective::Slay { kind, .. }, QuestEvent::Slew(killed)) => killed == kind,
                (Objective::SlayBoss { kind }, QuestEvent::SlewBoss(killed)) => killed == kind,
                (Objective::Descend { depth }, QuestEvent::DepthReached(_)) => {
                    self.deepest >= depth
                }
                _ => false,
            };

            if matched {
                let next = match QUESTS[index].objective {
                    // One-shot objectives jump straight to done.
                    Objective::SlayBoss { .. } | Objective::Descend { .. } => 1,
                    _ => self.progress[index] + 1,
                };
                self.advance_to(index, next);
            }
        }
    }

    /// Advance "hold this much" objectives, which depend on current stock
    /// rather than on anything that happened.
    pub fn observe_inventory(&mut self, inventory: &Inventory) {
        for index in 0..QUESTS.len() {
            if let Objective::Hold { item, .. } = QUESTS[index].objective {
                // advance_to never lowers progress, so spending the items
                // afterwards does not undo a finished quest.
                self.advance_to(index, inventory.count(item));
            }
        }
    }

    /// Pay out a finished quest's reward, once.
    pub fn claim(&mut self, index: usize, inventory: &mut Inventory) -> bool {
        let Some(quest) = QUESTS.get(index) else {
            return false;
        };

        if !self.is_complete(index) || self.claimed[index] {
            return false;
        }

        for &(item, count) in quest.reward {
            inventory.add(item, count);
        }

        self.claimed[index] = true;
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn stocked() -> Inventory {
        Inventory::new(40)
    }

    #[test]
    fn the_chain_is_well_formed() {
        for (index, quest) in QUESTS.iter().enumerate() {
            assert!(!quest.name.is_empty(), "quest {index} has no name");
            assert!(!quest.blurb.is_empty(), "quest {index} has no blurb");
            assert!(
                !quest.reward.is_empty(),
                "{} offers no reward",
                quest.name
            );
            assert!(
                quest.objective.required() > 0,
                "{} asks for nothing",
                quest.name
            );

            // Prerequisites must point backwards, which rules out cycles.
            if let Some(required) = quest.requires {
                assert!(
                    required < index,
                    "{} depends on a later quest, which can never be done",
                    quest.name
                );
            }
        }
    }

    #[test]
    fn exactly_one_quest_opens_the_chain() {
        let openers = QUESTS.iter().filter(|q| q.requires.is_none()).count();

        assert_eq!(openers, 1, "there should be one obvious place to start");
    }

    #[test]
    fn every_quest_is_reachable_from_the_start() {
        for index in 0..QUESTS.len() {
            let mut at = index;
            let mut hops = 0;

            while let Some(previous) = QUESTS[at].requires {
                at = previous;
                hops += 1;
                assert!(hops <= QUESTS.len(), "quest {index} is in a loop");
            }

            assert_eq!(at, 0, "quest {index} does not trace back to the start");
        }
    }

    #[test]
    fn a_new_log_has_nothing_done() {
        let log = QuestLog::new();

        for index in 0..QUESTS.len() {
            assert_eq!(log.progress(index), 0);
            assert!(!log.is_complete(index));
            assert!(!log.is_claimed(index));
        }
    }

    #[test]
    fn only_the_first_quest_is_available_at_the_start() {
        let log = QuestLog::new();

        assert!(log.is_available(0));
        for index in 1..QUESTS.len() {
            assert!(!log.is_available(index), "quest {index} opened too early");
        }
    }

    #[test]
    fn the_first_quest_is_the_active_one_at_the_start() {
        assert_eq!(QuestLog::new().active(), Some(0));
    }

    #[test]
    fn a_matching_event_advances_the_objective() {
        let mut log = QuestLog::new();

        log.record(QuestEvent::Mined(Tile::Dirt));

        assert_eq!(log.progress(0), 1);
    }

    #[test]
    fn an_unrelated_event_advances_nothing() {
        let mut log = QuestLog::new();

        log.record(QuestEvent::Slew(SLIME));

        assert_eq!(log.progress(0), 0, "digging quest should ignore a kill");
    }

    #[test]
    fn grass_does_not_count_toward_a_stone_quest() {
        let mut log = QuestLog::new();

        for _ in 0..40 {
            log.record(QuestEvent::Mined(Tile::Grass));
        }

        assert_eq!(log.progress(1), 0);
    }

    #[test]
    fn progress_stops_at_the_amount_required() {
        let mut log = QuestLog::new();

        for _ in 0..200 {
            log.record(QuestEvent::Mined(Tile::Dirt));
        }

        assert_eq!(log.progress(0), QUESTS[0].objective.required());
    }

    #[test]
    fn meeting_the_requirement_completes_the_quest() {
        let mut log = QuestLog::new();

        for _ in 0..QUESTS[0].objective.required() {
            log.record(QuestEvent::Mined(Tile::Dirt));
        }

        assert!(log.is_complete(0));
    }

    #[test]
    fn finishing_a_quest_unlocks_the_one_that_follows() {
        let mut log = QuestLog::new();
        assert!(!log.is_available(1), "precondition: quest 1 is locked");

        for _ in 0..QUESTS[0].objective.required() {
            log.record(QuestEvent::Mined(Tile::Dirt));
        }

        assert!(log.is_available(1), "finishing the first should open the next");
    }

    #[test]
    fn the_active_quest_moves_on_once_one_is_done() {
        let mut log = QuestLog::new();

        for _ in 0..QUESTS[0].objective.required() {
            log.record(QuestEvent::Mined(Tile::Dirt));
        }

        assert_ne!(log.active(), Some(0), "a finished quest is not still active");
    }

    #[test]
    fn progress_can_be_made_on_a_quest_before_it_unlocks() {
        // Killing slimes early should still count, rather than being lost.
        let mut log = QuestLog::new();

        log.record(QuestEvent::Slew(SLIME));

        assert_eq!(log.progress(5), 1);
    }

    #[test]
    fn holding_enough_of_an_item_completes_a_gathering_quest() {
        let mut log = QuestLog::new();
        let mut inventory = stocked();
        inventory.add(COPPER_ORE, 12);

        log.observe_inventory(&inventory);

        assert!(log.is_complete(2), "twelve copper should satisfy the quest");
    }

    #[test]
    fn holding_too_little_does_not_complete_a_gathering_quest() {
        let mut log = QuestLog::new();
        let mut inventory = stocked();
        inventory.add(COPPER_ORE, 3);

        log.observe_inventory(&inventory);

        assert!(!log.is_complete(2));
        assert_eq!(log.progress(2), 3);
    }

    #[test]
    fn a_gathering_quest_stays_done_after_the_items_are_spent() {
        let mut log = QuestLog::new();
        let mut inventory = stocked();
        inventory.add(COPPER_ORE, 12);
        log.observe_inventory(&inventory);

        inventory.remove(COPPER_ORE, 12);
        log.observe_inventory(&inventory);

        assert!(
            log.is_complete(2),
            "spending the ore should not undo the quest"
        );
    }

    #[test]
    fn descending_records_the_deepest_point_reached() {
        let mut log = QuestLog::new();

        log.record(QuestEvent::DepthReached(0.8));
        log.record(QuestEvent::DepthReached(0.1));

        assert!(
            log.is_complete(6),
            "coming back up should not undo having been deep"
        );
    }

    #[test]
    fn a_shallow_dip_does_not_finish_the_descent_quest() {
        let mut log = QuestLog::new();

        log.record(QuestEvent::DepthReached(0.2));

        assert!(!log.is_complete(6));
    }

    #[test]
    fn killing_the_boss_completes_its_quest() {
        let mut log = QuestLog::new();

        log.record(QuestEvent::SlewBoss(WARDEN));

        assert!(log.is_complete(9));
    }

    #[test]
    fn claiming_a_finished_quest_pays_the_reward() {
        let mut log = QuestLog::new();
        let mut inventory = stocked();

        for _ in 0..QUESTS[0].objective.required() {
            log.record(QuestEvent::Mined(Tile::Dirt));
        }
        let paid = log.claim(0, &mut inventory);

        assert!(paid);
        assert_eq!(inventory.count(STONE), 10);
        assert!(log.is_claimed(0));
    }

    #[test]
    fn a_reward_cannot_be_claimed_twice() {
        let mut log = QuestLog::new();
        let mut inventory = stocked();

        for _ in 0..QUESTS[0].objective.required() {
            log.record(QuestEvent::Mined(Tile::Dirt));
        }
        log.claim(0, &mut inventory);
        let again = log.claim(0, &mut inventory);

        assert!(!again, "a quest should pay out once");
        assert_eq!(inventory.count(STONE), 10, "and not twice");
    }

    #[test]
    fn an_unfinished_quest_pays_nothing() {
        let mut log = QuestLog::new();
        let mut inventory = stocked();

        let paid = log.claim(0, &mut inventory);

        assert!(!paid);
        assert_eq!(inventory.count(STONE), 0);
    }

    #[test]
    fn claiming_a_quest_that_does_not_exist_is_harmless() {
        let mut log = QuestLog::new();
        let mut inventory = stocked();

        assert!(!log.claim(999, &mut inventory));
    }

    #[test]
    fn the_whole_chain_can_be_completed_in_order() {
        let mut log = QuestLog::new();
        let mut inventory = stocked();

        // Drive each quest with whatever event satisfies it.
        for index in 0..QUESTS.len() {
            let objective = QUESTS[index].objective;

            match objective {
                Objective::Mine { tile, count } => {
                    for _ in 0..count {
                        log.record(QuestEvent::Mined(tile));
                    }
                }
                Objective::Hold { item, count } => {
                    inventory.add(item, count);
                    log.observe_inventory(&inventory);
                }
                Objective::Craft { item, count } => {
                    for _ in 0..count {
                        log.record(QuestEvent::Crafted(item));
                    }
                }
                Objective::Slay { kind, count } => {
                    for _ in 0..count {
                        log.record(QuestEvent::Slew(kind));
                    }
                }
                Objective::SlayBoss { kind } => log.record(QuestEvent::SlewBoss(kind)),
                Objective::Descend { depth } => {
                    log.record(QuestEvent::DepthReached(depth + 0.01))
                }
            }

            assert!(log.is_complete(index), "{} did not complete", QUESTS[index].name);
            assert!(log.claim(index, &mut inventory), "{} paid nothing", QUESTS[index].name);
        }

        assert_eq!(log.active(), None, "the chain should finish");
    }
}
