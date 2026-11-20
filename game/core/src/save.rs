//! Save files: a versioned, run-length-encoded snapshot of a game.
//!
//! The format is written by hand rather than through a serialisation crate,
//! so the on-disk layout is explicit and every field's size is visible.

use crate::item::{Inventory, ItemId, Stack, ITEMS};
use crate::quest::QuestLog;
use crate::world::{Tile, World};

/// File magic, so a wrong file is rejected rather than misread.
pub const MAGIC: &[u8; 4] = b"DDLV";

/// Current layout version.
///
/// Version 2 appended the quest log. Version 1 files still load; their
/// quests simply come back empty.
pub const SAVE_VERSION: u32 = 2;

/// First version that carries quest progress.
const FIRST_VERSION_WITH_QUESTS: u32 = 2;

/// Marks an empty inventory slot in the slot table.
const EMPTY_SLOT: u16 = u16::MAX;

/// Everything needed to resume a game.
#[derive(Clone, Debug, PartialEq)]
pub struct SaveGame {
    pub seed: u64,
    pub world: World,
    pub player: PlayerSave,
    /// Seconds into the day-night cycle.
    pub time_of_day: f32,
    pub quests: QuestLog,
}

/// The player's own state.
#[derive(Clone, Debug, PartialEq)]
pub struct PlayerSave {
    pub x: f32,
    pub y: f32,
    pub health: f32,
    pub hotbar_slot: u32,
    pub inventory: Inventory,
}

/// Why a save file could not be read.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum LoadError {
    /// Not a Deepdelve save at all.
    BadMagic,
    /// Written by a newer version of the game.
    FutureVersion(u32),
    /// The file ends in the middle of a field.
    Truncated,
    /// A tile or item id that this build does not know.
    UnknownId,
    /// Header values that do not describe a sane world.
    Corrupt,
}

/// Longest run the encoder emits in one block, bounded by the count field.
const MAX_RUN: usize = u16::MAX as usize;

/// Refuses obviously bogus headers before allocating anything from them.
const MAX_WORLD_TILES: u64 = 16_000_000;

/// Upper bound on stored quest entries, so a corrupt count cannot ask for
/// an enormous allocation.
const MAX_QUEST_ENTRIES: usize = 4096;

/// Serialise a game to bytes.
pub fn save(game: &SaveGame) -> Vec<u8> {
    let mut out = Vec::new();

    out.extend_from_slice(MAGIC);
    out.extend_from_slice(&SAVE_VERSION.to_le_bytes());
    out.extend_from_slice(&game.seed.to_le_bytes());

    let width = game.world.width();
    let height = game.world.height();
    out.extend_from_slice(&(width as u32).to_le_bytes());
    out.extend_from_slice(&(height as u32).to_le_bytes());

    // Run-length encode the tile grid in row-major order. Worlds are mostly
    // long stretches of one material, so this is a large saving.
    let mut run_tile = game.world.tile(0, 0);
    let mut run_length = 0usize;

    let flush = |out: &mut Vec<u8>, tile: Tile, length: usize| {
        let mut remaining = length;
        while remaining > 0 {
            let block = remaining.min(MAX_RUN);
            out.push(tile.to_id());
            out.extend_from_slice(&(block as u16).to_le_bytes());
            remaining -= block;
        }
    };

    for y in 0..height {
        for x in 0..width {
            let tile = game.world.tile(x, y);

            if tile == run_tile && run_length < MAX_RUN {
                run_length += 1;
            } else {
                flush(&mut out, run_tile, run_length);
                run_tile = tile;
                run_length = 1;
            }
        }
    }
    flush(&mut out, run_tile, run_length);

    out.extend_from_slice(&game.player.x.to_le_bytes());
    out.extend_from_slice(&game.player.y.to_le_bytes());
    out.extend_from_slice(&game.player.health.to_le_bytes());
    out.extend_from_slice(&game.player.hotbar_slot.to_le_bytes());

    let slot_count = game.player.inventory.slot_count();
    out.extend_from_slice(&(slot_count as u32).to_le_bytes());

    for index in 0..slot_count {
        match game.player.inventory.slot(index) {
            Some(stack) => {
                out.extend_from_slice(&stack.item.0.to_le_bytes());
                out.extend_from_slice(&stack.count.to_le_bytes());
            }
            None => {
                out.extend_from_slice(&EMPTY_SLOT.to_le_bytes());
                out.extend_from_slice(&0u32.to_le_bytes());
            }
        }
    }

    out.extend_from_slice(&game.time_of_day.to_le_bytes());

    // Version 2 onward: the quest log.
    let (progress, claimed, deepest) = game.quests.snapshot();
    out.extend_from_slice(&(progress.len() as u32).to_le_bytes());
    for value in progress {
        out.extend_from_slice(&value.to_le_bytes());
    }
    out.extend_from_slice(&(claimed.len() as u32).to_le_bytes());
    for &value in claimed {
        out.push(u8::from(value));
    }
    out.extend_from_slice(&deepest.to_le_bytes());

    out
}

