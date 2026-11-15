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
}

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
        .add_systems(Update, (step_player, stream_chunks, follow_camera).chain())
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

    commands.insert_resource(Game { world, atlas });
    commands.insert_resource(Player { body });

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

/// Keep chunks near the player composited and drop the rest.
///
/// Compositing the whole world at once would cost gigabytes of texture, so
/// only a small window around the player is ever resident.
fn stream_chunks(
    mut commands: Commands,
    mut images: ResMut<Assets<Image>>,
    game: Res<Game>,
    player: Res<Player>,
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
        if wanted.contains(&(chunk.cx, chunk.cy)) {
            resident.insert((chunk.cx, chunk.cy));
        } else {
            commands.entity(entity).despawn();
        }
    }

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
