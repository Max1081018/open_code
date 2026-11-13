# RustMod Forge — target engine research

Everything RustMod Forge generates is based on the sources below, read on 2026-11-13. Nothing in the
generators uses an API that is not in these sources. Where a fact was read but not exercised in a running
game, it is marked **(not runtime-verified)**.

| Source | Revision | What it is |
| --- | --- | --- |
| `github.com/horizon-rust/horizon` | `6c4c0347f9926e3b1d5994e7fb8b1ba5e68ddf70` (2026-11-13) | Upstream engine, desktop launcher, native-mod toolchain |
| `github.com/RxLauncherTeam/RxLauncher-Rust-Edition` | `150a414b09a18c900489d9462a7fc035dae744b7` (2026-11-04) | "Horizon Android": the Android port and its launcher |
| horizon-mixins pin used by the upstream launcher | `5a64af938ec86b00d53d16a408aabc0038fb3e57` (`launcher/src/native_mods.rs`, `MIXINS_REV`) | Native bundle applier |
| `playhorizon.dev/docs` | not reachable from the build environment (proxy refused) | The same documents live in `docs/` of both repositories, which is what was read |

Minecraft version for both: **Java 26.3** (`research-lock.json`).

## 1. What a `.hmod` contains

`docs/api/mod-files.md`, `crates/horizon-mods/src/manifest.rs`:

