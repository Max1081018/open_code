//! Shared drawing primitives.
//!
//! Characters and scenery both go through these, so everything drawn in the
//! game obeys the same lighting and shading rules and reads as one style.

use crate::art::Texture;
use crate::noise::hash01;

/// Darkest any channel may go. Pure black looks cheap; shadows keep a floor.
const SHADE_FLOOR: f32 = 12.0;

/// Brightest any channel may go, for the same reason in reverse.
const SHADE_CEILING: f32 = 250.0;

/// A material's three tones. Shadows are blue-shifted and highlights warm,
/// which is most of what makes generated art read as hand-made.
pub(crate) struct Ramp {
    pub shadow: [f32; 3],
    pub base: [f32; 3],
    pub highlight: [f32; 3],
}

pub(crate) fn ramp_from(base: [f32; 3]) -> Ramp {
    Ramp {
        shadow: [
            base[0] * 0.46,
            base[1] * 0.52,
            base[2] * 0.68 + 12.0,
        ],
        base,
        highlight: [
            base[0] * 1.16 + 24.0,
            base[1] * 1.12 + 16.0,
            base[2] * 1.04 + 4.0,
        ],
    }
}

/// Pick a tone along the ramp. `t` runs -1 (shadow) to +1 (highlight).
pub(crate) fn shade(ramp: &Ramp, t: f32) -> [f32; 3] {
    let t = t.clamp(-1.0, 1.0);

    let mut out = [0.0; 3];
    for channel in 0..3 {
        let value = if t < 0.0 {
            ramp.base[channel] + (ramp.base[channel] - ramp.shadow[channel]) * t
        } else {
            ramp.base[channel] + (ramp.highlight[channel] - ramp.base[channel]) * t
        };
        out[channel] = value.clamp(SHADE_FLOOR, SHADE_CEILING);
    }
    out
}

/// A transparent surface to assemble a character on.
pub(crate) struct Canvas {
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
}

impl Canvas {
    pub(crate) fn new(width: u32, height: u32) -> Canvas {
        Canvas {
            width,
            height,
            pixels: vec![0; (width * height * 4) as usize],
        }
    }

    pub(crate) fn put(&mut self, x: i32, y: i32, rgb: [f32; 3]) {
        if x < 0 || y < 0 || x >= self.width as i32 || y >= self.height as i32 {
            return;
        }

        let index = ((y as u32 * self.width + x as u32) * 4) as usize;
        self.pixels[index] = rgb[0] as u8;
        self.pixels[index + 1] = rgb[1] as u8;
        self.pixels[index + 2] = rgb[2] as u8;
        self.pixels[index + 3] = 255;
    }

    pub(crate) fn into_texture(self) -> Texture {
        Texture {
            width: self.width,
            height: self.height,
            pixels: self.pixels,
        }
    }
}

/// Distance from `(px, py)` to the nearest edge of a rounded rectangle, or
/// `None` if the point lies outside it.
pub(crate) fn rounded_inset(px: i32, py: i32, w: i32, h: i32, radius: f32) -> Option<f32> {
    if w <= 0 || h <= 0 {
        return None;
    }

    let fx = px as f32 + 0.5;
    let fy = py as f32 + 0.5;

    if fx < 0.0 || fy < 0.0 || fx > w as f32 || fy > h as f32 {
        return None;
    }

    // Distance to the nearer edge on each axis.
    let dx = fx.min(w as f32 - fx);
    let dy = fy.min(h as f32 - fy);

    // Inside a corner square, fall back to a circular test.
    if dx < radius && dy < radius {
        let offset_x = radius - dx;
        let offset_y = radius - dy;
        let distance = (offset_x * offset_x + offset_y * offset_y).sqrt();

        if distance > radius {
            return None;
        }
        return Some(radius - distance);
    }

    Some(dx.min(dy))
}

/// Draw one shaded body part.
#[allow(clippy::too_many_arguments)]
pub(crate) fn draw_part(
    canvas: &mut Canvas,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    radius: f32,
    base: [f32; 3],
    seed: u64,
) {
    let ramp = ramp_from(base);

    for py in 0..h {
        for px in 0..w {
            let Some(inset) = rounded_inset(px, py, w, h, radius) else {
                continue;
            };

            let nx = (px as f32 + 0.5) / w as f32;
            let ny = (py as f32 + 0.5) / h as f32;

            // One light, upper left.
            let lit = (1.0 - nx) * 0.45 + (1.0 - ny) * 0.55;
            let mut tone = (lit - 0.5) * 1.7;

            // Darken toward the outline so parts read as rounded volumes.
            let rim = (inset / 2.5).min(1.0);
            tone -= (1.0 - rim) * 0.75;

            // Grain, so nothing is a flat fill.
            let grain = hash01(seed, (py * w + px) as i64) - 0.5;
            tone += grain * 0.20;

            canvas.put(x + px, y + py, shade(&ramp, tone));
        }
    }
}

/// Draw an arm or leg as a column that pivots from its top.
///
/// `sway` displaces the *far* end only, so the limb shears rather than
/// sliding bodily sideways. Translating a whole arm detaches it from the
/// shoulder, which is the single most obvious tell of a cheap sprite.
#[allow(clippy::too_many_arguments)]
pub(crate) fn draw_limb(
    canvas: &mut Canvas,
    top_x: i32,
    top_y: i32,
    w: i32,
    h: i32,
    sway: i32,
    base: [f32; 3],
    cap: [f32; 3],
    cap_h: i32,
    seed: u64,
) {
    let ramp = ramp_from(base);
    let cap_ramp = ramp_from(cap);

    for py in 0..h {
        // Shear grows toward the far end, so the joint stays put.
        let along = py as f32 / (h - 1).max(1) as f32;
        let offset = (sway as f32 * along).round() as i32;

        let is_cap = py >= h - cap_h;
        let active = if is_cap { &cap_ramp } else { &ramp };

        // Hands and feet are a touch wider than the limb they finish.
        let widen = if is_cap { 1 } else { 0 };

        for px in -widen..w + widen {
            let edge_x = px.min(w - 1 - px) + widen;
            if edge_x < 0 {
                continue;
            }

            let nx = (px as f32 + 0.5) / w as f32;
            let lit = (1.0 - nx) * 0.5 + (1.0 - along) * 0.5;
            let mut tone = (lit - 0.5) * 1.5;

            // Round the column off at its sides and its far end.
            let rim = (edge_x as f32 / 1.8).min(1.0);
            tone -= (1.0 - rim) * 0.7;
            if py == h - 1 || py == 0 {
                tone -= 0.3;
            }

            let grain = hash01(seed, (py * (w + 2) + px) as i64) - 0.5;
            tone += grain * 0.18;

            canvas.put(top_x + px + offset, top_y + py, shade(active, tone));
        }
    }
}

