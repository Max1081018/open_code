//! Items, stacks, and the player's inventory.
//!
//! Items are a data table indexed by `ItemId` rather than a giant enum, so
//! content can grow to hundreds of entries without touching any logic.

use crate::world::Tile;

/// Index into [`ITEMS`].
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug, Hash)]
pub struct ItemId(pub u16);

/// What an item does when used.
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum ItemKind {
    /// Places a tile when used.
    Block(Tile),
    /// Digs, with the given tool power.
    Pickaxe { power: f32 },
    /// Crafting material with no direct use.
    Material,
}

/// Static definition of one item.
#[derive(Clone, Copy, Debug)]
pub struct ItemDef {
    pub name: &'static str,
    pub max_stack: u32,
    pub kind: ItemKind,
}

/// How many of a typical item fit in one slot.
const STANDARD_STACK: u32 = 999;

/// Tools never stack.
const UNIQUE: u32 = 1;

/// The item table. `ItemId(n)` indexes this slice, so entries may be appended
/// but never reordered.
pub const ITEMS: &[ItemDef] = &[
    ItemDef {
        name: "Dirt Block",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Block(Tile::Dirt),
    },
    ItemDef {
        name: "Grass Block",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Block(Tile::Grass),
    },
    ItemDef {
        name: "Stone Block",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Block(Tile::Stone),
    },
    ItemDef {
        name: "Coal",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Material,
    },
    ItemDef {
        name: "Copper Ore",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Block(Tile::CopperOre),
    },
    ItemDef {
        name: "Iron Ore",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Block(Tile::IronOre),
    },
    ItemDef {
        name: "Gold Ore",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Block(Tile::GoldOre),
    },
    ItemDef {
        name: "Copper Bar",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Material,
    },
    ItemDef {
        name: "Iron Bar",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Material,
    },
    ItemDef {
        name: "Gold Bar",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Material,
    },
    ItemDef {
        name: "Copper Pickaxe",
        max_stack: UNIQUE,
        kind: ItemKind::Pickaxe { power: 2.0 },
    },
    ItemDef {
        name: "Iron Pickaxe",
        max_stack: UNIQUE,
        kind: ItemKind::Pickaxe { power: 3.5 },
    },
    ItemDef {
        name: "Gold Pickaxe",
        max_stack: UNIQUE,
        kind: ItemKind::Pickaxe { power: 5.0 },
    },
    ItemDef {
        name: "Sand Block",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Block(Tile::Sand),
    },
    ItemDef {
        name: "Snow Block",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Block(Tile::Snow),
    },
    // Summoning tokens: one per boss, consumed to call it.
    ItemDef {
        name: "Cracked Idol",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Material,
    },
    ItemDef {
        name: "Frozen Heart",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Material,
    },
    ItemDef {
        name: "Sunstone",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Material,
    },
    ItemDef {
        name: "Void Shard",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Material,
    },
    // Trophies: proof of a kill, and crafting material later.
    ItemDef {
        name: "Warden Trophy",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Material,
    },
    ItemDef {
        name: "Rimewyrm Trophy",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Material,
    },
    ItemDef {
        name: "Sand Colossus Trophy",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Material,
    },
    ItemDef {
        name: "Hollow King Trophy",
        max_stack: STANDARD_STACK,
        kind: ItemKind::Material,
    },
];

pub const DIRT: ItemId = ItemId(0);
pub const GRASS: ItemId = ItemId(1);
pub const STONE: ItemId = ItemId(2);
pub const COAL: ItemId = ItemId(3);
pub const COPPER_ORE: ItemId = ItemId(4);
pub const IRON_ORE: ItemId = ItemId(5);
pub const GOLD_ORE: ItemId = ItemId(6);
pub const COPPER_BAR: ItemId = ItemId(7);
pub const IRON_BAR: ItemId = ItemId(8);
pub const GOLD_BAR: ItemId = ItemId(9);
pub const COPPER_PICKAXE: ItemId = ItemId(10);
pub const IRON_PICKAXE: ItemId = ItemId(11);
pub const GOLD_PICKAXE: ItemId = ItemId(12);
pub const SAND: ItemId = ItemId(13);
pub const SNOW: ItemId = ItemId(14);
pub const CRACKED_IDOL: ItemId = ItemId(15);
pub const FROZEN_HEART: ItemId = ItemId(16);
pub const SUNSTONE: ItemId = ItemId(17);
pub const VOID_SHARD: ItemId = ItemId(18);
pub const WARDEN_TROPHY: ItemId = ItemId(19);
pub const RIMEWYRM_TROPHY: ItemId = ItemId(20);
pub const COLOSSUS_TROPHY: ItemId = ItemId(21);
pub const HOLLOW_KING_TROPHY: ItemId = ItemId(22);

/// Look up an item's definition.
pub fn def(id: ItemId) -> &'static ItemDef {
    &ITEMS[id.0 as usize]
}