- A zip (stored or deflate only). Paths relative, `/`-separated, no `..`, `.`, empty parts, `\` or `:`; each path once.
- `horizon-mod.toml` (manifest) + `assets/` + `data/`. Content paths are `assets/` or `data/`, then at least two
  parts of `[a-z0-9_.-]`.
- Manifest keys (unknown keys are **refused**): `id` (`[a-z0-9_]{1,64}`), `name`, `version`, `description`,
  `authors`, `api`, `side` (`client` default, `server`, `both`), `capabilities`, `namespaces`, and on the Android
  fork `experimental`.
- Limits: 65,536 content files, 16 MiB each, 512 MiB in total. Android import: 256 MiB input, 32,768 entries,
  1,024-byte entry paths.
- `minecraft`, `c`, `horizon` cannot be claimed as namespaces; a mod may only add **tags** under `data/minecraft/`
  and `data/c/`, and atlas sources under `assets/minecraft/atlases/`.

### Content mods (API 0.2, capability `registries`)

Declared under `data/<id>/horizon/`:

| Folder | What | Template rule |
| --- | --- | --- |
| `block/*.json` | blocks | `template` = a vanilla block; `properties` (`hardness`, `light`, `sounds`), `state_properties`, `shapes`, … |
| `item/*.json` | items | `template` = vanilla item; `max_stack_size`, `rarity`, `components` (26.3 data components) |
| `entity_type/*.json` | entity types | `minecraft:snowball` (thrown, with `item`, `damage`) **or a living template: `minecraft:zombie`, `minecraft:villager`, `minecraft:wandering_trader`**, with `attributes` overrides only for attributes the template has |
| `mob_effect/*.json` | effects | `category`, `color` — no tick behaviour |
| `fluid/*.json`, `menu/*.json`, `creative_tab/*.json` | fluids, menus, tabs | see `docs/mods.md` |

Living types keep **their template's model, texture, sounds and goals** ("Not yet as data: its own model or texture
… and its own goals"). Loot table is `<id>:entities/<name>`.

Also read from a content mod: textures, models, item model definitions, `sounds.json` + `.ogg`, languages, recipes,
tags, loot tables, advancements, **functions**, damage types, worldgen, structures and NeoForge/Forge biome modifiers
(`add_features`, `remove_features`, `add_spawns`, `remove_spawns`, `add_spawn_costs`, `remove_spawn_costs`).

### Functions

`docs/mod-browser.md`: "Horizon runs a data pack's functions, function tags, predicates and item modifiers".
`crates/horizon-client/src/game/functions.rs` runs `#minecraft:load` once and `#minecraft:tick` every tick at
permission level 2. The resource root built from the content mods is the built-in data pack, and `docs/mods.md`
lists functions among the content a mod switch reloads. RustMod Forge's Android behaviour backend relies on this
**(not runtime-verified)**.

## 2. Native mods (`.hnmod`) — upstream desktop only

`docs/native-mods.md`, `docs/api/mod-files.md`:

- A zip with `horizon-native.json` (`schema` 1, `id`, `version`, `game` "26.3", `horizon` 40-hex commit, `mixins`
  40-hex commit, optional `hooks`) and `mixins/<id>/horizon-mixin.toml` plus `.rs`/`.toml` files, `data/`, licences.
  At most 512 entries and 64 MiB unpacked.
- It is **source code**: the desktop launcher compiles the whole game with it (`horizon-launcher native-build`).
- A trait mod declares `[api] path = "api"`; the crate depends on `horizon-client` and exports
  `pub fn hooks() -> Box<dyn horizon_client::mod_api::Hooks>`. The `Hooks` trait is generated at build time from
  `native-hooks.json` (434 hook points at the read revision; `NATIVE_HOOKS_API = 415`): method `fn <name>(&self,
  [host,] event: &mut <Name>Event<'_>)`, returning `Flow` for cancellable hooks.
- Relevant to entity reconstruction: `register_goals` (vanilla `registerGoals`; `horizon_client::mobs::goals`
  with `Float`, `Stroll::new(speed)`, `LookAtPlayer::new(range)`, `MeleeAttack::new(speed, follow_unseen)`,
  `NearestTarget::new(Prey::Player, must_see)`, `HurtByTarget::new()`, `LeapAtTarget::new(yd)`, …), custom
  `Goal` impls (`flags/can_use/can_continue/start/tick/stop/box_clone`, with `Mob` fields such as `position`,
  `removed`, `invisible`, and `MobWorld` fields `nearest_player`, `player.look`, `day_time`, `daylight`),
  `layer_definitions` (vanilla `LayerDefinition` / `CubeListBuilder` / `PartPose`), `mob_submit` (draw a mob
  yourself), `entity_tick_pre`, `living_incoming_damage`, `camera_shake`, `play_local_sound`.
- Trait-mod `Host` helpers are only the catalog's `helpers` list. `native_spawn_mob`, `native_bake_layer`,
  `native_has_line_of_sight` exist in the source but are not catalog helpers at this revision, so only a pinned
  mixin helper (which compiles inside `crate::game`) can call them.

## 3. The Android port (Horizon Android, `dev.horizon.android`)

`README.md`, `docs/android-content.md`, `docs/android-features.md`, `crates/horizon-mods/src/manifest.rs`,
`crates/horizon-mod-sdk/wit/horizon.wit`:

- **Imports sandboxed `.hmod` only.** "Source-only `.hnmod` mods require a separately compiled client and are not
  supported on Android yet." Java `.jar` mods are refused.
- The Android fork still runs **WebAssembly `.hmod` code** (Wasmtime, 64-bit APKs only): `mod.wasm` (a WIT component
  of `horizon:mods@0.1.0`) beside the manifest. API lines: `0.1` (code), `0.2` (0.1 + content, `registries`),
  `0.3` (server mods, `side = "server"`, capabilities `players`, `world`, `storage`).
- WASM capabilities: `game-read` (local player position/health, clock, raycast), `chat`, `hud`, `storage`,
  `command` (vanilla commands **as the player, with the player's permissions** — needs cheats in single player),
  experimental `ui`, `render` (HUD shapes, **camera shake**, zoom), `input`, `recipes`. Server: `players`, `world`
  (block get/set). **There is no entity, mob, AI or model API in the WASM interface.**
- Import paths: the launcher's **Mods → Import file** (validated, recommended), HTTPS link import, or its
  `DocumentsProvider` (authority `dev.horizon.android.documents`) which appears as "Horizon Android" in the system
  Files picker with a **Mods** folder. No import intent or file association exists, so RustMod Forge uses the
  Storage Access Framework: the user picks the Horizon Android Mods folder once (or any folder) and the export is
  written there.

## 4. Consequences for reconstruction

| Java mod feature | Android (Horizon Android) | Upstream desktop (native build) |
| --- | --- | --- |
| Textures, sounds, lang, recipes, loot, tags, advancements, worldgen, biome modifiers | `.hmod` content | `.hmod` content |
| Simple blocks/items | `.hmod` templates | `.hmod` templates |
| Custom mob type, attributes | `.hmod` living template (zombie / wandering trader) | same + `register_goals` |
| Custom model + animation | display-entity rig driven by functions (item models per bone, `item_display` transformations) **(not runtime-verified)** | `layer_definitions` + `mob_submit` |
| Custom AI (stalk, vanish, watch, line-of-sight) | function-based state machine | Rust `Goal` impls |
| Camera shake / screen effects | only from a WASM client mod (`render.shake`, experimental) or `title` overlays | `camera_shake` hook |
| Mixins, ASM transformers, custom renderers, GUI screens | unsupported, reported | partly (hooks), reported |
| Arbitrary Java code | never executed; reported | never executed; reported |

The Man From The Fog, or any mod, is therefore reconstructed per feature, and the report says for every feature
which of these routes was used and why.
