//! Bevy frontend for Deepdelve.
//!
//! Deliberately thin: this layer draws what `deepdelve-core` decides and
//! feeds input into it. No game rules live here.
//!
//! One world unit is one screen pixel, and one tile is `TILE_SCREEN_PX`
//! units, so the default 2-D camera already frames roughly 24 tiles across a
//! landscape phone with no custom projection.

use std::collections::HashSet;

use bevy::prelude::*;
use bevy::asset::RenderAssetUsages;
use bevy::image::ImageSampler;
use bevy::render::render_resource::{Extent3d, TextureDimension, TextureFormat};
use bevy::render::view::screenshot::{save_to_disk, Screenshot};
use bevy::window::WindowResolution;

use deepdelve_core::art::Texture;
use deepdelve_core::daynight::{TimeOfDay, DAY_LENGTH};
use deepdelve_core::enemy::{bodies_overlap, chase_intent, kind, Combat, Enemy, EnemyKindId};
use deepdelve_core::spawn::{choose_kind, find_standing_spot};
use deepdelve_core::sprite::{
    boss_style, character_frame, enemy_height_tiles, enemy_style, player_style, CharacterStyle,
    CHAR_H, CHAR_W,
};
use deepdelve_core::touch::{Controls, Zone};
use deepdelve_core::interact::{can_reach, place, MiningState};
use deepdelve_core::boss::{
    boss_intent, kind as boss_kind_of, summoned_by as boss_summoned_by, Attack as BossAttack, Boss,
};
use deepdelve_core::anim::{clip, state_from_motion, AnimState, Animator, ALL_STATES};
use deepdelve_core::biome::biome_at;
use deepdelve_core::craft::{available, craft, Station};
use deepdelve_core::decor::{
    cave_prop, prop_glow, prop_size_tiles, prop_texture, surface_prop, Prop, ALL_PROPS,
    PROP_VARIANTS,
};
use deepdelve_core::light::{compute_sky_light, LightMap};
use deepdelve_core::save::{load, save, PlayerSave, SaveGame};
use deepdelve_core::noise::hash01;
use deepdelve_core::item::{def, drop_from, Inventory, ItemId, ItemKind};
use deepdelve_core::physics::{Body, Intent};
use deepdelve_core::tilemap::{chunk_texture, TileAtlas, CHUNK_TILES};
use deepdelve_core::view::{PLAYER_HEIGHT_TILES, TILE_SCREEN_PX};
use deepdelve_core::world::World;

const WORLD_TILES_X: usize = 256;
const WORLD_TILES_Y: usize = 128;
const SEED: u64 = 7;

/// How many chunks beyond the player's own are kept resident.
const CHUNK_RADIUS: i32 = 2;

/// Screen pixels per tile, as a float.
const PX: f32 = TILE_SCREEN_PX as f32;

/// Edge length of a chunk, in world units.
const CHUNK_UNITS: f32 = CHUNK_TILES as f32 * PX;

/// Longest frame the simulation will accept, so a stall cannot teleport the
/// player through the ground.
const MAX_FRAME: f32 = 1.0 / 30.0;

#[derive(Resource)]
struct Game {
    world: World,
    atlas: TileAtlas,
}

#[derive(Resource)]
struct Player {
    body: Body,
    inventory: Inventory,
    mining: MiningState,
    /// Index into `HOTBAR` of the item the player is holding.
    hotbar_slot: usize,
    combat: Combat,
    anim: Animator,
    facing_right: bool,
}

#[derive(Resource, Default)]
struct Monsters(Vec<Enemy>);

#[derive(Resource, Default)]
struct Bosses(Vec<Boss>);

#[derive(Component)]
struct BossSprite(usize);

/// Damage one swing deals to a boss. Lower than against ordinary enemies
/// would be, because boss health pools are large and the fight should last.
const BOSS_ATTACK_DAMAGE: f32 = 26.0;

/// Seconds between a summoning phase calling in its minions.
const BOSS_SUMMON_INTERVAL: f32 = 6.0;

/// A boss stands head and shoulders over the player.
const BOSS_SCALE: f32 = 2.4;

/// Pre-generated animation frames for one character.
#[derive(Default)]
struct FrameSet {
    frames: std::collections::HashMap<(AnimState, u32, bool), Handle<Image>>,
}

impl FrameSet {
    /// The handle for a frame, falling back to the open-eyed variant where
    /// no blinking version was generated.
    fn get(&self, state: AnimState, frame: u32, blinking: bool) -> Option<Handle<Image>> {
        self.frames
            .get(&(state, frame, blinking))
            .or_else(|| self.frames.get(&(state, frame, false)))
            .cloned()
    }
}

/// Scenery textures, generated once at startup like the character frames.
#[derive(Resource, Default)]
struct PropBank {
    textures: std::collections::HashMap<(Prop, u32), Handle<Image>>,
}

impl PropBank {
    fn build(images: &mut Assets<Image>) -> PropBank {
        let mut textures = std::collections::HashMap::new();

        for prop in ALL_PROPS {
            for variant in 0..PROP_VARIANTS {
                textures.insert(
                    (prop, variant),
                    images.add(to_image(prop_texture(prop, variant))),
                );
            }
        }

        PropBank { textures }
    }

    fn get(&self, prop: Prop, variant: u32) -> Option<Handle<Image>> {
        self.textures.get(&(prop, variant % PROP_VARIANTS)).cloned()
    }
}

/// Every character's frames, generated once at startup.
///
/// Generating a sprite per frame would destroy mobile performance, so this
/// is built up front and only ever read afterwards.
#[derive(Resource, Default)]
struct SpriteBank {
    player: FrameSet,
    enemies: Vec<FrameSet>,
    bosses: Vec<FrameSet>,
}

/// States where a blink is actually visible, so only these get the extra
/// closed-eye frames rather than doubling the whole bank.
fn blinks_in(state: AnimState) -> bool {
    matches!(state, AnimState::Idle | AnimState::Walk | AnimState::Run)
}

fn build_frame_set(images: &mut Assets<Image>, style: &CharacterStyle) -> FrameSet {
    let mut frames = std::collections::HashMap::new();

    for state in ALL_STATES {
        for frame in 0..clip(state).frames {
            for blinking in [false, true] {
                if blinking && !blinks_in(state) {
                    continue;
                }

                let texture = character_frame(style, state, frame, blinking);
                frames.insert((state, frame, blinking), images.add(to_image(texture)));
            }
        }
    }

    FrameSet { frames }
}

/// On-screen size of a character sprite, preserving the canvas aspect.
fn character_size(height_tiles: f32) -> Vec2 {
    let height = height_tiles * PX;
    Vec2::new(height * CHAR_W as f32 / CHAR_H as f32, height)
}

/// Tint for a character standing at `(x, y)` in tile space.
///
/// Characters are lit by the same sky light as the terrain. Without this
/// they glow at full brightness in a pitch-dark cave, which immediately
/// reads as a sprite pasted on top of the scene rather than standing in it.
fn lit_tint(lighting: &LightMap, clock: &TimeOfDay, x: f32, y: f32) -> Color {
    // Sample at chest height rather than at the feet, which are often
    // buried in the floor tile.
    let brightness = lit_brightness(lighting, clock, x.max(0.0) as usize, (y - 1.0).max(0.0) as usize);

    Color::srgb(brightness, brightness, brightness)
}