/// What breaking `tile` drops, if anything.
pub fn drop_from(tile: Tile) -> Option<ItemId> {
    match tile {
        Tile::Air => None,
        // Digging grass destroys the turf and leaves plain soil.
        Tile::Dirt | Tile::Grass => Some(DIRT),
        Tile::Sand => Some(SAND),
        Tile::Snow => Some(SNOW),
        Tile::Stone => Some(STONE),
        Tile::CoalOre => Some(COAL),
        Tile::CopperOre => Some(COPPER_ORE),
        Tile::IronOre => Some(IRON_ORE),
        Tile::GoldOre => Some(GOLD_ORE),
    }
}

/// A quantity of one item occupying a single slot.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Stack {
    pub item: ItemId,
    pub count: u32,
}

/// Fixed-size slot storage.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Inventory {
    slots: Vec<Option<Stack>>,
}

impl Inventory {
    pub fn new(slot_count: usize) -> Inventory {
        Inventory {
            slots: vec![None; slot_count],
        }
    }

    pub fn slot_count(&self) -> usize {
        self.slots.len()
    }

    pub fn slot(&self, index: usize) -> Option<Stack> {
        self.slots.get(index).copied().flatten()
    }

    /// Overwrite one slot outright, ignoring stacking rules.
    ///
    /// Used when restoring a save, where the exact slot layout must come back
    /// as it was rather than being re-packed by `add`.
    pub fn set_slot(&mut self, index: usize, stack: Option<Stack>) {
        if let Some(slot) = self.slots.get_mut(index) {
            *slot = stack;
        }
    }

    /// Total held across every slot.
    pub fn count(&self, item: ItemId) -> u32 {
        self.slots
            .iter()
            .flatten()
            .filter(|stack| stack.item == item)
            .map(|stack| stack.count)
            .sum()
    }

    /// Insert `count` of `item`, topping up partial stacks before opening new
    /// slots. Returns however many did not fit.
    pub fn add(&mut self, item: ItemId, count: u32) -> u32 {
        let max_stack = def(item).max_stack;
        let mut remaining = count;

        // Top up partial stacks first, so the inventory stays compact.
        for slot in self.slots.iter_mut() {
            if remaining == 0 {
                break;
            }

            if let Some(stack) = slot {
                if stack.item == item && stack.count < max_stack {
                    let moved = (max_stack - stack.count).min(remaining);
                    stack.count += moved;
                    remaining -= moved;
                }
            }
        }

        for slot in self.slots.iter_mut() {
            if remaining == 0 {
                break;
            }

            if slot.is_none() {
                let moved = max_stack.min(remaining);
                *slot = Some(Stack { item, count: moved });
                remaining -= moved;
            }
        }

        remaining
    }

