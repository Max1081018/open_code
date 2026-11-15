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

use deepdelve_core::art::Texture;
use deepdelve_core::interact::{can_reach, place, MiningState, REACH_TILES};
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
}

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
    captured: bool,
}

/// Frames to settle (player falls and lands) before the shot is taken.
const CAPTURE_AT_FRAME: u32 = 90;

/// Frames to wait after the shot so the file is flushed before exiting.
const CAPTURE_EXIT_FRAME: u32 = 150;

fn main() {
    App::new()
        .add_plugins(
            DefaultPlugins
                .set(ImagePlugin::default_nearest())
                .set(WindowPlugin {
                    primary_window: Some(Window {
                        title: "Deepdelve".into(),
                        resolution: (1280u32, 720u32).into(),
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
                step_player,
                aim_at_tile,
                dig_or_build,
                stream_chunks,
                follow_camera,
                update_hud,
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

    if capture.frames == CAPTURE_AT_FRAME && !capture.captured {
        capture.captured = true;
        let path = capture.path.clone();
        commands
            .spawn(Screenshot::primary_window())
            .observe(save_to_disk(path));
    }

    if capture.frames >= CAPTURE_EXIT_FRAME {
        exit.write(AppExit::Success);
    }
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
            font_size: FontSize::Px(22.0),
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

    commands.insert_resource(Game { world, atlas });
    commands.insert_resource(Player {
        body,
        inventory: Inventory::new(40),
        mining: MiningState::new(),
        hotbar_slot: 0,
    });
    commands.insert_resource(Target::default());
    commands.insert_resource(DirtyChunks::default());

    if let Ok(path) = std::env::var("DEEPDELVE_SHOT") {
        commands.insert_resource(CaptureRun {
            path,
            frames: 0,
            captured: false,
        });
    }
}

/// Translate keyboard and touch into an `Intent`, then advance the body.
fn step_player(
    time: Res<Time>,
    keys: Res<ButtonInput<KeyCode>>,
    touches: Res<Touches>,
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

    // Provisional touch scheme until the on-screen controls land: the left
    // third of the screen steers, the right third jumps.
    for touch in touches.iter() {
        let x = touch.position().x;
        if x < 240.0 {
            move_dir -= 1.0;
        } else if x < 480.0 {
            move_dir += 1.0;
        } else {
            jump = true;
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

    let screen = touches
        .iter()
        .next()
        .map(|touch| touch.position())
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

    // Touch digs for now; the on-screen controls in the mobile pass will
    // separate "steer" from "dig" properly.
    let digging = mouse.pressed(MouseButton::Left) || touches.iter().next().is_some();

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

    if mouse.just_pressed(MouseButton::Right) {
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

fn update_hud(player: Res<Player>, mut hud: Query<&mut Text, With<HudText>>) {
    let held = HOTBAR[player.hotbar_slot];

    let carried: Vec<String> = HOTBAR
        .iter()
        .map(|&item| format!("{} {}", def(item).name, player.inventory.count(item)))
        .collect();

    for mut text in &mut hud {
        text.0 = format!(
            "Holding: {}  [1-4 to switch]\n{}\nWASD / arrows move, space jumps\nLeft click digs, right click builds (reach {REACH_TILES} tiles)",
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