/// How brightly lit a tile is right now, as a fraction.
fn lit_brightness(lighting: &LightMap, clock: &TimeOfDay, tile_x: usize, tile_y: usize) -> f32 {
    (lighting.brightness(tile_x, tile_y) * clock.sky_brightness())
        .clamp(AMBIENT_LIGHT, 1.0)
}

#[derive(Resource)]
struct Clock(TimeOfDay);

/// Counter mixed into the spawn hash so successive attempts differ.
#[derive(Resource, Default)]
struct SpawnTicks(u64);

#[derive(Component)]
struct MonsterSprite(usize);

/// The player's starting and maximum health.
const PLAYER_HEALTH: f32 = 100.0;

/// Damage one swing deals to an enemy.
const ATTACK_DAMAGE: f32 = 12.0;

/// How close a click must land to an enemy to hit it, in tiles.
const ATTACK_RADIUS: f32 = 1.6;

/// Seconds between spawn attempts.
const SPAWN_INTERVAL: f32 = 3.5;

/// Enemies are never spawned closer to the player than this, in tiles, so
/// nothing materialises in the player's face.
const SPAWN_MIN_DISTANCE: f32 = 12.0;
const SPAWN_MAX_DISTANCE: f32 = 26.0;

/// Upper limit on living enemies, to bound both difficulty and cost.
const MAX_MONSTERS: usize = 14;

/// How far above and below the player spawns are searched for, in tiles.
const SPAWN_DEPTH_WINDOW: usize = 12;

/// Items reachable from the hotbar, in order.
const HOTBAR: [ItemId; 4] = [
    deepdelve_core::item::DIRT,
    deepdelve_core::item::STONE,
    deepdelve_core::item::COPPER_ORE,
    deepdelve_core::item::IRON_ORE,
];

/// Bare-handed dig power, before any pickaxe is crafted.
const BARE_HAND_POWER: f32 = 1.6;

/// The tile currently under the cursor or finger, if any.
#[derive(Resource, Default)]
struct Target(Option<(usize, usize)>);

#[derive(Component)]
struct TargetHighlight;

#[derive(Component)]
struct HudText;

/// One of the on-screen thumb controls.
#[derive(Component, Clone, Copy)]
enum TouchControl {
    Stick,
    Jump,
    Build,
}

/// Chunks whose tiles changed and which must be re-composited.
#[derive(Resource, Default)]
struct DirtyChunks(HashSet<(usize, usize)>);

#[derive(Component)]
struct ChunkTile {
    cx: usize,
    cy: usize,
}

/// How far sky light reaches, recomputed whenever tiles change.
#[derive(Resource)]
struct Lighting(LightMap);

/// Floor on darkness, so unlit rock reads as very dim rather than invisible.
const AMBIENT_LIGHT: f32 = 0.15;

/// A darkness layer drawn over one chunk, one texel per tile.
///
/// Kept separate from the chunk's tile texture because the two change at very
/// different rates: a 768px tile texture is expensive to re-composite, while
/// a 16px light texture is nearly free and must update whenever light moves.
#[derive(Component)]
struct LightOverlay {
    cx: usize,
    cy: usize,
}

/// Set when the light map has changed and every overlay needs redrawing.
#[derive(Resource, Default)]
struct LightingStale(bool);

/// Where the game writes its save file.
const SAVE_PATH: &str = "deepdelve-save.bin";

/// Stations the player can reach.
///
/// Simplification: the player carries a field kit, so every recipe's station
/// is always available. Placeable workbenches and furnaces would replace
/// this with a proximity check against station tiles.
const FIELD_KIT: [Station; 2] = [Station::Furnace, Station::Anvil];

/// The last thing that happened worth telling the player about.
#[derive(Resource, Default)]
struct Notice(String);

/// Save on F5, reload on F9.
fn save_and_load(
    keys: Res<ButtonInput<KeyCode>>,
    mut game: ResMut<Game>,
    mut player: ResMut<Player>,
    mut clock: ResMut<Clock>,
    mut monsters: ResMut<Monsters>,
    mut dirty: ResMut<DirtyChunks>,
    mut notice: ResMut<Notice>,
) {
    if keys.just_pressed(KeyCode::F5) {
        let snapshot = SaveGame {
            seed: SEED,
            world: game.world.clone(),
            player: PlayerSave {
                x: player.body.x,
                y: player.body.y,
                health: player.combat.health,
                hotbar_slot: player.hotbar_slot as u32,
                inventory: player.inventory.clone(),
            },
            time_of_day: clock.0.fraction() * DAY_LENGTH,
        };

        notice.0 = match std::fs::write(SAVE_PATH, save(&snapshot)) {
            Ok(()) => format!("saved to {SAVE_PATH}"),
            Err(error) => format!("save failed: {error}"),
        };
    }

    if keys.just_pressed(KeyCode::F9) {
        let bytes = match std::fs::read(SAVE_PATH) {
            Ok(bytes) => bytes,
            Err(error) => {
                notice.0 = format!("no save to load: {error}");
                return;
            }
        };

        match load(&bytes) {
            Ok(restored) => {
                game.world = restored.world;

                player.body = Body::new(restored.player.x, restored.player.y);
                player.combat = Combat::new(PLAYER_HEALTH);
                player.combat.health = restored.player.health;
                player.inventory = restored.player.inventory;
                player.hotbar_slot = restored.player.hotbar_slot as usize;
                player.mining.cancel();

                let mut restored_clock = TimeOfDay::dawn();
                restored_clock.advance(restored.time_of_day);
                clock.0 = restored_clock;

                monsters.0.clear();

                // Force every chunk to re-composite against the new world.
                for cy in 0..WORLD_TILES_Y.div_ceil(CHUNK_TILES) {
                    for cx in 0..WORLD_TILES_X.div_ceil(CHUNK_TILES) {
                        dirty.0.insert((cx, cy));
                    }
                }

                notice.0 = "loaded".to_string();
            }
            Err(error) => notice.0 = format!("save file unreadable: {error:?}"),
        }
    }
}

/// Craft the nth currently-available recipe, on keys F1 to F4.
fn crafting(
    keys: Res<ButtonInput<KeyCode>>,
    mut player: ResMut<Player>,
    mut notice: ResMut<Notice>,
) {
    let slots = [KeyCode::F1, KeyCode::F2, KeyCode::F3, KeyCode::F4];

    for (position, key) in slots.into_iter().enumerate() {
        if !keys.just_pressed(key) {
            continue;
        }

        let craftable = available(&player.inventory, &FIELD_KIT);

        let Some(&recipe) = craftable.get(position) else {
            notice.0 = format!("nothing to craft in slot {}", position + 1);
            return;
        };

        let output = deepdelve_core::craft::RECIPES[recipe].output;

        if craft(&mut player.inventory, recipe, &FIELD_KIT) {
            notice.0 = format!("crafted {}", def(output).name);
        } else {
            notice.0 = format!("could not craft {}", def(output).name);
        }
    }
}

/// Light texture size: one texel per tile plus a one-texel border each side.
const LIGHT_TEXELS: u32 = CHUNK_TILES as u32 + 2;

/// The sub-region of the light texture that maps onto the chunk, skipping
/// the border ring.
fn light_source_rect() -> Rect {
    Rect::new(1.0, 1.0, (CHUNK_TILES + 1) as f32, (CHUNK_TILES + 1) as f32)
}