    /// Take `count` of `item`. Returns false and changes nothing if the
    /// inventory holds fewer than that.
    pub fn remove(&mut self, item: ItemId, count: u32) -> bool {
        // Checked up front so a partial draw can never happen.
        if self.count(item) < count {
            return false;
        }

        let mut remaining = count;

        for slot in self.slots.iter_mut() {
            if remaining == 0 {
                break;
            }

            if let Some(stack) = slot {
                if stack.item == item {
                    let taken = stack.count.min(remaining);
                    stack.count -= taken;
                    remaining -= taken;

                    if stack.count == 0 {
                        *slot = None;
                    }
                }
            }
        }

        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_item_id_constant_points_at_its_own_definition() {
        assert_eq!(def(DIRT).name, "Dirt Block");
        assert_eq!(def(STONE).name, "Stone Block");
        assert_eq!(def(GOLD_PICKAXE).name, "Gold Pickaxe");
        assert_eq!(def(SNOW).name, "Snow Block");
        assert_eq!(def(HOLLOW_KING_TROPHY).name, "Hollow King Trophy");
        assert_eq!(ITEMS.len(), 23, "constants must cover the whole table");
    }

    #[test]
    fn better_pickaxes_dig_harder() {
        let power = |id| match def(id).kind {
            ItemKind::Pickaxe { power } => power,
            other => panic!("expected a pickaxe, got {other:?}"),
        };

        assert!(power(COPPER_PICKAXE) < power(IRON_PICKAXE));
        assert!(power(IRON_PICKAXE) < power(GOLD_PICKAXE));
    }

    #[test]
    fn tools_do_not_stack_but_materials_do() {
        assert_eq!(def(IRON_PICKAXE).max_stack, 1);
        assert!(def(STONE).max_stack > 1);
    }

    #[test]
    fn breaking_a_tile_drops_its_matching_item() {
        assert_eq!(drop_from(Tile::Stone), Some(STONE));
        assert_eq!(drop_from(Tile::CopperOre), Some(COPPER_ORE));
        assert_eq!(drop_from(Tile::GoldOre), Some(GOLD_ORE));
    }

    #[test]
    fn breaking_grass_yields_plain_dirt() {
        // Grass turns to dirt when dug, as in every game of this shape.
        assert_eq!(drop_from(Tile::Grass), Some(DIRT));
    }

    #[test]
    fn coal_ore_drops_coal_rather_than_a_placeable_block() {
        assert_eq!(drop_from(Tile::CoalOre), Some(COAL));
        assert_eq!(def(COAL).kind, ItemKind::Material);
    }

    #[test]
    fn empty_space_drops_nothing() {
        assert_eq!(drop_from(Tile::Air), None);
    }

    #[test]
    fn set_slot_places_a_stack_exactly_where_told() {
        let mut inventory = Inventory::new(5);

        inventory.set_slot(3, Some(Stack { item: STONE, count: 7 }));

        assert_eq!(inventory.slot(3), Some(Stack { item: STONE, count: 7 }));
        assert_eq!(inventory.slot(0), None, "earlier slots stay untouched");
        assert_eq!(inventory.count(STONE), 7);
    }

    #[test]
    fn set_slot_can_clear_a_slot() {
        let mut inventory = Inventory::new(5);
        inventory.add(STONE, 4);

        inventory.set_slot(0, None);

        assert_eq!(inventory.slot(0), None);
        assert_eq!(inventory.count(STONE), 0);
    }

    #[test]
    fn set_slot_outside_the_inventory_is_ignored() {
        let mut inventory = Inventory::new(2);

        inventory.set_slot(99, Some(Stack { item: STONE, count: 1 }));

        assert_eq!(inventory.count(STONE), 0, "nothing should have been stored");
        assert_eq!(inventory.slot_count(), 2, "and the inventory must not grow");
    }

    #[test]
    fn a_new_inventory_is_empty() {
        let inventory = Inventory::new(10);

        assert_eq!(inventory.count(STONE), 0);
        assert_eq!(inventory.slot(0), None);
    }

    #[test]
    fn added_items_land_in_the_first_free_slot() {
        let mut inventory = Inventory::new(10);

        let leftover = inventory.add(STONE, 5);

        assert_eq!(leftover, 0);
        assert_eq!(inventory.slot(0), Some(Stack { item: STONE, count: 5 }));
        assert_eq!(inventory.count(STONE), 5);
    }

    #[test]
    fn adding_more_of_an_item_tops_up_the_existing_stack() {
        let mut inventory = Inventory::new(10);
        inventory.add(STONE, 5);

        inventory.add(STONE, 7);

        assert_eq!(inventory.slot(0), Some(Stack { item: STONE, count: 12 }));
        assert_eq!(inventory.slot(1), None, "should not open a second slot");
    }

    #[test]
    fn a_full_stack_overflows_into_the_next_slot() {
        let mut inventory = Inventory::new(10);
        let max = def(STONE).max_stack;

        let leftover = inventory.add(STONE, max + 3);

        assert_eq!(leftover, 0);
        assert_eq!(inventory.slot(0), Some(Stack { item: STONE, count: max }));
        assert_eq!(inventory.slot(1), Some(Stack { item: STONE, count: 3 }));
        assert_eq!(inventory.count(STONE), max + 3);
    }

    #[test]
    fn items_that_do_not_fit_are_reported_as_leftover() {
        let mut inventory = Inventory::new(1);
        let max = def(STONE).max_stack;

        let leftover = inventory.add(STONE, max + 10);

        assert_eq!(leftover, 10, "ten should not have fitted");
        assert_eq!(inventory.count(STONE), max);
    }

    #[test]
    fn unstackable_tools_each_take_their_own_slot() {
        let mut inventory = Inventory::new(10);

        inventory.add(IRON_PICKAXE, 2);

        assert_eq!(
            inventory.slot(0),
            Some(Stack {
                item: IRON_PICKAXE,
                count: 1
            })
        );
        assert_eq!(
            inventory.slot(1),
            Some(Stack {
                item: IRON_PICKAXE,
                count: 1
            })
        );
    }

    #[test]
    fn removing_items_reduces_the_stack() {
        let mut inventory = Inventory::new(10);
        inventory.add(STONE, 10);

        let removed = inventory.remove(STONE, 4);

        assert!(removed);
        assert_eq!(inventory.count(STONE), 6);
    }

    #[test]
    fn emptying_a_stack_frees_its_slot() {
        let mut inventory = Inventory::new(10);
        inventory.add(STONE, 3);

        inventory.remove(STONE, 3);

        assert_eq!(inventory.slot(0), None, "exhausted stack should clear");
    }

    #[test]
    fn removing_more_than_is_held_fails_and_changes_nothing() {
        let mut inventory = Inventory::new(10);
        inventory.add(STONE, 3);

        let removed = inventory.remove(STONE, 4);

        assert!(!removed, "should refuse to over-draw");
        assert_eq!(inventory.count(STONE), 3, "inventory must be untouched");
    }

    #[test]
    fn removal_draws_across_several_stacks() {
        let mut inventory = Inventory::new(10);
        let max = def(STONE).max_stack;
        inventory.add(STONE, max + 5);

        let removed = inventory.remove(STONE, max + 2);

        assert!(removed);
        assert_eq!(inventory.count(STONE), 3);
    }
}
