//! Render every character animation frame to one PNG for visual inspection.
//!
//! Usage: `cargo run --example sprite_sheet -- out.png [scale]`

use deepdelve_core::anim::{clip, ALL_STATES};
use deepdelve_core::art::Texture;
use deepdelve_core::png::encode_rgba;
use deepdelve_core::sprite::{character_frame, player_style, CHAR_H, CHAR_W};

/// Checkerboard so transparency and silhouettes are both readable.
const CHECK_LIGHT: [u8; 3] = [64, 68, 78];
const CHECK_DARK: [u8; 3] = [52, 56, 64];
const CHECK_SIZE: u32 = 8;

fn main() {
    let mut args = std::env::args().skip(1);
    let out_path = args.next().unwrap_or_else(|| "sprites.png".to_string());
    let scale: u32 = args.next().and_then(|a| a.parse().ok()).unwrap_or(3);

    let longest = ALL_STATES
        .iter()
        .map(|&state| clip(state).frames)
        .max()
        .unwrap_or(1);

    let cell_w = CHAR_W * scale + 8;
    let cell_h = CHAR_H * scale + 8;

    let sheet_w = cell_w * longest;
    let sheet_h = cell_h * ALL_STATES.len() as u32;

    let mut canvas = checkerboard(sheet_w, sheet_h);

    for (row, &state) in ALL_STATES.iter().enumerate() {
        for frame in 0..clip(state).frames {
            // Blink on the last frame of each row, to show the closed eyes.
            let blinking = frame == clip(state).frames - 1;
            let sprite = character_frame(&player_style(), state, frame, blinking);

            blit(
                &mut canvas,
                sheet_w,
                &sprite,
                frame * cell_w + 4,
                row as u32 * cell_h + 4,
                scale,
            );
        }
    }

    std::fs::write(&out_path, encode_rgba(sheet_w, sheet_h, &canvas)).expect("write PNG");

    println!(
        "wrote {out_path}: {sheet_w}x{sheet_h}, {} states at {scale}x",
        ALL_STATES.len()
    );
    for state in ALL_STATES {
        println!("  {state:?}: {} frames", clip(state).frames);
    }
}

fn checkerboard(width: u32, height: u32) -> Vec<u8> {
    let mut canvas = Vec::with_capacity((width * height * 4) as usize);

    for y in 0..height {
        for x in 0..width {
            let dark = ((x / CHECK_SIZE) + (y / CHECK_SIZE)) % 2 == 0;
            let [r, g, b] = if dark { CHECK_DARK } else { CHECK_LIGHT };
            canvas.extend_from_slice(&[r, g, b, 255]);
        }
    }

    canvas
}

/// Nearest-neighbour blit, skipping transparent source pixels.
fn blit(canvas: &mut [u8], canvas_w: u32, sprite: &Texture, at_x: u32, at_y: u32, scale: u32) {
    for sy in 0..sprite.height {
        for sx in 0..sprite.width {
            let [r, g, b, a] = sprite.pixel(sx, sy);
            if a == 0 {
                continue;
            }

            for oy in 0..scale {
                for ox in 0..scale {
                    let x = at_x + sx * scale + ox;
                    let y = at_y + sy * scale + oy;
                    let index = ((y * canvas_w + x) * 4) as usize;

                    canvas[index] = r;
                    canvas[index + 1] = g;
                    canvas[index + 2] = b;
                    canvas[index + 3] = 255;
                }
            }
        }
    }
}
