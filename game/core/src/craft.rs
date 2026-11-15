//! Crafting recipes and the rules for turning materials into items.

use crate::item::{
    Inventory, ItemId, COAL, COPPER_BAR, COPPER_ORE, COPPER_PICKAXE, GOLD_BAR, GOLD_ORE,
    GOLD_PICKAXE, IRON_BAR, IRON_ORE, IRON_PICKAXE, STONE,
};

/// A crafting station the player must be standing near.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Station {
    Furnace,
    Anvil,
}

/// One recipe: inputs in, output out, optionally requiring a station.
#[derive(Clone, Copy, Debug)]
pub struct Recipe {
    pub output: ItemId,
    pub output_count: u32,
    pub inputs: &'static [(ItemId, u32)],
    pub station: Option<Station>,
}

/// The recipe table, indexed by position.
pub const RECIPES: &[Recipe] = &[
    // Smelting: ore plus fuel becomes a bar.
    Recipe {
        output: COPPER_BAR,
        output_count: 1,
        inputs: &[(COPPER_ORE, 3), (COAL, 1)],
        station: Some(Station::Furnace),
    },
    Recipe {
        output: IRON_BAR,
        output_count: 1,
        inputs: &[(IRON_ORE, 3), (COAL, 1)],
        station: Some(Station::Furnace),
    },
    Recipe {
        output: GOLD_BAR,
        output_count: 1,
        inputs: &[(GOLD_ORE, 4), (COAL, 2)],
        station: Some(Station::Furnace),
    },
    // Tools: bars worked at an anvil.
    Recipe {
        output: COPPER_PICKAXE,
        output_count: 1,
        inputs: &[(COPPER_BAR, 8), (STONE, 4)],
        station: Some(Station::Anvil),
    },
    Recipe {
        output: IRON_PICKAXE,
        output_count: 1,
        inputs: &[(IRON_BAR, 10), (STONE, 4)],
        station: Some(Station::Anvil),
    },
    Recipe {
        output: GOLD_PICKAXE,
        output_count: 1,
        inputs: &[(GOLD_BAR, 12), (STONE, 4)],
        station: Some(Station::Anvil),
    },
];

/// Whether `inventory` holds every input for `recipe`.
pub fn has_materials(inventory: &Inventory, recipe: &Recipe) -> bool {
    recipe
        .inputs
        .iter()
        .all(|&(item, needed)| inventory.count(item) >= needed)
}

/// Whether the station this recipe demands is to hand.
fn station_available(recipe: &Recipe, stations: &[Station]) -> bool {
    match recipe.station {
        None => true,
        Some(required) => stations.contains(&required),
    }
}

/// Indices of every recipe craftable right now with `stations` to hand.
pub fn available(inventory: &Inventory, stations: &[Station]) -> Vec<usize> {
    RECIPES
        .iter()
        .enumerate()
        .filter(|(_, recipe)| {
            station_available(recipe, stations) && has_materials(inventory, recipe)
        })
        .map(|(index, _)| index)
        .collect()
}

