# Progress report — Lanternbound

Branch `ccr-60ac94c6-dyqxhw`. Engine: Godot 4.4.1, GL Compatibility renderer, Android-first.
Read **DESIGN.md** first: it sets the game's direction (light as weapon and key, vaults,
relics, the Dark Tide, regions).

## Where things stand (tests: 103 pass)

### This session's big changes (from `6c194f2`)

| Change | What it is | How verified |
|---|---|---|
| **Real 3D characters** | `Body3D`: KayKit (CC0) rigged models, each filmed side-on by its own orthographic camera into a SubViewport and shown on a sprite at its feet. Truly side-facing; turns by rotating round through the camera; 19-21 skeletal clips (idle/walk/run/jump/chop/slash/block/dodge/hit/death/cast...), gait speed matched to ground speed; items on the `handslot.r` bone (KayKit 3D weapons, else the item picture on a camera-facing card gripped at its handle). Off-screen bodies stop rendering and animating; enemies render at 1x without MSAA. Setting `characters_3d` falls back to the old cut-out rig | Tests (hand-bone parenting, turn, footsteps), filmstrips of dig/chop/slash/torch/walk |
| Cast | Player = hooded wanderer (Rogue_Hooded), Wren = Mage, Bram = Barbarian, Tobin = Barbarian palette-swapped, Mira = Rogue palette-swapped, **Sir Aldous** = Knight (new). Undead: zombie/robot/shade/Warden/Gloam are KayKit skeletons with bone weapons; ordinary dead claw out of the ground on spawn | Cast preview (`tools/preview_cast.gd`), captures |
| Portraits | Rendered from the models (`tools/render_portraits.gd`) | Dialogue capture |
| **Flare** | Star button / Q: 25 glow; burns the dead, staggers the living, lights braziers within 3.5 tiles, wakes light-runes | Test, capture |
| **Sealed vaults** (6/world) | Brick room behind an unbreakable rune-stone door; antechamber with 3 cold braziers (one on a ledge); lit all = door opens on a gilded relic chest that bursts its loot | Test (layout, opening, chest), capture |
| **Hidden caches** (12/world) | Chest sealed in rock behind a cave wall, marked by a light-rune visible only after a flare (or with the Seer's Eye) | Test |
| **Relics** (8, 3 slots) | Featherbone (air jump), Ember Heart (ignite), Deepsong (ore glints), Moth Lantern (glow regrows), Bulwark (-25% harm), Swiftroot (+18% speed), Seer's Eye (runes, double map reveal), Luckstone (richer loot). Wear/take off in the pack panel; row under the vitals; saved | Test |
| **Dark Tide** | 2nd night, then ~1 in 3: sky turns violet-red, the dead rise around the player (max 5) except within 8 tiles of a lit light; extra glowshards; dawn refills the lantern | Test, capture |
| Sir Aldous's quests | "The Lightwardens' Vaults" (open a vault, wear a relic) then "The Hidden Marks" (find 2 caches); voiced | Quest tests driven by real vault/relic/cache events |
| Tobin trades | Old Coins (vaults, caches) buy torches, food, flasks, ore, wardstones, iron tools, heart crystals | Test |
| Cave near layer | Dark stalactite/stalagmite silhouettes at 1.5x parallax framing caves (2.5D depth) | Captures |
| Model size | `tools/slim_glb.py` keeps only used clips: characters 33 MB -> 11 MB | Cast preview, tests |

### Earlier (still true)
Trees chop in stages and break into log chunks; mining debris per material; hit-stop; hammers;
footsteps per surface; minimap with saved fog of war; spitters; cave dressing; 5 main + 5 side
quests; tutorial bot; save/load; weather and thunderstorms; foliage shader; light map.

## Not verified / not done

- **No real device** has run the game; no APK built. 3D characters each render their own
  SubViewport: fine in software rendering here, but **phone performance is unmeasured**.
- **Audio is unheard** (no sound device): checked by length/loudness only.
- Tutorial bot: was 3/3 before the 3D characters; re-run after making vault/cache generation
  use its own random stream (it had reshuffled the meadow). Check the latest run's result.
- Regions are still the original five biomes; DESIGN.md's region table is the target.
- No fishing, farming, pets, mounts, armour, enchanting yet.

## Next tasks (in order)

1. Confirm the tutorial bot passes again; fix whatever it finds.
2. Boss fights as adventures: give the Warden and Gloam multi-phase patterns with the new
   skeleton clips (taunt, spin, summon via Spawn_Ground_Skeletons), and arenas in vaults.
3. A region with its own identity (e.g. Drowned Halls: underground lake ruins), using
   KayKit dungeon props and a new enemy.
4. Fishing in pools (the item art exists: fish, fishingPole), cooking recipes with buffs.
5. Treasure maps (a chest find that marks an unopened vault on the minimap).
6. Phone build and real-device performance check of Body3D.

## How to check things

- Tests: `godot --headless --path godot -s res://tests/run_tests.gd [-- name_filter]`
- New `class_name` scripts need `godot --headless --path godot --import` once.
- Captures: `xvfb-run -a -s "-screen 0 2340x1080x24" godot --path godot --rendering-driver opengl3 --resolution 2340x1080 --fixed-fps 60 -- --shot=out.png --touch --frames=N`
  plus `--scenario=cave|crystal|deep|ruin|vault|vault_open|...`, `--action=dig|chop|attack|walk|flare|tutorial|soak|...`,
  `--hold=item`, `--wear=relic_a,relic_b`, `--tide`, `--spawn=kinds`, `--boss=warden`, `--x=s-30`, `--strip=N --every=K`.
- Tools: `tools/preview_cast.gd`, `tools/preview_body.gd`, `tools/render_portraits.gd`,
  `tools/render_props.gd -- dungeon`, `tools/kaykit_palette.py`, `tools/slim_glb.py`,
  `tools/draw_relics.py`, `tools/bake_voices.py`.
- Software rendering is slow with several 3D bodies: keep captures short or use 1170x540.
