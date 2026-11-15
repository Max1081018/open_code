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
use bevy::render::render_resource::{Extent3d, TextureDimension, TextureFormat};
use bevy::render::view::screenshot::{save_to_disk, Screenshot};
use bevy::window::WindowResolution;

use deepdelve_core::art::Texture;
use deepdelve_core::daynight::{TimeOfDay, DAY_LENGTH};
use deepdelve_core::enemy::{bodies_overlap, chase_intent, kind, Combat, Enemy, EnemyKindId};
use deepdelve_core::spawn::{choose_kind, find_standing_spot};
use deepdelve_core::touch::{Controls, Zone};
use deepdelve_core::interact::{can_reach, place, MiningState, REACH_TILES};
use deepdelve_core::noise::hash01;
use deepdelve_core::item::{def, drop_from, Inventory, ItemId, ItemKind};
use deepdelve_core::physics::{Body, Intent};
use deepdelve_core::tilemap::{chunk_texture, TileAtlas, CHUNK_TILES};
use deepdelve_core::view::{PLAYER_HEIGHT_TILES, PLAYER_WIDTH_TILES, TILE_SCREEN_PX};
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
}

#[derive(Resource, Default)]
struct Monsters(Vec<Enemy>);

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
const SPAWN_INTERVAL: f32 = 2.0;

/// Enemies are never spawned closer to the player than this, in tiles, so
/// nothing materialises in the player's face.
const SPAWN_MIN_DISTANCE: f32 = 12.0;
const SPAWN_MAX_DISTANCE: f32 = 26.0;

/// Upper limit on living enemies, to bound both difficulty and cost.
const MAX_MONSTERS: usize = 24;

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

fn main() {
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
            (
                advance_clock,
                step_player,
                aim_at_tile,
                dig_or_build,
                attack_monsters,
                spawn_monsters,
                step_monsters,
                sync_monster_sprites,
                stream_chunks,
                follow_camera,
                update_hud,
                layout_touch_controls,
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

fn setup(mut commands: Commands) {
    let world = World::generate(SEED, WORLD_TILES_X, WORLD_TILES_Y);
    let atlas = TileAtlas::new(SEED);

    let spawn_x = WORLD_TILES_X / 2;
    let surface = world.surface_y(spawn_x).unwrap_or(WORLD_TILES_Y / 3);
    let body = Body::new(spawn_x as f32 + 0.5, surface as f32);

    commands.spawn((Camera2d, Transform::from_xyz(0.0, 0.0, 1000.0)));

    commands.spawn((
        Sprite {
            color: Color::srgb(0.96, 0.86, 0.62),
            custom_size: Some(Vec2::new(
                PLAYER_WIDTH_TILES * PX,
                PLAYER_HEIGHT_TILES * PX,
            )),
            ..default()
        },
        Transform::from_xyz(0.0, 0.0, 10.0),
        PlayerSprite,
    ));

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
            BackgroundColor(Color::srgba(1.0, 1.0, 1.0, 0.16)),
            control,
        ));
    }

    commands.insert_resource(Game { world, atlas });
    commands.insert_resource(Player {
        body,
        inventory: Inventory::new(40),
        mining: MiningState::new(),
        hotbar_slot: 0,
        combat: Combat::new(PLAYER_HEALTH),
    });
    commands.insert_resource(Target::default());
    commands.insert_resource(DirtyChunks::default());
    commands.insert_resource(Monsters::default());
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

/// Colour used to draw each enemy type until sprite art exists for them.
fn monster_colour(id: EnemyKindId) -> Color {
    match id.0 {
        0 => Color::srgb(0.45, 0.85, 0.45),
        1 => Color::srgb(0.85, 0.55, 0.25),
        2 => Color::srgb(0.70, 0.35, 0.80),
        _ => Color::srgb(0.85, 0.25, 0.25),
    }
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
        enemy.combat.tick(dt);

        let intent = chase_intent(enemy, &game.world, player_body.x);
        let paced = Intent {
            move_dir: intent.move_dir * kind(enemy.kind).speed_scale,
            jump: intent.jump,
        };
        enemy.body.step(&game.world, paced, dt);

        if bodies_overlap(&enemy.body, &player_body) {
            player.combat.take_damage(kind(enemy.kind).contact_damage);
        }
    }

    monsters.0.retain(|enemy| enemy.is_alive());

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

    let Some((index, _)) = nearest else {
        return;
    };

    let enemy = &mut monsters.0[index];
    let landed = enemy.combat.take_damage(ATTACK_DAMAGE);

    if landed && !enemy.is_alive() {
        for &(item, count) in enemy.loot() {
            player.inventory.add(item, count);
        }
    }
}

/// Keep one sprite per living enemy, in step with the enemy list.
fn sync_monster_sprites(
    mut commands: Commands,
    monsters: Res<Monsters>,
    mut sprites: Query<(Entity, &MonsterSprite, &mut Transform, &mut Sprite)>,
) {
    let mut drawn = vec![false; monsters.0.len()];

    for (entity, marker, mut transform, mut sprite) in &mut sprites {
        match monsters.0.get(marker.0) {
            Some(enemy) => {
                drawn[marker.0] = true;
                transform.translation.x = enemy.body.x * PX;
                transform.translation.y =
                    -(enemy.body.y - PLAYER_HEIGHT_TILES / 2.0) * PX;
                // Enemies shift index as others die, so re-tint every frame.
                sprite.color = monster_colour(enemy.kind);
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
        commands.spawn((
            Sprite {
                color: monster_colour(enemy.kind),
                custom_size: Some(Vec2::new(
                    PLAYER_WIDTH_TILES * PX,
                    PLAYER_HEIGHT_TILES * PX,
                )),
                ..default()
            },
            Transform::from_xyz(
                enemy.body.x * PX,
                -(enemy.body.y - PLAYER_HEIGHT_TILES / 2.0) * PX,
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

    for mut text in &mut hud {
        text.0 = format!(
            "HP [{health_bar}] {:.0}/{:.0}    {sky}    monsters: {}\n\
             Holding: {}  [1-4 to switch]\n{}\n\
             WASD / arrows move, space jumps\n\
             Left click digs and swings, right click builds (reach {REACH_TILES} tiles)",
            player.combat.health,
            player.combat.max_health,
            monsters.0.len(),
            def(held).name,
            carried.join("   "),
        );
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

        commands.spawn((
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
        ));
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