/// Build the darkness overlay for one chunk.
///
/// The texture carries a one-texel border of the neighbouring chunks' light.
/// Without it, bilinear sampling clamps at the chunk edge and each chunk ends
/// on a different value, which shows up as a hard seam running through the
/// darkness. With the border, both sides of a seam interpolate between the
/// same two tiles and agree exactly.
fn light_image(light: &LightMap, cx: usize, cy: usize) -> Image {
    let size = LIGHT_TEXELS;
    let mut pixels = Vec::with_capacity((size * size * 4) as usize);

    let base_x = (cx * CHUNK_TILES) as isize;
    let base_y = (cy * CHUNK_TILES) as isize;

    for ty in 0..size as isize {
        for tx in 0..size as isize {
            // Offset by one so index 1 is the chunk's first real tile.
            let world_x = (base_x + tx - 1).clamp(0, light.width() as isize - 1) as usize;
            let world_y = (base_y + ty - 1).clamp(0, light.height() as isize - 1) as usize;

            let brightness = light.brightness(world_x, world_y).max(AMBIENT_LIGHT);
            let darkness = ((1.0 - brightness) * 255.0) as u8;
            pixels.extend_from_slice(&[0, 0, 0, darkness]);
        }
    }

    let mut image = Image::new(
        Extent3d {
            width: size,
            height: size,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        pixels,
        TextureFormat::Rgba8UnormSrgb,
        RenderAssetUsages::RENDER_WORLD,
    );

    // Linear, unlike the tiles: light should be a gradient, not a staircase
    // of lit squares.
    image.sampler = ImageSampler::linear();
    image
}

/// Recompute sky light after tiles change, before the dirty set is consumed.
fn refresh_lighting(
    game: Res<Game>,
    dirty: Res<DirtyChunks>,
    mut lighting: ResMut<Lighting>,
    mut stale: ResMut<LightingStale>,
) {
    if dirty.0.is_empty() {
        return;
    }

    lighting.0 = compute_sky_light(&game.world);
    stale.0 = true;
}

/// Redraw every overlay when the light map has moved.
fn refresh_light_overlays(
    mut images: ResMut<Assets<Image>>,
    lighting: Res<Lighting>,
    mut stale: ResMut<LightingStale>,
    mut overlays: Query<(&LightOverlay, &mut Sprite)>,
) {
    if !stale.0 {
        return;
    }
    stale.0 = false;

    for (overlay, mut sprite) in &mut overlays {
        sprite.image = images.add(light_image(&lighting.0, overlay.cx, overlay.cy));
    }
}

/// Dim the world with the time of day.
fn apply_sky_tint(
    clock: Res<Clock>,
    mut chunks: Query<&mut Sprite, (With<ChunkTile>, Without<LightOverlay>)>,
) {
    let brightness = clock.0.sky_brightness();
    let tint = Color::srgb(brightness, brightness, brightness);

    for mut sprite in &mut chunks {
        sprite.color = tint;
    }
}

#[derive(Component)]
struct PlayerSprite;

/// Headless capture mode: with `DEEPDELVE_SHOT=<path>` set, the app renders a
/// few seconds, saves a screenshot and exits. This is how rendering gets
/// verified in a container with no display and no GPU.
#[derive(Resource)]
struct CaptureRun {
    path: String,
    frames: u32,
    at_frame: u32,
    captured: bool,
}

/// Default frames to settle (player falls and lands) before the shot.
/// Override with `DEEPDELVE_SHOT_FRAME` to let more of the world happen first.
const DEFAULT_CAPTURE_FRAME: u32 = 90;

/// Frames to wait after the shot so the file is flushed before exiting.
const CAPTURE_TAIL_FRAMES: u32 = 60;

/// Entry point for both desktop and Android.
///
/// `#[bevy_main]` additionally emits the `android_main` symbol that
/// GameActivity looks for when the crate is built as a `cdylib`.
#[bevy_main]
pub fn main() {
    App::new()
        .add_plugins(
            DefaultPlugins
                .set(ImagePlugin::default_nearest())
                .set(WindowPlugin {
                    primary_window: Some(Window {
                        title: "Deepdelve".into(),
                        resolution: window_resolution(),
                        ..default()
                    }),
                    ..default()
                }),
        )
        .insert_resource(ClearColor(Color::srgb(0.42, 0.65, 0.85)))
        .add_systems(Startup, setup)
        .add_systems(
            Update,
            // Grouped because a single chain tops out at 20 systems. The
            // groups run in order, and so do the systems inside each.
            (
                // Input and the player.
                (advance_clock, step_player, aim_at_tile, dig_or_build).chain(),
                // Combat and spawning.
                (
                    attack_monsters,
                    attack_bosses,
                    spawn_monsters,
                    step_monsters,
                    summon_boss,
                    step_bosses,
                )
                    .chain(),
                // Player-driven side effects.
                (crafting, save_and_load).chain(),
                // World presentation.
                (
                    refresh_lighting,
                    stream_chunks,
                    refresh_light_overlays,
                    apply_sky_tint,
                )
                    .chain(),
                // Everything that follows the simulation.
                (
                    animate_player,
                    sync_monster_sprites,
                    sync_boss_sprites,
                    follow_camera,
                    update_hud,
                    layout_touch_controls,
                )
                    .chain(),
            )
                .chain(),
        )
        .add_systems(Update, capture_and_exit)
        .run();
}

/// Drives `DEEPDELVE_SHOT` capture mode; does nothing in normal play.
fn capture_and_exit(
    mut commands: Commands,
    capture: Option<ResMut<CaptureRun>>,
    mut exit: MessageWriter<AppExit>,
) {
    let Some(mut capture) = capture else {
        return;
    };

    capture.frames += 1;

    if capture.frames >= capture.at_frame && !capture.captured {
        capture.captured = true;
        let path = capture.path.clone();
        commands
            .spawn(Screenshot::primary_window())
            .observe(save_to_disk(path));
    }

    if capture.frames >= capture.at_frame + CAPTURE_TAIL_FRAMES {
        exit.write(AppExit::Success);
    }
}

/// Window size, overridable with `DEEPDELVE_RES=<width>x<height>` so phone
/// aspect ratios can be checked on a desktop.
fn window_resolution() -> WindowResolution {
    let parsed = std::env::var("DEEPDELVE_RES").ok().and_then(|value| {
        let (width, height) = value.split_once('x')?;
        Some((width.parse::<u32>().ok()?, height.parse::<u32>().ok()?))
    });

    parsed.unwrap_or((1280, 720)).into()
}

fn setup(mut commands: Commands, mut images: ResMut<Assets<Image>>) {
    // Generate every character's frames up front. Doing this per frame at
    // runtime would be ruinous on a phone.
    let bank = SpriteBank {
        player: build_frame_set(&mut images, &player_style()),
        enemies: (0..deepdelve_core::enemy::ENEMIES.len())
            .map(|index| {
                build_frame_set(&mut images, &enemy_style(EnemyKindId(index as u16)))
            })
            .collect(),
        bosses: (0..deepdelve_core::boss::BOSSES.len())
            .map(|index| {
                build_frame_set(
                    &mut images,
                    &boss_style(deepdelve_core::boss::BossKindId(index as u16)),
                )
            })
            .collect(),
    };

    let world = World::generate(SEED, WORLD_TILES_X, WORLD_TILES_Y);
    let atlas = TileAtlas::new(SEED);

    let spawn_x = WORLD_TILES_X / 2;
    let surface = world.surface_y(spawn_x).unwrap_or(WORLD_TILES_Y / 3);
    let body = Body::new(spawn_x as f32 + 0.5, surface as f32);

    commands.spawn((Camera2d, Transform::from_xyz(0.0, 0.0, 1000.0)));

    let first_frame = bank
        .player
        .get(AnimState::Idle, 0, false)
        .expect("player idle frame");

    commands.spawn((
        Sprite {
            image: first_frame,
            custom_size: Some(character_size(PLAYER_HEIGHT_TILES)),
            ..default()
        },
        Transform::from_xyz(0.0, 0.0, 10.0),
        PlayerSprite,
    ));

    commands.insert_resource(bank);
    commands.insert_resource(PropBank::build(&mut images));

    // Translucent square showing which tile the pick will hit.
    commands.spawn((
        Sprite {
            color: Color::srgba(1.0, 1.0, 1.0, 0.28),
            custom_size: Some(Vec2::splat(PX)),
            ..default()
        },
        Transform::from_xyz(0.0, 0.0, 5.0),
        Visibility::Hidden,
        TargetHighlight,
    ));

    commands.spawn((
        Text::new(""),
        TextFont {
            // Viewport-relative, so the HUD stays readable on a phone
            // instead of shrinking to nothing at high resolution.
            font_size: FontSize::Vh(2.6),
            ..default()
        },
        TextColor(Color::WHITE),
        Node {
            position_type: PositionType::Absolute,
            top: Val::Px(12.0),
            left: Val::Px(12.0),
            ..default()
        },
        HudText,
    ));

    // On-screen controls. Positions and sizes are laid out each frame from
    // the real window size, so they follow rotation and screen size.
    for control in [TouchControl::Stick, TouchControl::Jump, TouchControl::Build] {
        commands.spawn((
            Node {
                position_type: PositionType::Absolute,
                border_radius: BorderRadius::MAX,
                ..default()
            },
            BackgroundColor(Color::srgba(1.0, 1.0, 1.0, 0.10)),
            control,
        ));
    }

    commands.insert_resource(Lighting(compute_sky_light(&world)));
    commands.insert_resource(LightingStale::default());
    commands.insert_resource(Game { world, atlas });
    commands.insert_resource(Player {
        body,
        inventory: Inventory::new(40),
        mining: MiningState::new(),
        hotbar_slot: 0,
        combat: Combat::new(PLAYER_HEALTH),
        anim: Animator::new(),
        facing_right: true,
    });
    commands.insert_resource(Target::default());
    commands.insert_resource(DirtyChunks::default());
    commands.insert_resource(Monsters::default());
    commands.insert_resource(Bosses::default());
    commands.insert_resource(Notice::default());
    commands.insert_resource(SpawnTicks::default());
    // Start after dark when asked, so nocturnal spawning can be exercised
    // without waiting out half a day cycle.
    let mut clock = TimeOfDay::dawn();
    if std::env::var("DEEPDELVE_START_NIGHT").is_ok() {
        clock.advance(DAY_LENGTH * 0.7);
    }
    commands.insert_resource(Clock(clock));

    if let Ok(path) = std::env::var("DEEPDELVE_SHOT") {
        let at_frame = std::env::var("DEEPDELVE_SHOT_FRAME")
            .ok()
            .and_then(|value| value.parse().ok())
            .unwrap_or(DEFAULT_CAPTURE_FRAME);

        commands.insert_resource(CaptureRun {
            path,
            frames: 0,
            at_frame,
            captured: false,
        });
    }
}

/// Lay the thumb controls out for the current window size.
fn layout_touch_controls(
    windows: Query<&Window>,
    mut controls_ui: Query<(&mut Node, &TouchControl)>,
) {
    let Ok(window) = windows.single() else {
        return;
    };
    let controls = Controls::new(window.width(), window.height());

    for (mut node, which) in &mut controls_ui {
        let (centre, radius) = match which {
            TouchControl::Stick => (controls.stick_centre(), controls.stick_radius()),
            TouchControl::Jump => (controls.jump_centre(), controls.button_radius()),
            TouchControl::Build => (controls.build_centre(), controls.button_radius()),
        };

        node.left = Val::Px(centre.0 - radius);
        node.top = Val::Px(centre.1 - radius);
        node.width = Val::Px(radius * 2.0);
        node.height = Val::Px(radius * 2.0);
    }
}

/// The control layout for the current window, if there is one.
fn controls_for(windows: &Query<&Window>) -> Option<Controls> {
    windows
        .single()
        .ok()
        .map(|window| Controls::new(window.width(), window.height()))
}

/// Translate keyboard and touch into an `Intent`, then advance the body.
fn step_player(
    time: Res<Time>,
    keys: Res<ButtonInput<KeyCode>>,
    touches: Res<Touches>,
    windows: Query<&Window>,
    game: Res<Game>,
    mut player: ResMut<Player>,
    mut sprites: Query<&mut Transform, With<PlayerSprite>>,
) {
    let mut move_dir: f32 = 0.0;
    if keys.pressed(KeyCode::KeyA) || keys.pressed(KeyCode::ArrowLeft) {
        move_dir -= 1.0;
    }
    if keys.pressed(KeyCode::KeyD) || keys.pressed(KeyCode::ArrowRight) {
        move_dir += 1.0;
    }

    let mut jump = keys.pressed(KeyCode::Space)
        || keys.pressed(KeyCode::KeyW)
        || keys.pressed(KeyCode::ArrowUp);

    if let Some(controls) = controls_for(&windows) {
        for touch in touches.iter() {
            let point = touch.position();

            match controls.zone_at(point.x, point.y) {
                Zone::Stick => move_dir += controls.stick_axis(point.x, point.y),
                Zone::Jump => jump = true,
                Zone::Build | Zone::World => {}
            }
        }
    }

    let intent = Intent {
        move_dir: move_dir.clamp(-1.0, 1.0),
        jump,
    };

    let dt = time.delta_secs().min(MAX_FRAME);
    player.body.step(&game.world, intent, dt);

    // Face the way we are steering, and keep facing that way once stopped.
    if intent.move_dir > 0.1 {
        player.facing_right = true;
    } else if intent.move_dir < -0.1 {
        player.facing_right = false;
    }

    let locomotion = state_from_motion(
        player.body.vx,
        player.body.vy,
        player.body.on_ground,
    );
    player.anim.request(locomotion);
    player.anim.advance(dt);

    for mut transform in &mut sprites {
        transform.translation.x = player.body.x * PX;
        transform.translation.y = -(player.body.y - PLAYER_HEIGHT_TILES / 2.0) * PX;
    }
}

/// Advance the day-night clock and tint the sky to match.
fn advance_clock(time: Res<Time>, mut clock: ResMut<Clock>, mut sky: ResMut<ClearColor>) {
    clock.0.advance(time.delta_secs());

    let brightness = clock.0.sky_brightness();
    sky.0 = Color::srgb(
        0.42 * brightness,
        0.65 * brightness,
        0.85 * brightness,
    );
}

/// Occasionally place a new enemy out of sight of the player.
fn spawn_monsters(
    time: Res<Time>,
    clock: Res<Clock>,
    game: Res<Game>,
    player: Res<Player>,
    mut monsters: ResMut<Monsters>,
    mut ticks: ResMut<SpawnTicks>,
    mut since_last: Local<f32>,
) {
    *since_last += time.delta_secs();
    if *since_last < SPAWN_INTERVAL {
        return;
    }
    *since_last = 0.0;

    if monsters.0.len() >= MAX_MONSTERS {
        return;
    }

    ticks.0 += 1;
    let roll = |n: i64| hash01(ticks.0, n);

    let side = if roll(1) < 0.5 { -1.0 } else { 1.0 };
    let distance = SPAWN_MIN_DISTANCE + roll(2) * (SPAWN_MAX_DISTANCE - SPAWN_MIN_DISTANCE);

    let x = player.body.x + side * distance;
    if x < 1.0 || x >= (WORLD_TILES_X - 1) as f32 {
        return;
    }

    let tx = x as usize;

    // Search the column near the player's depth for real footing with
    // headroom, rather than guessing a row and hoping it is a floor.
    let top = (player.body.y as usize).saturating_sub(SPAWN_DEPTH_WINDOW);
    let bottom = (player.body.y as usize + SPAWN_DEPTH_WINDOW).min(WORLD_TILES_Y - 2);

    let Some(ty) = find_standing_spot(&game.world, tx, top, bottom, roll(3)) else {
        return;
    };

    let depth = ty as f32 / WORLD_TILES_Y as f32;

    let Some(chosen) = choose_kind(depth, clock.0.is_night(), roll(4)) else {
        return;
    };

    // Feet rest on the top edge of the solid tile below the spot.
    monsters
        .0
        .push(Enemy::new(chosen, tx as f32 + 0.5, (ty + 1) as f32));
}

/// Run enemy AI and physics, apply contact damage, and respawn on death.
fn step_monsters(
    time: Res<Time>,
    game: Res<Game>,
    mut monsters: ResMut<Monsters>,
    mut player: ResMut<Player>,
) {
    let dt = time.delta_secs().min(MAX_FRAME);

    player.combat.tick(dt);
    let player_body = player.body;

    for enemy in monsters.0.iter_mut() {
        // A dead enemy stops fighting but stays long enough to fall over.
        if !enemy.is_alive() {
            enemy.anim.request(AnimState::Death);
            enemy.anim.advance(dt);
            continue;
        }

        enemy.combat.tick(dt);

        let intent = chase_intent(enemy, &game.world, player_body.x);
        let paced = Intent {
            move_dir: intent.move_dir * kind(enemy.kind).speed_scale,
            jump: intent.jump,
        };
        enemy.body.step(&game.world, paced, dt);

        if intent.move_dir > 0.01 {
            enemy.facing_right = true;
        } else if intent.move_dir < -0.01 {
            enemy.facing_right = false;
        }

        enemy.anim.request(state_from_motion(
            enemy.body.vx,
            enemy.body.vy,
            enemy.body.on_ground,
        ));
        enemy.anim.advance(dt);

        if bodies_overlap(&enemy.body, &player_body) {
            if player.combat.take_damage(kind(enemy.kind).contact_damage) {
                player.anim.request(AnimState::Hurt);
            }
            enemy.anim.request(AnimState::Attack);
        }
    }

    // Keep corpses until their death animation has played out.
    monsters
        .0
        .retain(|enemy| enemy.is_alive() || !enemy.anim.finished());

    if !player.combat.is_alive() {
        let spawn_x = WORLD_TILES_X / 2;
        let surface = game.world.surface_y(spawn_x).unwrap_or(WORLD_TILES_Y / 3);

        player.body = Body::new(spawn_x as f32 + 0.5, surface as f32);
        player.combat = Combat::new(PLAYER_HEALTH);
        monsters.0.clear();
    }
}

/// Swing at whatever enemy is nearest the aim point.
fn attack_monsters(
    mouse: Res<ButtonInput<MouseButton>>,
    target: Res<Target>,
    mut monsters: ResMut<Monsters>,
    mut player: ResMut<Player>,
) {
    if !mouse.just_pressed(MouseButton::Left) {
        return;
    }

    let Some((tile_x, tile_y)) = target.0 else {
        return;
    };
    let aim = (tile_x as f32 + 0.5, tile_y as f32 + 0.5);

    let mut nearest: Option<(usize, f32)> = None;

    for (index, enemy) in monsters.0.iter().enumerate() {
        let centre_y = enemy.body.y - enemy.body.height() / 2.0;
        let distance_sq = (enemy.body.x - aim.0).powi(2) + (centre_y - aim.1).powi(2);

        if distance_sq <= ATTACK_RADIUS * ATTACK_RADIUS
            && nearest.is_none_or(|(_, best)| distance_sq < best)
        {
            nearest = Some((index, distance_sq));
        }
    }

    player.anim.request(AnimState::Attack);

    let Some((index, _)) = nearest else {
        return;
    };

    let enemy = &mut monsters.0[index];
    let landed = enemy.combat.take_damage(ATTACK_DAMAGE);

    if landed {
        enemy.anim.request(AnimState::Hurt);
    }

    if landed && !enemy.is_alive() {
        for &(item, count) in enemy.loot() {
            player.inventory.add(item, count);
        }
    }
}

/// Summon a boss with B, consuming whichever token the player holds.
fn summon_boss(
    keys: Res<ButtonInput<KeyCode>>,
    game: Res<Game>,
    mut player: ResMut<Player>,
    mut bosses: ResMut<Bosses>,
    mut notice: ResMut<Notice>,
) {
    if !keys.just_pressed(KeyCode::KeyB) {
        return;
    }

    if !bosses.0.is_empty() {
        notice.0 = "a boss is already here".to_string();
        return;
    }

    // Find any summoning token in the inventory.
    let token = (0..player.inventory.slot_count())
        .filter_map(|slot| player.inventory.slot(slot))
        .find_map(|stack| boss_summoned_by(stack.item).map(|boss| (stack.item, boss)));

    let Some((item, boss_kind)) = token else {
        notice.0 = "no summoning token — brutes carry the Cracked Idol".to_string();
        return;
    };

    // Place it on solid footing beside the player.
    let column = (player.body.x as usize + 6).min(WORLD_TILES_X - 2);
    let top = (player.body.y as usize).saturating_sub(10);
    let bottom = (player.body.y as usize + 10).min(WORLD_TILES_Y - 2);

    let Some(row) = find_standing_spot(&game.world, column, top, bottom, 0.5) else {
        notice.0 = "no room here to summon".to_string();
        return;
    };

    player.inventory.remove(item, 1);
    bosses
        .0
        .push(Boss::new(boss_kind, column as f32 + 0.5, (row + 1) as f32));

    notice.0 = format!("{} rises!", boss_kind_of(boss_kind).name);
}

/// Advance boss AI, physics, contact damage and minion summoning.
fn step_bosses(
    time: Res<Time>,
    game: Res<Game>,
    mut bosses: ResMut<Bosses>,
    mut monsters: ResMut<Monsters>,
    mut player: ResMut<Player>,
    mut notice: ResMut<Notice>,
    mut summon_timer: Local<f32>,
) {
    if bosses.0.is_empty() {
        return;
    }

    let dt = time.delta_secs().min(MAX_FRAME);
    *summon_timer += dt;

    let summoning_due = *summon_timer >= BOSS_SUMMON_INTERVAL;
    if summoning_due {
        *summon_timer = 0.0;
    }

    let player_body = player.body;

    for boss in bosses.0.iter_mut() {
        boss.combat.tick(dt);

        let intent = boss_intent(boss, &game.world, player_body.x);
        boss.body.step(&game.world, intent, dt);

        if intent.move_dir > 0.01 {
            boss.facing_right = true;
        } else if intent.move_dir < -0.01 {
            boss.facing_right = false;
        }

        boss.anim.request(state_from_motion(
            boss.body.vx,
            boss.body.vy,
            boss.body.on_ground,
        ));
        boss.anim.advance(dt);

        let phase = *boss.phase();

        if bodies_overlap(&boss.body, &player_body) {
            if player.combat.take_damage(phase.contact_damage) {
                player.anim.request(AnimState::Hurt);
            }
            boss.anim.request(AnimState::Attack);
        }

        if summoning_due {
            if let BossAttack::Summon { minion, count } = phase.attack {
                for offset in 0..count {
                    let x = boss.body.x + 2.0 + offset as f32;
                    monsters.0.push(Enemy::new(minion, x, boss.body.y));
                }
            }
        }
    }

    // Pay out and clear any boss that has fallen.
    let fallen: Vec<Boss> = bosses
        .0
        .iter()
        .filter(|boss| !boss.is_alive())
        .copied()
        .collect();

    for boss in &fallen {
        for &(item, count) in boss.loot() {
            player.inventory.add(item, count);
        }
        notice.0 = format!("{} defeated!", boss_kind_of(boss.kind).name);
    }

    bosses.0.retain(|boss| boss.is_alive());
}

/// One sprite per living boss, kept in step with the boss list.
fn sync_boss_sprites(
    mut commands: Commands,
    time: Res<Time>,
    bosses: Res<Bosses>,
    bank: Res<SpriteBank>,
    lighting: Res<Lighting>,
    clock: Res<Clock>,
    mut sprites: Query<(Entity, &BossSprite, &mut Transform, &mut Sprite)>,
) {
    let now = time.elapsed_secs();
    let mut drawn = vec![false; bosses.0.len()];

    let appearance = |boss: &Boss| {
        let blinking = deepdelve_core::anim::blink_closed(now, 900 + boss.kind.0 as u64);

        bank.bosses
            .get(boss.kind.0 as usize)
            .and_then(|set| set.get(boss.anim.state(), boss.anim.frame(), blinking))
    };

    for (entity, marker, mut transform, mut sprite) in &mut sprites {
        match bosses.0.get(marker.0) {
            Some(boss) => {
                drawn[marker.0] = true;
                transform.translation.x = boss.body.x * PX;
                transform.translation.y =
                    -(boss.body.y - PLAYER_HEIGHT_TILES * BOSS_SCALE / 2.0) * PX;

                if let Some(handle) = appearance(boss) {
                    sprite.image = handle;
                }
                sprite.flip_x = !boss.facing_right;
                sprite.color = lit_tint(&lighting.0, &clock.0, boss.body.x, boss.body.y);
            }
            None => {
                commands.entity(entity).despawn();
            }
        }
    }

    for (index, already_drawn) in drawn.iter().enumerate() {
        if *already_drawn {
            continue;
        }

        let boss = &bosses.0[index];
        let Some(handle) = appearance(boss) else {
            continue;
        };

        commands.spawn((
            Sprite {
                image: handle,
                custom_size: Some(character_size(PLAYER_HEIGHT_TILES * BOSS_SCALE)),
                flip_x: !boss.facing_right,
                ..default()
            },
            Transform::from_xyz(
                boss.body.x * PX,
                -(boss.body.y - PLAYER_HEIGHT_TILES * BOSS_SCALE / 2.0) * PX,
                8.0,
            ),
            BossSprite(index),
        ));
    }
}

/// Show the player's current animation frame.
fn animate_player(
    time: Res<Time>,
    player: Res<Player>,
    bank: Res<SpriteBank>,
    lighting: Res<Lighting>,
    clock: Res<Clock>,
    mut sprites: Query<&mut Sprite, With<PlayerSprite>>,
) {
    let blinking = deepdelve_core::anim::blink_closed(time.elapsed_secs(), 1);

    let Some(handle) = bank
        .player
        .get(player.anim.state(), player.anim.frame(), blinking)
    else {
        return;
    };

    let tint = lit_tint(&lighting.0, &clock.0, player.body.x, player.body.y);

    for mut sprite in &mut sprites {
        sprite.image = handle.clone();
        sprite.flip_x = !player.facing_right;
        sprite.color = tint;
    }
}

/// Swing at a boss. Bosses are large, so they are easier to connect with.
fn attack_bosses(
    mouse: Res<ButtonInput<MouseButton>>,
    target: Res<Target>,
    mut bosses: ResMut<Bosses>,
) {
    if !mouse.just_pressed(MouseButton::Left) {
        return;
    }

    let Some((tile_x, tile_y)) = target.0 else {
        return;
    };
    let aim = (tile_x as f32 + 0.5, tile_y as f32 + 0.5);

    for boss in bosses.0.iter_mut() {
        let centre_y = boss.body.y - boss.body.height() * BOSS_SCALE / 2.0;
        let reach = ATTACK_RADIUS * BOSS_SCALE;

        let distance_sq = (boss.body.x - aim.0).powi(2) + (centre_y - aim.1).powi(2);

        if distance_sq <= reach * reach {
            boss.combat.take_damage(BOSS_ATTACK_DAMAGE);
            return;
        }
    }
}

/// Keep one sprite per living enemy, in step with the enemy list.
fn sync_monster_sprites(
    mut commands: Commands,
    time: Res<Time>,
    monsters: Res<Monsters>,
    bank: Res<SpriteBank>,
    lighting: Res<Lighting>,
    clock: Res<Clock>,
    mut sprites: Query<(Entity, &MonsterSprite, &mut Transform, &mut Sprite)>,
) {
    let now = time.elapsed_secs();
    let mut drawn = vec![false; monsters.0.len()];

    // Enemies shift index as others die, so everything is refreshed every
    // frame rather than only on spawn.
    let appearance = |enemy: &Enemy, index: usize| {
        let blinking = deepdelve_core::anim::blink_closed(now, 100 + index as u64);

        bank.enemies
            .get(enemy.kind.0 as usize)
            .and_then(|set| set.get(enemy.anim.state(), enemy.anim.frame(), blinking))
    };

    for (entity, marker, mut transform, mut sprite) in &mut sprites {
        match monsters.0.get(marker.0) {
            Some(enemy) => {
                drawn[marker.0] = true;
                let height = enemy_height_tiles(enemy.kind);

                transform.translation.x = enemy.body.x * PX;
                transform.translation.y = -(enemy.body.y - height / 2.0) * PX;

                if let Some(handle) = appearance(enemy, marker.0) {
                    sprite.image = handle;
                }
                sprite.custom_size = Some(character_size(height));
                sprite.flip_x = !enemy.facing_right;
                sprite.color = lit_tint(&lighting.0, &clock.0, enemy.body.x, enemy.body.y);
            }
            None => {
                commands.entity(entity).despawn();
            }
        }
    }

    for (index, already_drawn) in drawn.iter().enumerate() {
        if *already_drawn {
            continue;
        }

        let enemy = &monsters.0[index];
        let Some(handle) = appearance(enemy, index) else {
            continue;
        };

        let height = enemy_height_tiles(enemy.kind);

        commands.spawn((
            Sprite {
                image: handle,
                custom_size: Some(character_size(height)),
                flip_x: !enemy.facing_right,
                color: lit_tint(&lighting.0, &clock.0, enemy.body.x, enemy.body.y),
                ..default()
            },
            Transform::from_xyz(
                enemy.body.x * PX,
                -(enemy.body.y - height / 2.0) * PX,
                9.0,
            ),
            MonsterSprite(index),
        ));
    }
}

/// Work out which tile the cursor or finger is over, and show the highlight.
fn aim_at_tile(
    windows: Query<&Window>,
    cameras: Query<(&Camera, &GlobalTransform)>,
    touches: Res<Touches>,
    player: Res<Player>,
    mut target: ResMut<Target>,
    mut highlight: Query<(&mut Transform, &mut Visibility), With<TargetHighlight>>,
) {
    let clear = |target: &mut Target,
                     highlight: &mut Query<
        (&mut Transform, &mut Visibility),
        With<TargetHighlight>,
    >| {
        target.0 = None;
        for (_, mut visibility) in highlight.iter_mut() {
            *visibility = Visibility::Hidden;
        }
    };

    let (Ok(window), Ok((camera, camera_transform))) = (windows.single(), cameras.single()) else {
        clear(&mut target, &mut highlight);
        return;
    };

    // Only touches outside the thumb controls aim at the world, so steering
    // with the stick does not also swing the pick.
    let controls = Controls::new(window.width(), window.height());

    let screen = touches
        .iter()
        .map(|touch| touch.position())
        .find(|point| controls.zone_at(point.x, point.y) == Zone::World)
        .or_else(|| window.cursor_position());

    let Some(screen) = screen else {
        clear(&mut target, &mut highlight);
        return;
    };

    let Ok(world_point) = camera.viewport_to_world_2d(camera_transform, screen) else {
        clear(&mut target, &mut highlight);
        return;
    };

    // Screen y is up, world y is down.
    let tile_x = (world_point.x / PX).floor();
    let tile_y = (-world_point.y / PX).floor();

    if tile_x < 0.0 || tile_y < 0.0 {
        clear(&mut target, &mut highlight);
        return;
    }

    let tile = (tile_x as usize, tile_y as usize);

    if !can_reach(&player.body, tile) {
        clear(&mut target, &mut highlight);
        return;
    }

    target.0 = Some(tile);

    for (mut transform, mut visibility) in highlight.iter_mut() {
        transform.translation.x = tile_x * PX + PX / 2.0;
        transform.translation.y = -(tile_y * PX + PX / 2.0);
        *visibility = Visibility::Visible;
    }
}

/// Dig the targeted tile, or place the held block on it.
fn dig_or_build(
    time: Res<Time>,
    mouse: Res<ButtonInput<MouseButton>>,
    keys: Res<ButtonInput<KeyCode>>,
    touches: Res<Touches>,
    windows: Query<&Window>,
    target: Res<Target>,
    mut game: ResMut<Game>,
    mut player: ResMut<Player>,
    mut dirty: ResMut<DirtyChunks>,
) {
    for (index, key) in [
        KeyCode::Digit1,
        KeyCode::Digit2,
        KeyCode::Digit3,
        KeyCode::Digit4,
    ]
    .into_iter()
    .enumerate()
    {
        if keys.just_pressed(key) {
            player.hotbar_slot = index;
        }
    }

    let Some(tile_pos) = target.0 else {
        player.mining.cancel();
        return;
    };

    // Body is Copy, so take a snapshot and avoid borrowing player twice.
    let body = player.body;

    let controls = controls_for(&windows);

    let touch_in = |zone: Zone| {
        controls.is_some_and(|controls| {
            touches
                .iter()
                .any(|touch| controls.zone_at(touch.position().x, touch.position().y) == zone)
        })
    };

    let touch_started_in = |zone: Zone| {
        controls.is_some_and(|controls| {
            touches
                .iter_just_pressed()
                .any(|touch| controls.zone_at(touch.position().x, touch.position().y) == zone)
        })
    };

    let digging = mouse.pressed(MouseButton::Left) || touch_in(Zone::World);

    if digging {
        let dt = time.delta_secs().min(MAX_FRAME);

        player.anim.request(AnimState::Mine);

        if let Some(broken) =
            player
                .mining
                .mine(&mut game.world, &body, tile_pos, BARE_HAND_POWER, dt)
        {
            if let Some(item) = drop_from(broken) {
                player.inventory.add(item, 1);
            }
            mark_dirty(&mut dirty, tile_pos);
        }
    } else {
        player.mining.cancel();
    }

    if mouse.just_pressed(MouseButton::Right) || touch_started_in(Zone::Build) {
        let held = HOTBAR[player.hotbar_slot];

        if let ItemKind::Block(tile) = def(held).kind {
            if player.inventory.count(held) > 0 && place(&mut game.world, &body, tile_pos, tile) {
                player.inventory.remove(held, 1);
                mark_dirty(&mut dirty, tile_pos);
            }
        }
    }
}

/// Mark the chunk holding `tile_pos` dirty, plus its neighbours, since edge
/// lighting on the far side of a chunk seam depends on this tile.
fn mark_dirty(dirty: &mut DirtyChunks, tile_pos: (usize, usize)) {
    let (x, y) = tile_pos;

    for (nx, ny) in [
        (x, y),
        (x.saturating_sub(1), y),
        (x + 1, y),
        (x, y.saturating_sub(1)),
        (x, y + 1),
    ] {
        dirty.0.insert((nx / CHUNK_TILES, ny / CHUNK_TILES));
    }
}

fn update_hud(
    player: Res<Player>,
    clock: Res<Clock>,
    monsters: Res<Monsters>,
    bosses: Res<Bosses>,
    notice: Res<Notice>,
    mut hud: Query<&mut Text, With<HudText>>,
) {
    let held = HOTBAR[player.hotbar_slot];

    let carried: Vec<String> = HOTBAR
        .iter()
        .map(|&item| format!("{} {}", def(item).name, player.inventory.count(item)))
        .collect();

    let health_blocks = (player.combat.health / 10.0).ceil().max(0.0) as usize;
    let health_bar: String = "#".repeat(health_blocks) + &"-".repeat(10 - health_blocks.min(10));

    let sky = if clock.0.is_night() { "night" } else { "day" };

    let craftable = available(&player.inventory, &FIELD_KIT);
    let recipes: Vec<String> = craftable
        .iter()
        .take(4)
        .enumerate()
        .map(|(slot, &recipe)| {
            format!(
                "F{}:{}",
                slot + 1,
                def(deepdelve_core::craft::RECIPES[recipe].output).name
            )
        })
        .collect();

    let crafting_line = if recipes.is_empty() {
        "Craftable: nothing yet (mine ore and coal)".to_string()
    } else {
        format!("Craftable: {}", recipes.join("  "))
    };

    let boss_line = match bosses.0.first() {
        Some(boss) => {
            let blocks = (boss.health_fraction() * 20.0).ceil().max(0.0) as usize;
            format!(
                "\n{} [{}{}] phase {}/{}",
                boss_kind_of(boss.kind).name,
                "#".repeat(blocks),
                "-".repeat(20 - blocks.min(20)),
                boss.phase_index() + 1,
                boss_kind_of(boss.kind).phases.len(),
            )
        }
        None => String::new(),
    };

    let notice_line = if notice.0.is_empty() {
        String::new()
    } else {
        format!("\n> {}", notice.0)
    };

    for mut text in &mut hud {
        text.0 = format!(
            "HP [{health_bar}] {:.0}/{:.0}    {sky}    monsters: {}{boss_line}\n\
             Holding: {}  [1-4 to switch]\n{}\n{crafting_line}\n\
             WASD move, space jumps, left click digs/swings, right click builds\n\
             B summons a boss    F5 saves    F9 loads{notice_line}",
            player.combat.health,
            player.combat.max_health,
            monsters.0.len(),
            def(held).name,
            carried.join("   "),
        );
    }
}

/// Place scenery for one chunk, as children of its tile sprite.
///
/// Positions are relative to the chunk's centre, and the whole lot is
/// deterministic from the world seed, so nothing about decoration needs
/// storing or re-deciding when a chunk streams back in.
fn spawn_scenery(
    chunk: &mut ChildSpawnerCommands,
    game: &Game,
    props: &PropBank,
    lighting: &LightMap,
    clock: &TimeOfDay,
    cx: usize,
    cy: usize,
) {
    let chunk_centre_x = cx as f32 * CHUNK_UNITS + CHUNK_UNITS / 2.0;
    let chunk_centre_y = -(cy as f32 * CHUNK_UNITS + CHUNK_UNITS / 2.0);

    let place = |chunk: &mut ChildSpawnerCommands,
                     prop: Prop,
                     tile_x: usize,
                     ground_y: usize| {
        let variant = (tile_x as u32).wrapping_mul(2654435761) % PROP_VARIANTS;
        let Some(handle) = props.get(prop, variant) else {
            return;
        };

        let (tiles_w, tiles_h) = prop_size_tiles(prop);

        // Scenery sits on the ground: its bottom edge meets the tile top.
        let world_x = (tile_x as f32 + 0.5) * PX;
        let world_y = -(ground_y as f32 - tiles_h / 2.0) * PX;

        // Glowing scenery is lit less by the surroundings and more by itself.
        let ambient = lit_brightness(lighting, clock, tile_x, ground_y);
        let lit = (ambient + prop_glow(prop)).min(1.0);

        chunk.spawn((
            Sprite {
                image: handle,
                custom_size: Some(Vec2::new(tiles_w * PX, tiles_h * PX)),
                color: Color::srgb(lit, lit, lit),
                ..default()
            },
            Transform::from_xyz(
                world_x - chunk_centre_x,
                world_y - chunk_centre_y,
                // Behind creatures, in front of the tiles and their shading.
                2.0,
            ),
        ));
    };

    for offset in 0..CHUNK_TILES {
        let tile_x = cx * CHUNK_TILES + offset;
        if tile_x >= WORLD_TILES_X {
            continue;
        }

        // Surface scenery, if this chunk contains that column's surface.
        if let Some(surface) = game.world.surface_y(tile_x) {
            if surface / CHUNK_TILES == cy {
                if let Some(prop) = surface_prop(SEED, tile_x, biome_at(SEED, tile_x)) {
                    place(chunk, prop, tile_x, surface);
                }
            }
        }

        // Cave scenery on any floor inside this chunk.
        for row in 0..CHUNK_TILES {
            let tile_y = cy * CHUNK_TILES + row;
            if tile_y + 1 >= WORLD_TILES_Y {
                continue;
            }

            if let Some(prop) = cave_prop(&game.world, SEED, tile_x, tile_y) {
                place(chunk, prop, tile_x, tile_y + 1);
            }
        }
    }
}

/// Keep chunks near the player composited and drop the rest.
///
/// Compositing the whole world at once would cost gigabytes of texture, so
/// only a small window around the player is ever resident.
fn stream_chunks(
    mut commands: Commands,
    mut images: ResMut<Assets<Image>>,
    game: Res<Game>,
    lighting: Res<Lighting>,
    clock: Res<Clock>,
    props: Res<PropBank>,
    player: Res<Player>,
    mut dirty: ResMut<DirtyChunks>,
    existing: Query<(Entity, &ChunkTile)>,
) {
    let chunks_x = WORLD_TILES_X.div_ceil(CHUNK_TILES) as i32;
    let chunks_y = WORLD_TILES_Y.div_ceil(CHUNK_TILES) as i32;

    let player_cx = (player.body.x / CHUNK_TILES as f32).floor() as i32;
    let player_cy = (player.body.y / CHUNK_TILES as f32).floor() as i32;

    let mut wanted = HashSet::new();
    for cy in (player_cy - CHUNK_RADIUS)..=(player_cy + CHUNK_RADIUS) {
        for cx in (player_cx - CHUNK_RADIUS)..=(player_cx + CHUNK_RADIUS) {
            if cx >= 0 && cy >= 0 && cx < chunks_x && cy < chunks_y {
                wanted.insert((cx as usize, cy as usize));
            }
        }
    }

    let mut resident = HashSet::new();
    for (entity, chunk) in &existing {
        let key = (chunk.cx, chunk.cy);

        // A dirty chunk is despawned and rebuilt below with fresh tiles.
        if dirty.0.contains(&key) || !wanted.contains(&key) {
            commands.entity(entity).despawn();
        } else {
            resident.insert(key);
        }
    }
    dirty.0.clear();

    for (cx, cy) in wanted {
        if resident.contains(&(cx, cy)) {
            continue;
        }

        let handle = images.add(to_image(chunk_texture(&game.world, &game.atlas, cx, cy)));
        let light_handle = images.add(light_image(&lighting.0, cx, cy));

        commands
            .spawn((
                Sprite {
                    image: handle,
                    custom_size: Some(Vec2::splat(CHUNK_UNITS)),
                    ..default()
                },
                Transform::from_xyz(
                    cx as f32 * CHUNK_UNITS + CHUNK_UNITS / 2.0,
                    -(cy as f32 * CHUNK_UNITS + CHUNK_UNITS / 2.0),
                    0.0,
                ),
                ChunkTile { cx, cy },
            ))
            // The overlay and the scenery ride along as children, so
            // despawning a chunk takes both with it.
            .with_children(|chunk| {
                chunk.spawn((
                    Sprite {
                        image: light_handle,
                        custom_size: Some(Vec2::splat(CHUNK_UNITS)),
                        rect: Some(light_source_rect()),
                        ..default()
                    },
                    Transform::from_xyz(0.0, 0.0, 1.0),
                    LightOverlay { cx, cy },
                ));

                spawn_scenery(chunk, &game, &props, &lighting.0, &clock.0, cx, cy);
            });
    }
}

fn follow_camera(
    player: Res<Player>,
    mut cameras: Query<&mut Transform, (With<Camera2d>, Without<PlayerSprite>)>,
) {
    for mut transform in &mut cameras {
        transform.translation.x = player.body.x * PX;
        transform.translation.y = -(player.body.y - PLAYER_HEIGHT_TILES / 2.0) * PX;
    }
}

/// Upload a core `Texture` as a GPU image.
fn to_image(texture: Texture) -> Image {
    Image::new(
        Extent3d {
            width: texture.width,
            height: texture.height,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        texture.pixels,
        TextureFormat::Rgba8UnormSrgb,
        RenderAssetUsages::RENDER_WORLD,
    )
}
