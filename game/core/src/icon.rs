//! Item icons for the hotbar and inventory.
//!
//! Drawn at a small fixed size and read at a glance, so these are bolder and
//! simpler than world art: strong silhouette, few tones, dark outline.

use crate::art::Texture;
use crate::item::{def, ItemId, ItemKind};
use crate::paint::{ramp_from, shade, Canvas};

/// Edge length of an icon, in pixels.
pub const ICON_SIZE: u32 = 32;

/// Outline colour. Dark but never black, so icons read on any background.
const OUTLINE: [f32; 3] = [26.0, 24.0, 34.0];

/// Pixels of clear space kept around every icon, so a row of them does not
/// run together.
const MARGIN: i32 = 3;

/// Fill a shape described by a predicate, then trace a dark outline round it.
///
/// Outlining afterwards rather than drawing a border means the silhouette is
/// always correct whatever the shape.
fn stamp(canvas: &mut Canvas, inside: impl Fn(i32, i32) -> Option<[f32; 3]>) {
    let size = ICON_SIZE as i32;
    let mut filled = vec![false; (size * size) as usize];

    for y in MARGIN..size - MARGIN {
        for x in MARGIN..size - MARGIN {
            if let Some(colour) = inside(x, y) {
                canvas.put(x, y, colour);
                filled[(y * size + x) as usize] = true;
            }
        }
    }

    // Any empty pixel touching a filled one becomes outline.
    for y in 0..size {
        for x in 0..size {
            if filled[(y * size + x) as usize] {
                continue;
            }

            let touches = [(-1, 0), (1, 0), (0, -1), (0, 1)].into_iter().any(|(dx, dy)| {
                let (nx, ny) = (x + dx, y + dy);
                nx >= 0
                    && ny >= 0
                    && nx < size
                    && ny < size
                    && filled[(ny * size + nx) as usize]
            });

            if touches {
                canvas.put(x, y, OUTLINE);
            }
        }
    }
}

/// Shade a point on a shape: lit from the upper left, darker at the edges.
fn lit(base: [f32; 3], nx: f32, ny: f32) -> [f32; 3] {
    let ramp = ramp_from(base);
    let tone = ((1.0 - nx) * 0.45 + (1.0 - ny) * 0.55 - 0.5) * 1.5;

    shade(&ramp, tone)
}

