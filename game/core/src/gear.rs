//! What the player is effectively wielding.
//!
//! There is no explicit equip step: the best tool and the best weapon in the
//! bag are the ones in hand. That keeps the inventory simple and means a
//! crafted upgrade takes effect the moment it is made.

use crate::item::{def, Inventory, ItemId, ItemKind, ITEMS};

/// Digging power with nothing better to hand.
pub const BARE_HAND_POWER: f32 = 1.6;

/// Damage dealt with nothing better to hand.
pub const BARE_HAND_DAMAGE: f32 = 8.0;

/// Find the held item scoring highest under `rate`, ignoring items it
/// does not rate at all.
fn best_by(inventory: &Inventory, rate: impl Fn(ItemKind) -> Option<f32>) -> Option<(ItemId, f32)> {
    let mut best: Option<(ItemId, f32)> = None;

    for index in 0..ITEMS.len() {
        let item = ItemId(index as u16);

        if inventory.count(item) == 0 {
            continue;
        }

        let Some(score) = rate(def(item).kind) else {
            continue;
        };

        // Strictly greater, so the result does not depend on table order.
        if best.is_none_or(|(_, current)| score > current) {
            best = Some((item, score));
        }
    }

    best
}

/// The strongest pickaxe held, if any.
pub fn best_pickaxe(inventory: &Inventory) -> Option<ItemId> {
    best_by(inventory, |kind| match kind {
        ItemKind::Pickaxe { power } => Some(power),
        _ => None,
    })
    .map(|(item, _)| item)
}

/// The strongest sword held, if any.
pub fn best_sword(inventory: &Inventory) -> Option<ItemId> {
    best_by(inventory, |kind| match kind {
        ItemKind::Sword { damage } => Some(damage),
        _ => None,
    })
    .map(|(item, _)| item)
}

/// How fast the player digs right now.
pub fn dig_power(inventory: &Inventory) -> f32 {
    best_by(inventory, |kind| match kind {
        ItemKind::Pickaxe { power } => Some(power),
        _ => None,
    })
    .map(|(_, power)| power)
    .unwrap_or(BARE_HAND_POWER)
    .max(BARE_HAND_POWER)
}

/// How hard the player hits right now.
pub fn attack_damage(inventory: &Inventory) -> f32 {
    best_by(inventory, |kind| match kind {
        ItemKind::Sword { damage } => Some(damage),
        _ => None,
    })
    .map(|(_, damage)| damage)
    .unwrap_or(BARE_HAND_DAMAGE)
    .max(BARE_HAND_DAMAGE)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::item::{
        COPPER_PICKAXE, COPPER_SWORD, GOLD_PICKAXE, GOLD_SWORD, IRON_PICKAXE, IRON_SWORD,
        STONE,
    };

    fn bag() -> Inventory {
        Inventory::new(20)
    }

    #[test]
    fn bare_hands_are_the_floor() {
        let empty = bag();

        assert_eq!(dig_power(&empty), BARE_HAND_POWER);
        assert_eq!(attack_damage(&empty), BARE_HAND_DAMAGE);
        assert_eq!(best_pickaxe(&empty), None);
        assert_eq!(best_sword(&empty), None);
    }

    #[test]
    fn a_pickaxe_digs_faster_than_bare_hands() {
        let mut inventory = bag();
        inventory.add(COPPER_PICKAXE, 1);

        assert!(
            dig_power(&inventory) > BARE_HAND_POWER,
            "crafting a pickaxe should actually speed up digging"
        );
        assert_eq!(best_pickaxe(&inventory), Some(COPPER_PICKAXE));
    }

    #[test]
    fn a_sword_hits_harder_than_bare_hands() {
        let mut inventory = bag();
        inventory.add(COPPER_SWORD, 1);

        assert!(attack_damage(&inventory) > BARE_HAND_DAMAGE);
        assert_eq!(best_sword(&inventory), Some(COPPER_SWORD));
    }

    #[test]
    fn the_better_tool_wins_whichever_order_it_was_picked_up() {
        let mut forwards = bag();
        forwards.add(COPPER_PICKAXE, 1);
        forwards.add(IRON_PICKAXE, 1);

        let mut backwards = bag();
        backwards.add(IRON_PICKAXE, 1);
        backwards.add(COPPER_PICKAXE, 1);

        assert_eq!(best_pickaxe(&forwards), Some(IRON_PICKAXE));
        assert_eq!(best_pickaxe(&backwards), Some(IRON_PICKAXE));
        assert_eq!(dig_power(&forwards), dig_power(&backwards));
    }

    #[test]
    fn the_progression_is_strictly_upward() {
        let power_with = |item| {
            let mut inventory = bag();
            inventory.add(item, 1);
            dig_power(&inventory)
        };

        assert!(power_with(COPPER_PICKAXE) < power_with(IRON_PICKAXE));
        assert!(power_with(IRON_PICKAXE) < power_with(GOLD_PICKAXE));

        let damage_with = |item| {
            let mut inventory = bag();
            inventory.add(item, 1);
            attack_damage(&inventory)
        };

        assert!(damage_with(COPPER_SWORD) < damage_with(IRON_SWORD));
        assert!(damage_with(IRON_SWORD) < damage_with(GOLD_SWORD));
    }

    #[test]
    fn a_sword_does_not_help_you_dig() {
        let mut inventory = bag();
        inventory.add(GOLD_SWORD, 1);

        assert_eq!(dig_power(&inventory), BARE_HAND_POWER);
    }

    #[test]
    fn a_pickaxe_is_not_a_weapon() {
        let mut inventory = bag();
        inventory.add(GOLD_PICKAXE, 1);

        assert_eq!(attack_damage(&inventory), BARE_HAND_DAMAGE);
    }

    #[test]
    fn ordinary_materials_change_nothing() {
        let mut inventory = bag();
        inventory.add(STONE, 500);

        assert_eq!(dig_power(&inventory), BARE_HAND_POWER);
        assert_eq!(attack_damage(&inventory), BARE_HAND_DAMAGE);
    }

    #[test]
    fn losing_a_tool_drops_you_back_down() {
        let mut inventory = bag();
        inventory.add(IRON_PICKAXE, 1);
        let armed = dig_power(&inventory);

        inventory.remove(IRON_PICKAXE, 1);

        assert!(dig_power(&inventory) < armed);
        assert_eq!(dig_power(&inventory), BARE_HAND_POWER);
    }

    #[test]
    fn every_tool_in_the_table_is_reachable_as_a_best_choice() {
        // Guards against a tool being added that nothing can ever select.
        for index in 0..ITEMS.len() {
            let item = ItemId(index as u16);
            let mut inventory = bag();
            inventory.add(item, 1);

            match def(item).kind {
                ItemKind::Pickaxe { .. } => {
                    assert_eq!(best_pickaxe(&inventory), Some(item), "{}", def(item).name)
                }
                ItemKind::Sword { .. } => {
                    assert_eq!(best_sword(&inventory), Some(item), "{}", def(item).name)
                }
                _ => {}
            }
        }
    }
}
