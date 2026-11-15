//! Render a slice of a generated world to a PNG, at the real in-game scale.
//!
//! This is how the look of the game gets checked without a GPU: identical
//! worldgen, identical tile art, identical 96px-per-tile scale the renderer
//! will use.
//!
//! Usage: `cargo run --example render_world -- <out.png> [seed] [tiles_across]`

use deepdelve_core::art::{
    edge_shade, tile_texture, variant_for, variant_seed, Exposure, Texture, TEXTURE_VARIANTS,
};
use deepdelve_core::light::{compute_sky_light, LightMap};
use deepdelve_core::png::encode_rgba;
use deepdelve_core::view::{RENDER_SCALE, TILE_SOURCE_PX};
use deepdelve_core::world::{Tile, World};

/// Sky colours, top of screen to horizon.
const SKY_HIGH: [f32; 3] = [78.0, 134.0, 206.0];
const SKY_LOW: [f32; 3] = [164.0, 206.0, 232.0];

fn main() {
    let mut args = std::env::args().skip(1);

    let out_path = args.next().unwrap_or_else(|| "world.png".to_string());
    let seed: u64 = args.next().and_then(|a| a.parse().ok()).unwrap_or(7);
    let tiles_across: usize = args.next().and_then(|a| a.parse().ok()).unwrap_or(24);
    let tiles_down = (tiles_across * 9 / 16).max(6);

    let world = World::generate(seed, 512, 256);

    // Frame the shot on the surface, a few tiles of sky above it.
    let centre = 200;
    let surface = world.surface_y(centre).unwrap_or(80);
    let origin_x = centre - tiles_across / 2;
    let origin_y = surface.saturating_sub(4);

    let tile_px = TILE_SOURCE_PX * RENDER_SCALE;
    let out_w = tiles_across as u32 * tile_px;
    let out_h = tiles_down as u32 * tile_px;

    let mut canvas = sky_gradient(out_w, out_h);

    // One texture per material, reused across every tile of that material.
    let textures: Vec<(Tile, Vec<Texture>)> = [
        Tile::Dirt,
        Tile::Grass,
        Tile::Sand,
        Tile::Snow,
        Tile::Stone,
        Tile::CoalOre,
        Tile::CopperOre,
        Tile::IronOre,
        Tile::GoldOre,
    ]
    .into_iter()
    .map(|tile| {
        let variants = (0..TEXTURE_VARIANTS)
            .filter_map(|variant| tile_texture(tile, variant_seed(seed, variant)))
            .collect();
        (tile, variants)
    })
    .collect();

    let lookup = |tile: Tile, variant: u32| -> Option<&Texture> {
        textures
            .iter()
            .find(|(kind, _)| *kind == tile)
            .and_then(|(_, variants)| variants.get(variant as usize))
    };

    for ty in 0..tiles_down {
        for tx in 0..tiles_across {
            let (wx, wy) = (origin_x + tx, origin_y + ty);
            let tile = world.tile(wx, wy);
            let Some(texture) = lookup(tile, variant_for(seed, wx, wy)) else {
                continue;
            };

            // A side is lit only where it opens onto air, so buried tiles
            // merge into one mass of ground.
            let open = |x: usize, y: usize| !world.tile(x, y).is_solid();
            let exposure = Exposure {
                top: wy == 0 || open(wx, wy - 1),
                bottom: open(wx, wy + 1),
                left: wx == 0 || open(wx - 1, wy),
                right: open(wx + 1, wy),
            };

            blit_scaled(
                &mut canvas,
                out_w,
                texture,
                exposure,
                tx as u32 * tile_px,
                ty as u32 * tile_px,
                RENDER_SCALE,
            );
        }
    }

    // Light is applied as a post-pass, sampled smoothly between tile centres
    // so the falloff is a gradient rather than a staircase of lit squares.
    let light = compute_sky_light(&world);
    let sky = 1.0f32;

    for py in 0..out_h {
        for px in 0..out_w {
            let world_x = origin_x as f32 + px as f32 / tile_px as f32;
            let world_y = origin_y as f32 + py as f32 / tile_px as f32;

            let lit = (sample_light(&light, world_x, world_y) * sky).clamp(AMBIENT, 1.0);

            let i = ((py * out_w + px) * 4) as usize;
            for channel in 0..3 {
                canvas[i + channel] = (canvas[i + channel] as f32 * lit) as u8;
            }
        }
    }

    let encoded = encode_rgba(out_w, out_h, &canvas);
    std::fs::write(&out_path, &encoded).expect("failed to write PNG");

    println!(
        "wrote {out_path}: {out_w}x{out_h} ({} tiles at {tile_px}px, seed {seed})",
        tiles_across * tiles_down
    );
}

/// Floor on darkness, so unlit rock is readable rather than pure black.
const AMBIENT: f32 = 0.15;

/// Bilinear sample of the light map at a position in tile units.
fn sample_light(light: &LightMap, x: f32, y: f32) -> f32 {
    // Light levels sit at tile centres, half a tile in from the grid.
    let fx = (x - 0.5).max(0.0);
    let fy = (y - 0.5).max(0.0);

    let x0 = fx.floor();
    let y0 = fy.floor();
    let tx = fx - x0;
    let ty = fy - y0;

    let at = |ix: f32, iy: f32| light.brightness(ix.max(0.0) as usize, iy.max(0.0) as usize);

    let top = at(x0, y0) + (at(x0 + 1.0, y0) - at(x0, y0)) * tx;
    let bottom = at(x0, y0 + 1.0) + (at(x0 + 1.0, y0 + 1.0) - at(x0, y0 + 1.0)) * tx;

    top + (bottom - top) * ty
}

/// A vertical sky gradient as an RGBA canvas.
fn sky_gradient(width: u32, height: u32) -> Vec<u8> {
    let mut canvas = Vec::with_capacity((width * height * 4) as usize);

    for y in 0..height {
        let t = y as f32 / (height - 1).max(1) as f32;

        let r = SKY_HIGH[0] + (SKY_LOW[0] - SKY_HIGH[0]) * t;
        let g = SKY_HIGH[1] + (SKY_LOW[1] - SKY_HIGH[1]) * t;
        let b = SKY_HIGH[2] + (SKY_LOW[2] - SKY_HIGH[2]) * t;

        for _ in 0..width {
            canvas.extend_from_slice(&[r as u8, g as u8, b as u8, 255]);
        }
    }

    canvas
}

/// Nearest-neighbour blit of `texture` at `scale`, which keeps pixel art crisp.
fn blit_scaled(
    canvas: &mut [u8],
    canvas_width: u32,
    texture: &Texture,
    exposure: Exposure,
    dest_x: u32,
    dest_y: u32,
    scale: u32,
) {
    for sy in 0..texture.height {
        for sx in 0..texture.width {
            let [r, g, b, a] = texture.pixel(sx, sy);

            let shade = edge_shade(exposure, sx, sy, texture.width);
            let r = (r as f32 * shade).clamp(0.0, 255.0) as u8;
            let g = (g as f32 * shade).clamp(0.0, 255.0) as u8;
            let b = (b as f32 * shade).clamp(0.0, 255.0) as u8;

            for oy in 0..scale {
                for ox in 0..scale {
                    let x = dest_x + sx * scale + ox;
                    let y = dest_y + sy * scale + oy;
                    let i = ((y * canvas_width + x) * 4) as usize;

                    canvas[i] = r;
                    canvas[i + 1] = g;
                    canvas[i + 2] = b;
                    canvas[i + 3] = a;
                }
            }
        }
    }
}