/// Craft `RECIPES[index]`, consuming inputs and adding the output.
///
/// Fails, changing nothing, if materials are short, the station is missing,
/// or there is no room for the output.
pub fn craft(inventory: &mut Inventory, index: usize, stations: &[Station]) -> bool {
    let Some(recipe) = RECIPES.get(index) else {
        return false;
    };

    if !station_available(recipe, stations) {
        return false;
    }

    // Work on a copy and only commit on full success, so a craft that fails
    // part-way through can never eat the materials.
    let mut trial = inventory.clone();

    for &(item, needed) in recipe.inputs {
        if !trial.remove(item, needed) {
            return false;
        }
    }

    if trial.add(recipe.output, recipe.output_count) != 0 {
        return false;
    }

    *inventory = trial;
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::item::def;

    const COPPER_BAR_RECIPE: usize = 0;
    const IRON_PICKAXE_RECIPE: usize = 4;

    fn stocked_inventory() -> Inventory {
        let mut inventory = Inventory::new(20);
        inventory.add(COPPER_ORE, 30);
        inventory.add(IRON_ORE, 30);
        inventory.add(GOLD_ORE, 30);
        inventory.add(COAL, 30);
        inventory.add(STONE, 30);
        inventory
    }

    #[test]
    fn an_empty_inventory_has_the_materials_for_nothing() {
        let inventory = Inventory::new(20);

        for recipe in RECIPES {
            assert!(
                !has_materials(&inventory, recipe),
                "{} should not be craftable from nothing",
                def(recipe.output).name
            );
        }
    }

    #[test]
    fn a_stocked_inventory_has_the_materials_for_smelting() {
        let inventory = stocked_inventory();

        assert!(has_materials(&inventory, &RECIPES[COPPER_BAR_RECIPE]));
    }

    #[test]
    fn materials_alone_are_not_enough_without_the_station() {
        let inventory = stocked_inventory();

        let craftable = available(&inventory, &[]);

        assert!(
            craftable.is_empty(),
            "every recipe needs a station, got {craftable:?}"
        );
    }

    #[test]
    fn a_furnace_unlocks_smelting_but_not_toolmaking() {
        let inventory = stocked_inventory();

        let craftable = available(&inventory, &[Station::Furnace]);

        assert!(
            craftable.contains(&COPPER_BAR_RECIPE),
            "furnace should allow smelting copper"
        );
        assert!(
            !craftable.contains(&IRON_PICKAXE_RECIPE),
            "an anvil is needed for tools"
        );
    }

    #[test]
    fn crafting_consumes_the_inputs_and_yields_the_output() {
        let mut inventory = stocked_inventory();

        let crafted = craft(&mut inventory, COPPER_BAR_RECIPE, &[Station::Furnace]);

        assert!(crafted);
        assert_eq!(inventory.count(COPPER_BAR), 1, "should have a bar");
        assert_eq!(inventory.count(COPPER_ORE), 27, "three ore consumed");
        assert_eq!(inventory.count(COAL), 29, "one coal consumed");
    }

    #[test]
    fn crafting_without_the_station_fails_and_consumes_nothing() {
        let mut inventory = stocked_inventory();

        let crafted = craft(&mut inventory, COPPER_BAR_RECIPE, &[Station::Anvil]);

        assert!(!crafted, "a furnace recipe needs a furnace");
        assert_eq!(inventory.count(COPPER_ORE), 30, "ore must be untouched");
        assert_eq!(inventory.count(COPPER_BAR), 0);
    }

    #[test]
    fn crafting_without_materials_fails_and_consumes_nothing() {
        let mut inventory = Inventory::new(20);
        inventory.add(COPPER_ORE, 1); // not the three required
        inventory.add(COAL, 1);

        let crafted = craft(&mut inventory, COPPER_BAR_RECIPE, &[Station::Furnace]);

        assert!(!crafted);
        assert_eq!(inventory.count(COPPER_ORE), 1, "the single ore must remain");
        assert_eq!(inventory.count(COAL), 1, "the coal must remain");
    }

    #[test]
    fn crafting_an_unknown_recipe_fails_safely() {
        let mut inventory = stocked_inventory();

        let crafted = craft(&mut inventory, RECIPES.len() + 5, &[Station::Furnace]);

        assert!(!crafted, "out-of-range recipe index must not panic or craft");
    }

    #[test]
    fn crafting_fails_when_there_is_no_room_for_the_output() {
        // Every slot holds a full stack, and the inputs come out of stacks
        // deep enough that consuming them frees no slot for the bar.
        let mut inventory = Inventory::new(3);
        inventory.add(COPPER_ORE, def(COPPER_ORE).max_stack);
        inventory.add(COAL, def(COAL).max_stack);
        inventory.add(STONE, def(STONE).max_stack);

        assert!(
            (0..3).all(|slot| inventory.slot(slot).is_some()),
            "precondition: every slot is occupied"
        );

        let crafted = craft(&mut inventory, COPPER_BAR_RECIPE, &[Station::Furnace]);

        assert!(!crafted, "nowhere to put the bar");
        assert_eq!(
            inventory.count(COPPER_ORE),
            def(COPPER_ORE).max_stack,
            "ore must survive a failure"
        );
    }

    #[test]
    fn better_tools_cost_more_than_worse_ones() {
        let total_inputs = |index: usize| -> u32 {
            RECIPES[index].inputs.iter().map(|(_, count)| count).sum()
        };

        assert!(
            total_inputs(IRON_PICKAXE_RECIPE) > total_inputs(3),
            "iron pickaxe should cost more than copper"
        );
    }
}
