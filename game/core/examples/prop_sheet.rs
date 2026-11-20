//! Render every prop variant to one PNG for visual inspection.
//!
//! Usage: `cargo run --example prop_sheet -- out.png`

use deepdelve_core::art::Texture;
use deepdelve_core::decor::{prop_size_tiles, prop_texture, ALL_PROPS, PROP_VARIANTS};
use deepdelve_core::png::encode_rgba;

fn main() {
    let out_path = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "props.png".to_string());

    // Size cells to the tallest and widest prop so nothing is cropped.
    let cell_w = ALL_PROPS
        .iter()
        .map(|&p| (prop_size_tiles(p).0 * 48.0) as u32)
        .max()
        .unwrap_or(64)
        + 16;
    let cell_h = ALL_PROPS
        .iter()
        .map(|&p| (prop_size_tiles(p).1 * 48.0) as u32)
        .max()
        .unwrap_or(64)
        + 16;

    let sheet_w = cell_w * PROP_VARIANTS;
    let sheet_h = cell_h * ALL_PROPS.len() as u32;

    // A ground line per row, so "standing on the floor" is checkable by eye.
    let mut canvas = Vec::with_capacity((sheet_w * sheet_h * 4) as usize);
    for y in 0..sheet_h {
        let in_row = y % cell_h;
        let ground = in_row >= cell_h - 9 && in_row < cell_h - 7;
        for _ in 0..sheet_w {
            if ground {
                canvas.extend_from_slice(&[96, 84, 64, 255]);
            } else {
                canvas.extend_from_slice(&[44, 50, 60, 255]);
            }
        }
    }

    for (row, &prop) in ALL_PROPS.iter().enumerate() {
        for variant in 0..PROP_VARIANTS {
            let texture = prop_texture(prop, variant);

            // Sit each prop on the row's ground line, centred in its cell.
            let at_x = variant * cell_w + (cell_w - texture.width) / 2;
            let at_y = (row as u32 + 1) * cell_h - 8 - texture.height;

            blit(&mut canvas, sheet_w, &texture, at_x, at_y);
        }
        println!("  {prop:?}: {:?} tiles", prop_size_tiles(prop));
    }

    std::fs::write(&out_path, encode_rgba(sheet_w, sheet_h, &canvas)).expect("write PNG");
    println!("wrote {out_path}: {sheet_w}x{sheet_h}");
}

fn blit(canvas: &mut [u8], canvas_w: u32, texture: &Texture, at_x: u32, at_y: u32) {
    for y in 0..texture.height {
        for x in 0..texture.width {
            let [r, g, b, a] = texture.pixel(x, y);
            if a == 0 {
                continue;
            }
            let index = (((at_y + y) * canvas_w + at_x + x) * 4) as usize;
            canvas[index] = r;
            canvas[index + 1] = g;
            canvas[index + 2] = b;
            canvas[index + 3] = 255;
        }
    }
}
