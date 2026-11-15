//! Surface biomes: broad bands of differing terrain across the world.

use crate::noise::fbm_1d;
use crate::world::Tile;

/// How quickly biomes change as you walk. Low, so each band is wide enough
/// to feel like a region rather than a stripe.
const BIOME_FREQUENCY: f32 = 0.004;

/// Octaves in the biome field. Few, so boundaries stay smooth.
const BIOME_OCTAVES: u32 = 2;

/// Keeps the biome field independent of terrain height and caves.
const BIOME_SALT: u64 = 0xB10E_1234_B10E_5678;

/// Thresholds carving the noise range into three bands.
const TUNDRA_BELOW: f32 = 0.38;
const DESERT_ABOVE: f32 = 0.62;

/// A surface region.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash, PartialOrd, Ord)]
pub enum Biome {
    Tundra,
    Plains,
    Desert,
}

impl Biome {
    /// The tile capping the ground in this biome.
    pub fn surface_tile(self) -> Tile {
        match self {
            Biome::Tundra => Tile::Snow,
            Biome::Plains => Tile::Grass,
            Biome::Desert => Tile::Sand,
        }
    }

    /// The tile filling the soil layer beneath the surface.
    pub fn soil_tile(self) -> Tile {
        match self {
            // Sand runs deep; snow is a thin cap over ordinary soil.
            Biome::Desert => Tile::Sand,
            Biome::Tundra | Biome::Plains => Tile::Dirt,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Biome::Tundra => "Tundra",
            Biome::Plains => "Plains",
            Biome::Desert => "Desert",
        }
    }
}

/// Which biome covers column `x`.
pub fn biome_at(seed: u64, x: usize) -> Biome {
    let field = fbm_1d(
        seed ^ BIOME_SALT,
        x as f32 * BIOME_FREQUENCY,
        BIOME_OCTAVES,
    );

    if field < TUNDRA_BELOW {
        Biome::Tundra
    } else if field > DESERT_ABOVE {
        Biome::Desert
    } else {
        Biome::Plains
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;

    const SEED: u64 = 7;

    #[test]
    fn biome_choice_is_deterministic() {
        for x in 0..200 {
            assert_eq!(biome_at(SEED, x), biome_at(SEED, x), "column {x} changed");
        }
    }

    #[test]
    fn a_wide_world_contains_every_biome() {
        let seen: BTreeSet<Biome> = (0..4000).map(|x| biome_at(SEED, x)).collect();

        assert_eq!(
            seen.len(),
            3,
            "a long walk should cross all three biomes, saw {seen:?}"
        );
    }

    #[test]
    fn biomes_form_wide_bands_rather_than_flickering() {
        let mut changes = 0;
        let mut previous = biome_at(SEED, 0);

        for x in 1..2000 {
            let current = biome_at(SEED, x);
            if current != previous {
                changes += 1;
                previous = current;
            }
        }

        assert!(
            changes > 0,
            "the world should not be one biome for 2000 tiles"
        );
        assert!(
            changes < 40,
            "biomes should be broad bands, but changed {changes} times in 2000 tiles"
        );
    }

    #[test]
    fn a_biome_band_is_never_a_single_column() {
        let mut run_start = 0usize;
        let mut previous = biome_at(SEED, 0);

        for x in 1..2000 {
            let current = biome_at(SEED, x);
            if current != previous {
                assert!(
                    x - run_start >= 4,
                    "{previous:?} lasted only {} columns from {run_start}",
                    x - run_start
                );
                run_start = x;
                previous = current;
            }
        }
    }

    #[test]
    fn different_seeds_lay_biomes_out_differently() {
        let one: Vec<Biome> = (0..1000).map(|x| biome_at(1, x)).collect();
        let two: Vec<Biome> = (0..1000).map(|x| biome_at(2, x)).collect();

        assert_ne!(one, two, "the biome map should depend on the seed");
    }

    #[test]
    fn each_biome_has_its_own_surface_material() {
        assert_eq!(Biome::Plains.surface_tile(), Tile::Grass);
        assert_eq!(Biome::Desert.surface_tile(), Tile::Sand);
        assert_eq!(Biome::Tundra.surface_tile(), Tile::Snow);
    }

    #[test]
    fn desert_sand_runs_deeper_than_a_snow_cap() {
        assert_eq!(Biome::Desert.soil_tile(), Tile::Sand);
        assert_eq!(
            Biome::Tundra.soil_tile(),
            Tile::Dirt,
            "snow should be a thin cap over ordinary soil"
        );
    }
}