/// Draw the icon for an item.
pub fn item_icon(item: ItemId) -> Texture {
    let size = ICON_SIZE as i32;
    let mut canvas = Canvas::new(ICON_SIZE, ICON_SIZE);
    let definition = def(item);

    let span = (size - MARGIN * 2) as f32;
    let unit = |v: i32| (v - MARGIN) as f32 / span;

    match definition.kind {
        // A block is drawn as a solid cube face in the tile's own colour.
        ItemKind::Block(tile) => {
            let base = crate::art::tile_base_colour(tile);

            stamp(&mut canvas, |x, y| {
                // A slight bevel at the top reads as a cube rather than a square.
                if y < MARGIN + 3 && (x < MARGIN + 2 || x > size - MARGIN - 3) {
                    return None;
                }
                Some(lit(base, unit(x), unit(y)))
            });
        }

        ItemKind::Pickaxe { power } => {
            // Stronger picks are drawn in brighter metal.
            let metal = [
                110.0 + power * 26.0,
                96.0 + power * 30.0,
                90.0 + power * 12.0,
            ];
            let handle = [116.0, 82.0, 52.0];

            stamp(&mut canvas, |x, y| {
                let fx = unit(x);
                let fy = unit(y);

                // Handle: a diagonal shaft from lower left to upper right.
                let on_shaft = ((fx - fy) - 0.18).abs() < 0.11 && fy > 0.25;
                // Head: a curved bar across the top.
                let head_y = 0.26 - (fx - 0.5).powi(2) * 0.85;
                let on_head = (fy - head_y).abs() < 0.10 && (0.08..0.92).contains(&fx);

                if on_head {
                    Some(lit(metal, fx, fy))
                } else if on_shaft {
                    Some(lit(handle, fx, fy))
                } else {
                    None
                }
            });
        }

        ItemKind::Material => {
            let name = definition.name;

            if name.ends_with("Bar") {
                // An ingot: a trapezoid sitting on the floor of the cell.
                let metal = match name {
                    "Copper Bar" => [198.0, 122.0, 70.0],
                    "Iron Bar" => [176.0, 180.0, 190.0],
                    _ => [226.0, 186.0, 78.0],
                };

                stamp(&mut canvas, |x, y| {
                    let fx = unit(x);
                    let fy = unit(y);
                    if fy < 0.42 {
                        return None;
                    }
                    // Narrower at the top than the bottom.
                    let inset = (1.0 - fy) * 0.45;
                    if fx < inset || fx > 1.0 - inset {
                        return None;
                    }
                    Some(lit(metal, fx, fy))
                });
            } else if name.ends_with("Trophy") {
                // A faceted gem on a plinth.
                let gem = match name {
                    "Warden Trophy" => [120.0, 214.0, 224.0],
                    "Rimewyrm Trophy" => [150.0, 196.0, 240.0],
                    "Sand Colossus Trophy" => [226.0, 176.0, 96.0],
                    _ => [214.0, 162.0, 236.0],
                };

                stamp(&mut canvas, |x, y| {
                    let fx = unit(x);
                    let fy = unit(y);

                    if fy > 0.78 {
                        return Some(lit([96.0, 92.0, 108.0], fx, fy));
                    }
                    // Diamond silhouette.
                    let from_centre = (fx - 0.5).abs() + (fy - 0.38).abs();
                    (from_centre < 0.40).then(|| lit(gem, fx, fy))
                });
            } else if name == "Coal" {
                // A cluster of angular lumps.
                stamp(&mut canvas, |x, y| {
                    let fx = unit(x);
                    let fy = unit(y);

                    let lumps = [(0.36, 0.60, 0.30), (0.66, 0.52, 0.24), (0.52, 0.78, 0.22)];
                    lumps
                        .iter()
                        .any(|&(cx, cy, r)| (fx - cx).abs() + (fy - cy).abs() < r)
                        .then(|| lit([68.0, 66.0, 74.0], fx, fy))
                });
            } else {
                // Summoning tokens: a rune disc, one colour and one rune
                // shape per boss so they are told apart at a glance.
                let (tint, rune) = match name {
                    "Cracked Idol" => ([176.0, 168.0, 150.0], 0),
                    "Frozen Heart" => ([146.0, 196.0, 238.0], 1),
                    "Sunstone" => ([234.0, 174.0, 92.0], 2),
                    _ => ([170.0, 128.0, 212.0], 3),
                };
                let engraving = [tint[0] * 0.45, tint[1] * 0.42, tint[2] * 0.52];

                stamp(&mut canvas, |x, y| {
                    let fx = unit(x);
                    let fy = unit(y);
                    let dx = fx - 0.5;
                    let dy = fy - 0.5;
                    let radius = (dx * dx + dy * dy).sqrt();

                    if radius > 0.46 {
                        return None;
                    }

                    let engraved = match rune {
                        // A ring.
                        0 => (0.24..0.30).contains(&radius),
                        // A vertical bar.
                        1 => dx.abs() < 0.08 && radius < 0.34,
                        // A cross.
                        2 => (dx.abs() < 0.08 || dy.abs() < 0.08) && radius < 0.34,
                        // A diamond.
                        _ => (dx.abs() + dy.abs() - 0.28).abs() < 0.07,
                    };

                    Some(lit(if engraved { engraving } else { tint }, fx, fy))
                });
            }
        }
    }

    canvas.into_texture()
}

/// Edge length of a health heart, in pixels.
pub const HEART_SIZE: u32 = 24;