/// Sequential reader that refuses to run off the end of the buffer.
struct Reader<'a> {
    bytes: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    fn take(&mut self, count: usize) -> Result<&'a [u8], LoadError> {
        let end = self
            .position
            .checked_add(count)
            .ok_or(LoadError::Truncated)?;

        if end > self.bytes.len() {
            return Err(LoadError::Truncated);
        }

        let slice = &self.bytes[self.position..end];
        self.position = end;
        Ok(slice)
    }

    fn u8(&mut self) -> Result<u8, LoadError> {
        Ok(self.take(1)?[0])
    }

    fn u16(&mut self) -> Result<u16, LoadError> {
        Ok(u16::from_le_bytes(self.take(2)?.try_into().unwrap()))
    }

    fn u32(&mut self) -> Result<u32, LoadError> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().unwrap()))
    }

    fn u64(&mut self) -> Result<u64, LoadError> {
        Ok(u64::from_le_bytes(self.take(8)?.try_into().unwrap()))
    }

    fn f32(&mut self) -> Result<f32, LoadError> {
        Ok(f32::from_le_bytes(self.take(4)?.try_into().unwrap()))
    }
}

/// Parse bytes produced by [`save`].
pub fn load(bytes: &[u8]) -> Result<SaveGame, LoadError> {
    if bytes.len() < MAGIC.len() || &bytes[..MAGIC.len()] != MAGIC {
        return Err(LoadError::BadMagic);
    }

    let mut reader = Reader {
        bytes,
        position: MAGIC.len(),
    };

    let version = reader.u32()?;
    if version > SAVE_VERSION {
        return Err(LoadError::FutureVersion(version));
    }

    let seed = reader.u64()?;
    let width = reader.u32()? as usize;
    let height = reader.u32()? as usize;

    // Validate before allocating, so a corrupt header cannot ask for a
    // terabyte of tiles.
    let total = (width as u64)
        .checked_mul(height as u64)
        .ok_or(LoadError::Corrupt)?;
    if width == 0 || height == 0 || total > MAX_WORLD_TILES {
        return Err(LoadError::Corrupt);
    }

    let mut tiles = Vec::with_capacity(total as usize);
    while tiles.len() < total as usize {
        let tile = Tile::from_id(reader.u8()?).ok_or(LoadError::UnknownId)?;
        let run = reader.u16()? as usize;

        if run == 0 || tiles.len() + run > total as usize {
            return Err(LoadError::Corrupt);
        }

        tiles.extend(std::iter::repeat_n(tile, run));
    }

    let x = reader.f32()?;
    let y = reader.f32()?;
    let health = reader.f32()?;
    let hotbar_slot = reader.u32()?;

    let slot_count = reader.u32()? as usize;
    if slot_count > MAX_WORLD_TILES as usize {
        return Err(LoadError::Corrupt);
    }

    let mut inventory = Inventory::new(slot_count);
    for index in 0..slot_count {
        let item = reader.u16()?;
        let count = reader.u32()?;

        if item == EMPTY_SLOT {
            continue;
        }

        if item as usize >= ITEMS.len() {
            return Err(LoadError::UnknownId);
        }

        inventory.set_slot(
            index,
            Some(Stack {
                item: ItemId(item),
                count,
            }),
        );
    }

    let time_of_day = reader.f32()?;

    // Quests arrived in version 2. Older files load with an empty log
    // rather than being rejected.
    let quests = if version >= FIRST_VERSION_WITH_QUESTS {
        let progress_len = reader.u32()? as usize;
        if progress_len > MAX_QUEST_ENTRIES {
            return Err(LoadError::Corrupt);
        }
        let mut progress = Vec::with_capacity(progress_len);
        for _ in 0..progress_len {
            progress.push(reader.u32()?);
        }

        let claimed_len = reader.u32()? as usize;
        if claimed_len > MAX_QUEST_ENTRIES {
            return Err(LoadError::Corrupt);
        }
        let mut claimed = Vec::with_capacity(claimed_len);
        for _ in 0..claimed_len {
            claimed.push(reader.u8()? != 0);
        }

        let deepest = reader.f32()?;

        QuestLog::restore(&progress, &claimed, deepest)
    } else {
        QuestLog::new()
    };

    Ok(SaveGame {
        seed,
        world: World::from_tiles(width, height, tiles),
        player: PlayerSave {
            x,
            y,
            health,
            hotbar_slot,
            inventory,
        },
        time_of_day,
        quests,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::item::{COPPER_ORE, IRON_PICKAXE, STONE};

    fn sample_game() -> SaveGame {
        let world = World::generate(99, 64, 64);

        let mut inventory = Inventory::new(12);
        inventory.add(STONE, 137);
        inventory.add(COPPER_ORE, 4);
        inventory.add(IRON_PICKAXE, 1);

        SaveGame {
            seed: 99,
            world,
            player: PlayerSave {
                x: 31.5,
                y: 20.0,
                health: 73.5,
                hotbar_slot: 2,
                inventory,
            },
            time_of_day: 123.25,
            quests: QuestLog::new(),
        }
    }

    #[test]
    fn a_saved_game_reloads_identically() {
        let original = sample_game();

        let reloaded = load(&save(&original)).expect("round trip should succeed");

        assert_eq!(reloaded, original);
    }

    #[test]
    fn every_tile_survives_the_round_trip() {
        let original = sample_game();

        let reloaded = load(&save(&original)).expect("round trip");

        for y in 0..original.world.height() {
            for x in 0..original.world.width() {
                assert_eq!(
                    reloaded.world.tile(x, y),
                    original.world.tile(x, y),
                    "tile ({x}, {y}) changed"
                );
            }
        }
    }

    #[test]
    fn the_inventory_survives_the_round_trip() {
        let original = sample_game();

        let reloaded = load(&save(&original)).expect("round trip");

        assert_eq!(reloaded.player.inventory.count(STONE), 137);
        assert_eq!(reloaded.player.inventory.count(COPPER_ORE), 4);
        assert_eq!(reloaded.player.inventory.count(IRON_PICKAXE), 1);
    }

    #[test]
    fn stack_layout_is_preserved_not_merely_the_totals() {
        let mut inventory = Inventory::new(6);
        // Deliberately leave slot 0 holding a partial stack and slot 2 empty.
        inventory.add(STONE, 5);
        inventory.add(IRON_PICKAXE, 1);

        let mut game = sample_game();
        game.player.inventory = inventory.clone();

        let reloaded = load(&save(&game)).expect("round trip");

        for slot in 0..inventory.slot_count() {
            assert_eq!(
                reloaded.player.inventory.slot(slot),
                inventory.slot(slot),
                "slot {slot} differs"
            );
        }
    }

    #[test]
    fn player_position_and_health_survive_exactly() {
        let original = sample_game();

        let reloaded = load(&save(&original)).expect("round trip");

        assert_eq!(reloaded.player.x, 31.5);
        assert_eq!(reloaded.player.y, 20.0);
        assert_eq!(reloaded.player.health, 73.5);
        assert_eq!(reloaded.player.hotbar_slot, 2);
        assert_eq!(reloaded.time_of_day, 123.25);
    }

    #[test]
    fn a_uniform_world_compresses_to_a_fraction_of_its_tiles() {
        let world = World::from_tiles(256, 256, vec![Tile::Stone; 256 * 256]);
        let game = SaveGame {
            seed: 1,
            world,
            player: PlayerSave {
                x: 0.0,
                y: 0.0,
                health: 1.0,
                hotbar_slot: 0,
                inventory: Inventory::new(1),
            },
            time_of_day: 0.0,
            quests: QuestLog::new(),
        };

        let encoded = save(&game);

        assert!(
            encoded.len() < 1024,
            "65536 identical tiles should run-length encode small, got {} bytes",
            encoded.len()
        );
    }

    #[test]
    fn a_varied_world_still_round_trips_through_the_encoding() {
        // Alternating tiles are the worst case for run-length encoding.
        let tiles: Vec<Tile> = (0..64 * 64)
            .map(|i| if i % 2 == 0 { Tile::Stone } else { Tile::Air })
            .collect();
        let world = World::from_tiles(64, 64, tiles);

        let mut game = sample_game();
        game.world = world;

        let reloaded = load(&save(&game)).expect("round trip");

        assert_eq!(reloaded.world, game.world);
    }

    #[test]
    fn a_run_longer_than_one_encoded_block_is_split_correctly() {
        // Longer than u16::MAX, so the encoder must break the run up.
        let wide = 400usize;
        let tall = 400usize;
        let world = World::from_tiles(wide, tall, vec![Tile::Dirt; wide * tall]);

        let mut game = sample_game();
        game.world = world;

        let reloaded = load(&save(&game)).expect("round trip");

        assert_eq!(reloaded.world.tile(0, 0), Tile::Dirt);
        assert_eq!(reloaded.world.tile(wide - 1, tall - 1), Tile::Dirt);
        assert_eq!(reloaded.world, game.world);
    }

    #[test]
    fn quest_progress_survives_a_save_and_reload() {
        let mut game = sample_game();

        let mut log = QuestLog::new();
        for _ in 0..crate::quest::QUESTS[0].objective.required() {
            log.record(crate::quest::QuestEvent::Mined(Tile::Dirt));
        }
        log.claim(0, &mut game.player.inventory);
        log.record(crate::quest::QuestEvent::DepthReached(0.73));
        game.quests = log;

        let reloaded = load(&save(&game)).expect("round trip");

        assert!(reloaded.quests.is_complete(0), "finished quest came back undone");
        assert!(reloaded.quests.is_claimed(0), "reward would be paid twice");
        assert!(
            reloaded.quests.is_complete(6),
            "the deepest point reached should survive a reload"
        );
    }

    #[test]
    fn a_save_from_before_quests_existed_still_loads() {
        // Version 1 files have no quest section. They must load with an
        // empty log rather than being rejected or misread.
        let game = sample_game();
        let mut bytes = save(&game);

        // Strip the quest section and relabel as version 1.
        let quest_bytes = {
            let (progress, claimed, _) = game.quests.snapshot();
            4 + progress.len() * 4 + 4 + claimed.len() + 4
        };
        bytes.truncate(bytes.len() - quest_bytes);
        bytes[4..8].copy_from_slice(&1u32.to_le_bytes());

        let reloaded = load(&bytes).expect("a version 1 save should still load");

        assert_eq!(reloaded.player.health, game.player.health);
        assert_eq!(reloaded.quests, QuestLog::new(), "quests start fresh");
    }

    #[test]
    fn a_truncated_quest_section_is_refused_rather_than_guessed_at() {
        let bytes = save(&sample_game());

        // Cut into the middle of the quest data.
        let result = load(&bytes[..bytes.len() - 6]);

        assert!(result.is_err(), "a half-written quest log must not load");
    }

    #[test]
    fn a_file_that_is_not_a_save_is_rejected() {
        assert_eq!(load(b"not a save file at all"), Err(LoadError::BadMagic));
    }

    #[test]
    fn an_empty_file_is_rejected_without_panicking() {
        assert_eq!(load(&[]), Err(LoadError::BadMagic));
    }

    #[test]
    fn a_save_from_a_newer_game_is_refused() {
        let mut encoded = save(&sample_game());
        // Overwrite the version field, just past the magic.
        encoded[4..8].copy_from_slice(&(SAVE_VERSION + 7).to_le_bytes());

        assert_eq!(
            load(&encoded),
            Err(LoadError::FutureVersion(SAVE_VERSION + 7))
        );
    }

    #[test]
    fn a_truncated_save_is_refused_without_panicking() {
        let encoded = save(&sample_game());

        for cut in [8, 16, 32, encoded.len() / 2, encoded.len() - 1] {
            let result = load(&encoded[..cut]);

            assert!(
                result.is_err(),
                "truncating to {cut} bytes should fail, not load"
            );
        }
    }

    #[test]
    fn an_unknown_tile_id_is_refused() {
        let mut encoded = save(&sample_game());
        // The tile table begins after magic, version, seed, width, height.
        let tile_data_start = 4 + 4 + 8 + 4 + 4;
        encoded[tile_data_start] = 200;

        assert_eq!(load(&encoded), Err(LoadError::UnknownId));
    }

    #[test]
    fn an_absurd_world_size_is_refused_rather_than_allocated() {
        let mut encoded = save(&sample_game());
        encoded[16..20].copy_from_slice(&u32::MAX.to_le_bytes());

        assert!(
            matches!(load(&encoded), Err(LoadError::Corrupt | LoadError::Truncated)),
            "a gigantic width must be refused"
        );
    }

    #[test]
    fn every_item_in_the_registry_can_be_stored_and_recovered() {
        let mut inventory = Inventory::new(ITEMS.len());
        for index in 0..ITEMS.len() {
            inventory.add(ItemId(index as u16), 1);
        }

        let mut game = sample_game();
        game.player.inventory = inventory.clone();

        let reloaded = load(&save(&game)).expect("round trip");

        for index in 0..ITEMS.len() {
            assert_eq!(
                reloaded.player.inventory.count(ItemId(index as u16)),
                1,
                "item {index} did not survive"
            );
        }
    }

    #[test]
    fn an_empty_slot_stays_empty_after_reloading() {
        let mut inventory = Inventory::new(4);
        inventory.add(STONE, 1);
        inventory.remove(STONE, 1);

        let mut game = sample_game();
        game.player.inventory = inventory;

        let reloaded = load(&save(&game)).expect("round trip");

        assert_eq!(reloaded.player.inventory.slot(0), None);
        assert_eq!(reloaded.player.inventory.slot_count(), 4);
    }

    #[test]
    fn a_stack_is_recovered_whole() {
        let mut inventory = Inventory::new(4);
        inventory.add(STONE, 42);

        let mut game = sample_game();
        game.player.inventory = inventory;

        let reloaded = load(&save(&game)).expect("round trip");

        assert_eq!(
            reloaded.player.inventory.slot(0),
            Some(Stack {
                item: STONE,
                count: 42
            })
        );
    }
}
