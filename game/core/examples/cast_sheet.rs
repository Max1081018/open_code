//! Render every character in the game to one PNG, for checking that the
//! cast reads as distinct individuals in one coherent style.
//!
//! Usage: `cargo run --example cast_sheet -- out.png [scale]`

use deepdelve_core::anim::AnimState;
use deepdelve_core::art::Texture;
use deepdelve_core::boss::{kind as boss_kind, BossKindId, BOSSES};
use deepdelve_core::enemy::{kind as enemy_kind, EnemyKindId, ENEMIES};
use deepdelve_core::png::encode_rgba;
use deepdelve_core::sprite::{
    boss_style, character_frame, enemy_style, player_style, CharacterStyle, CHAR_H, CHAR_W,
};

/// The poses shown for each character, left to right.
const SHOWCASE: [(AnimState, u32); 5] = [
    (AnimState::Idle, 0),
    (AnimState::Walk, 1),
    (AnimState::Walk, 4),
    (AnimState::Attack, 2),
    (AnimState::Hurt, 1),
];

fn main() {
    let mut args = std::env::args().skip(1);
    let out_path = args.next().unwrap_or_else(|| "cast.png".to_string());
    let scale: u32 = args.next().and_then(|a| a.parse().ok()).unwrap_or(3);

    let mut cast: Vec<(String, CharacterStyle)> = vec![("Player".to_string(), player_style())];

    for index in 0..ENEMIES.len() {
        let id = EnemyKindId(index as u16);
        cast.push((enemy_kind(id).name.to_string(), enemy_style(id)));
    }
    for index in 0..BOSSES.len() {
        let id = BossKindId(index as u16);
        cast.push((boss_kind(id).name.to_string(), boss_style(id)));
    }

    let cell_w = CHAR_W * scale + 10;
    let cell_h = CHAR_H * scale + 10;
    let sheet_w = cell_w * SHOWCASE.len() as u32;
    let sheet_h = cell_h * cast.len() as u32;

    // Alternating row bands, so each character's row is easy to follow.
    let mut canvas = Vec::with_capacity((sheet_w * sheet_h * 4) as usize);
    for y in 0..sheet_h {
        let band = (y / cell_h) % 2 == 0;
        let shade: u8 = if band { 58 } else { 48 };
        for _ in 0..sheet_w {
            canvas.extend_from_slice(&[shade, shade + 4, shade + 10, 255]);
        }
    }

    for (row, (name, style)) in cast.iter().enumerate() {
        for (column, &(state, frame)) in SHOWCASE.iter().enumerate() {
            let sprite = character_frame(style, state, frame, false);

            blit(
                &mut canvas,
                sheet_w,
                &sprite,
                column as u32 * cell_w + 5,
                row as u32 * cell_h + 5,
                scale,
            );
        }
        println!("  row {row}: {name}");
    }

    std::fs::write(&out_path, encode_rgba(sheet_w, sheet_h, &canvas)).expect("write PNG");
    println!("wrote {out_path}: {sheet_w}x{sheet_h}, {} characters", cast.len());
}

fn blit(canvas: &mut [u8], canvas_w: u32, sprite: &Texture, at_x: u32, at_y: u32, scale: u32) {
    for sy in 0..sprite.height {
        for sx in 0..sprite.width {
            let [r, g, b, a] = sprite.pixel(sx, sy);
            if a == 0 {
                continue;
            }

            for oy in 0..scale {
                for ox in 0..scale {
                    let index = (((at_y + sy * scale + oy) * canvas_w + at_x + sx * scale + ox)
                        * 4) as usize;
                    canvas[index] = r;
                    canvas[index + 1] = g;
                    canvas[index + 2] = b;
                    canvas[index + 3] = 255;
                }
            }
        }
    }
}