/// Draw a health heart, full or spent.
pub fn heart_icon(full: bool) -> Texture {
    let size = HEART_SIZE as i32;
    let mut canvas = Canvas::new(HEART_SIZE, HEART_SIZE);

    let colour = if full {
        [226.0, 68.0, 84.0]
    } else {
        // Spent hearts stay visible as empty sockets rather than vanishing,
        // so the player can see their maximum at a glance.
        [74.0, 54.0, 66.0]
    };

    for y in 1..size - 1 {
        for x in 1..size - 1 {
            let fx = (x as f32 + 0.5) / size as f32;
            let fy = (y as f32 + 0.5) / size as f32;

            // Classic implicit heart curve, scaled into the cell.
            let px = (fx - 0.5) * 2.3;
            let py = (fy - 0.56) * 2.3;
            let term = px * px + py * py - 0.45;

            if term * term * term - px * px * py * py * py > 0.0 {
                continue;
            }

            // Lit from the upper left, like everything else.
            let tone = ((1.0 - fx) * 0.45 + (1.0 - fy) * 0.55 - 0.5) * 1.4;
            canvas.put(x, y, shade(&ramp_from(colour), tone));
        }
    }

    canvas.into_texture()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::item::ITEMS;
    use crate::world::Tile;
    use crate::item::{COAL, COPPER_PICKAXE, GOLD_BAR, STONE, WARDEN_TROPHY};

    #[test]
    fn a_heart_is_drawn_at_the_declared_size() {
        let heart = heart_icon(true);

        assert_eq!(heart.width, HEART_SIZE);
        assert_eq!(heart.height, HEART_SIZE);
    }

    #[test]
    fn a_heart_is_a_shape_rather_than_a_filled_square() {
        let heart = heart_icon(true);
        let filled = opaque(&heart);
        let area = (HEART_SIZE * HEART_SIZE) as usize;

        assert!(filled > area / 6, "the heart is barely drawn");
        assert!(filled < area * 3 / 4, "the heart has no silhouette");
    }

    #[test]
    fn a_spent_heart_is_darker_than_a_full_one() {
        let brightness = |texture: &Texture| {
            let lit: Vec<f32> = texture
                .pixels
                .chunks_exact(4)
                .filter(|p| p[3] > 0)
                .map(|p| p[0] as f32 + p[1] as f32 + p[2] as f32)
                .collect();
            lit.iter().sum::<f32>() / lit.len() as f32
        };

        assert!(
            brightness(&heart_icon(false)) < brightness(&heart_icon(true)),
            "a spent heart should read as empty"
        );
    }

    #[test]
    fn a_spent_heart_is_still_visible_as_a_socket() {
        assert!(
            opaque(&heart_icon(false)) > 0,
            "losing health should not make the slot disappear"
        );
    }

    fn opaque(texture: &Texture) -> usize {
        texture
            .pixels
            .chunks_exact(4)
            .filter(|pixel| pixel[3] > 0)
            .count()
    }

    #[test]
    fn every_item_has_an_icon_of_the_right_size() {
        for index in 0..ITEMS.len() {
            let icon = item_icon(ItemId(index as u16));

            assert_eq!(icon.width, ICON_SIZE, "item {index} width");
            assert_eq!(icon.height, ICON_SIZE, "item {index} height");
        }
    }

    #[test]
    fn every_icon_draws_something_substantial() {
        let area = (ICON_SIZE * ICON_SIZE) as usize;

        for index in 0..ITEMS.len() {
            let icon = item_icon(ItemId(index as u16));
            let filled = opaque(&icon);

            assert!(
                filled > area / 8,
                "{} is nearly invisible at {filled} pixels",
                def(ItemId(index as u16)).name
            );
            assert!(
                filled < area,
                "{} fills its whole cell and has no silhouette",
                def(ItemId(index as u16)).name
            );
        }
    }

    #[test]
    fn icons_leave_a_margin_so_they_do_not_touch_in_a_row() {
        for index in 0..ITEMS.len() {
            let icon = item_icon(ItemId(index as u16));

            let edge_filled = (0..ICON_SIZE)
                .filter(|&x| icon.pixel(x, 0)[3] > 0 || icon.pixel(x, ICON_SIZE - 1)[3] > 0)
                .count();

            assert_eq!(
                edge_filled, 0,
                "{} runs to the edge of its cell",
                def(ItemId(index as u16)).name
            );
        }
    }

    #[test]
    fn different_items_have_different_icons() {
        let stone = item_icon(STONE);
        let coal = item_icon(COAL);
        let pickaxe = item_icon(COPPER_PICKAXE);

        assert_ne!(stone.pixels, coal.pixels);
        assert_ne!(stone.pixels, pickaxe.pixels);
        assert_ne!(coal.pixels, pickaxe.pixels);
    }

    #[test]
    fn block_icons_resemble_the_tile_they_place() {
        // A stone block icon should be broadly stone-coloured.
        let icon = item_icon(STONE);
        let expected = crate::art::tile_base_colour(Tile::Stone);

        let lit: Vec<[f32; 3]> = icon
            .pixels
            .chunks_exact(4)
            .filter(|p| p[3] > 0)
            .map(|p| [p[0] as f32, p[1] as f32, p[2] as f32])
            .collect();

        let mean = [
            lit.iter().map(|c| c[0]).sum::<f32>() / lit.len() as f32,
            lit.iter().map(|c| c[1]).sum::<f32>() / lit.len() as f32,
            lit.iter().map(|c| c[2]).sum::<f32>() / lit.len() as f32,
        ];

        let distance = ((mean[0] - expected[0]).powi(2)
            + (mean[1] - expected[1]).powi(2)
            + (mean[2] - expected[2]).powi(2))
        .sqrt();

        assert!(
            distance < 90.0,
            "a stone block icon averaged {mean:?}, nothing like stone {expected:?}"
        );
    }

    #[test]
    fn tools_look_different_from_blocks() {
        // Tools are drawn as a shape on a transparent field, so they cover
        // noticeably less of the cell than a solid block does.
        let block = opaque(&item_icon(STONE));
        let tool = opaque(&item_icon(COPPER_PICKAXE));

        assert!(
            tool < block,
            "a pickaxe ({tool}) should not fill as much as a block ({block})"
        );
    }

    #[test]
    fn every_icon_is_outlined_so_it_reads_on_any_background() {
        for index in 0..ITEMS.len() {
            let icon = item_icon(ItemId(index as u16));

            let dark = icon
                .pixels
                .chunks_exact(4)
                .filter(|p| p[3] > 0 && p[0] < 60 && p[1] < 60 && p[2] < 70)
                .count();

            assert!(
                dark > 12,
                "{} has no outline to separate it from the slot",
                def(ItemId(index as u16)).name
            );
        }
    }

    #[test]
    fn no_icon_pixel_is_pure_black_or_pure_white() {
        for index in 0..ITEMS.len() {
            for pixel in item_icon(ItemId(index as u16)).pixels.chunks_exact(4) {
                if pixel[3] == 0 {
                    continue;
                }
                assert!(!(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0));
                assert!(!(pixel[0] == 255 && pixel[1] == 255 && pixel[2] == 255));
            }
        }
    }

    #[test]
    fn bars_and_trophies_are_distinguishable_from_one_another() {
        assert_ne!(item_icon(GOLD_BAR).pixels, item_icon(WARDEN_TROPHY).pixels);
    }

    #[test]
    fn icon_drawing_is_deterministic() {
        assert_eq!(item_icon(STONE), item_icon(STONE));
    }

    #[test]
    fn every_kind_of_item_is_handled() {
        // Guards against a new ItemKind falling through to a blank cell.
        for index in 0..ITEMS.len() {
            let item = ItemId(index as u16);
            let icon = item_icon(item);

            let filled = opaque(&icon);
            match def(item).kind {
                ItemKind::Block(_) | ItemKind::Pickaxe { .. } | ItemKind::Material => {
                    assert!(filled > 0, "{} drew nothing", def(item).name)
                }
            }
        }
    }
}
