//! Render every item icon to one PNG. Usage: `cargo run --example icon_sheet -- out.png`
use deepdelve_core::icon::{item_icon, ICON_SIZE};
use deepdelve_core::item::{def, ItemId, ITEMS};
use deepdelve_core::png::encode_rgba;

fn main() {
    let out = std::env::args().nth(1).unwrap_or_else(|| "icons.png".into());
    let scale = 4u32;
    let cell = ICON_SIZE * scale + 8;
    let columns = 8u32;
    let rows = (ITEMS.len() as u32).div_ceil(columns);

    let (w, h) = (cell * columns, cell * rows);
    let mut canvas = Vec::with_capacity((w * h * 4) as usize);
    for y in 0..h {
        for x in 0..w {
            // Slot-like checker so transparency and outlines are visible.
            let slot = ((x % cell) < 4) || ((y % cell) < 4);
            let v: u8 = if slot { 38 } else { 62 };
            canvas.extend_from_slice(&[v, v + 4, v + 12, 255]);
        }
    }

    for index in 0..ITEMS.len() {
        let icon = item_icon(ItemId(index as u16));
        let ox = (index as u32 % columns) * cell + 4;
        let oy = (index as u32 / columns) * cell + 4;

        for y in 0..icon.height {
            for x in 0..icon.width {
                let [r, g, b, a] = icon.pixel(x, y);
                if a == 0 { continue; }
                for sy in 0..scale {
                    for sx in 0..scale {
                        let i = (((oy + y * scale + sy) * w + ox + x * scale + sx) * 4) as usize;
                        canvas[i] = r; canvas[i + 1] = g; canvas[i + 2] = b; canvas[i + 3] = 255;
                    }
                }
            }
        }
        println!("  {:>2} {}", index, def(ItemId(index as u16)).name);
    }

    std::fs::write(&out, encode_rgba(w, h, &canvas)).expect("write png");
    println!("wrote {out}: {w}x{h}");
}
