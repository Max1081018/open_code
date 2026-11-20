//! Procedural character sprites: bodies built from parts, with faces.
//!
//! Characters are assembled from head, torso, arms and legs so animation can
//! move the parts independently, rather than being drawn as one blob. Eyes
//! and mouth are drawn last, on top of the head.

use crate::anim::AnimState;
use crate::art::Texture;
use crate::noise::hash01;

/// Character canvas width, in source pixels.
pub const CHAR_W: u32 = 40;

/// Character canvas height, in source pixels. Feet sit on the bottom row.
pub const CHAR_H: u32 = 88;

/// How a character is proportioned.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Build {
    /// Upright, two arms, two legs: the player and most humanoids.
    Humanoid,
    /// Squat and limbless, like a slime.
    Blob,
    /// Broad and heavy, with oversized arms.
    Hulk,
}

/// The colours and shape of one character.
#[derive(Clone, Copy, Debug)]
pub struct CharacterStyle {
    pub build: Build,
    /// Head and hands.
    pub skin: [f32; 3],
    /// Torso covering.
    pub cloth: [f32; 3],
    /// Legs.
    pub trouser: [f32; 3],
    /// Hair or crest on top of the head.
    pub hair: [f32; 3],
    /// Iris colour.
    pub eye: [f32; 3],
    /// Staggers blinking and texture noise between characters.
    pub seed: u64,
}

/// What the mouth is doing.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum Mouth {
    /// A level line.
    #[default]
    Neutral,
    /// Open, for effort or falling.
    Open,
    /// Pressed thin, for pain.
    Tight,
}

/// Where each body part sits on a given frame.
#[derive(Clone, Copy, Debug, Default)]
pub struct Pose {
    /// Vertical bob of the whole body, in pixels. Positive is down.
    pub body_dy: i32,
    /// Extra head movement on top of the body bob.
    pub head_dy: i32,
    /// Horizontal lean of the upper body.
    pub lean: i32,
    pub arm_near: (i32, i32),
    pub arm_far: (i32, i32),
    pub leg_near: (i32, i32),
    pub leg_far: (i32, i32),
    pub mouth: Mouth,
}

/// The player's look.
pub fn player_style() -> CharacterStyle {
    CharacterStyle {
        build: Build::Humanoid,
        skin: [232.0, 186.0, 152.0],
        cloth: [78.0, 102.0, 162.0],
        trouser: [66.0, 62.0, 84.0],
        hair: [96.0, 62.0, 40.0],
        eye: [48.0, 72.0, 112.0],
        seed: 0x9001,
    }
}

/// Darkest any channel may go. Pure black looks cheap; shadows keep a floor.
const SHADE_FLOOR: f32 = 12.0;

/// Brightest any channel may go, for the same reason in reverse.
const SHADE_CEILING: f32 = 250.0;

/// A material's three tones. Shadows are blue-shifted and highlights warm,
/// which is most of what makes generated art read as hand-made.
struct Ramp {
    shadow: [f32; 3],
    base: [f32; 3],
    highlight: [f32; 3],
}

fn ramp_from(base: [f32; 3]) -> Ramp {
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
fn shade(ramp: &Ramp, t: f32) -> [f32; 3] {
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
struct Canvas {
    width: u32,
    height: u32,
    pixels: Vec<u8>,
}

impl Canvas {
    fn new(width: u32, height: u32) -> Canvas {
        Canvas {
            width,
            height,
            pixels: vec![0; (width * height * 4) as usize],
        }
    }

    fn put(&mut self, x: i32, y: i32, rgb: [f32; 3]) {
        if x < 0 || y < 0 || x >= self.width as i32 || y >= self.height as i32 {
            return;
        }

        let index = ((y as u32 * self.width + x as u32) * 4) as usize;
        self.pixels[index] = rgb[0] as u8;
        self.pixels[index + 1] = rgb[1] as u8;
        self.pixels[index + 2] = rgb[2] as u8;
        self.pixels[index + 3] = 255;
    }

    fn into_texture(self) -> Texture {
        Texture {
            width: self.width,
            height: self.height,
            pixels: self.pixels,
        }
    }
}

/// Distance from `(px, py)` to the nearest edge of a rounded rectangle, or
/// `None` if the point lies outside it.
fn rounded_inset(px: i32, py: i32, w: i32, h: i32, radius: f32) -> Option<f32> {
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
fn draw_part(
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
fn draw_limb(
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

/// Layout of a humanoid on the character canvas.
mod layout {
    pub const CENTRE_X: i32 = 20;

    pub const HEAD_X: i32 = 8;
    pub const HEAD_Y: i32 = 6;
    pub const HEAD_W: i32 = 24;
    pub const HEAD_H: i32 = 24;

    pub const TORSO_X: i32 = 10;
    pub const TORSO_Y: i32 = 29;
    pub const TORSO_W: i32 = 20;
    pub const TORSO_H: i32 = 29;

    pub const LEG_Y: i32 = 56;
    pub const LEG_W: i32 = 8;
    pub const LEG_H: i32 = 32;
    pub const LEG_FAR_X: i32 = 11;
    pub const LEG_NEAR_X: i32 = 21;

    pub const ARM_Y: i32 = 32;
    pub const ARM_W: i32 = 7;
    pub const ARM_H: i32 = 26;
    pub const ARM_FAR_X: i32 = 5;
    pub const ARM_NEAR_X: i32 = 28;

    /// Eye centres, relative to the canvas.
    pub const EYE_Y: i32 = 17;
    pub const EYE_LEFT_X: i32 = 15;
    pub const EYE_RIGHT_X: i32 = 25;
    pub const EYE_W: i32 = 5;
    pub const EYE_H: i32 = 5;

    pub const MOUTH_Y: i32 = 24;
}

/// The pose for one frame of one clip.
pub fn pose(state: AnimState, frame: u32) -> Pose {
    let index = frame as usize;

    /// Pick the entry for this frame, holding the last one if asked for more.
    fn at(table: &[i32], index: usize) -> i32 {
        *table.get(index).or(table.last()).unwrap_or(&0)
    }

    match state {
        AnimState::Idle => Pose {
            body_dy: at(&[0, 1, 1, 0], index),
            head_dy: at(&[0, 0, 1, 0], index),
            arm_near: (0, at(&[0, 0, 1, 1], index)),
            arm_far: (0, at(&[0, 1, 1, 0], index)),
            mouth: Mouth::Neutral,
            ..Pose::default()
        },

        AnimState::Walk | AnimState::Run => {
            // Run reuses the walk poses with a longer stride and a lean.
            let scale = if state == AnimState::Run { 2 } else { 1 };

            let swing = at(&[4, 2, -2, -4, -2, 2], index) * scale;
            let counter = at(&[-4, -2, 2, 4, 2, -2], index) * scale;

            Pose {
                body_dy: at(&[0, 1, 0, 0, 1, 0], index),
                head_dy: 0,
                lean: if state == AnimState::Run { 2 } else { 0 },
                // Arms counter-swing against the legs.
                arm_near: (counter, 0),
                arm_far: (swing, 0),
                leg_near: (swing, at(&[-1, 0, 0, -1, 0, 0], index)),
                leg_far: (counter, at(&[0, -1, 0, 0, -1, 0], index)),
                mouth: Mouth::Neutral,
            }
        }

        AnimState::Jump => Pose {
            body_dy: -1,
            arm_near: (2, -6),
            arm_far: (-2, -5),
            leg_near: (2, -4),
            leg_far: (-3, -2),
            mouth: Mouth::Open,
            ..Pose::default()
        },

        AnimState::Fall => Pose {
            body_dy: 1,
            arm_near: (4, -3),
            arm_far: (-4, -3),
            leg_near: (4, 0),
            leg_far: (-4, 0),
            mouth: Mouth::Open,
            ..Pose::default()
        },

        AnimState::Mine => Pose {
            body_dy: at(&[0, 1, 2, 1], index),
            head_dy: at(&[0, 1, 1, 0], index),
            lean: at(&[0, 1, 2, 1], index),
            // The near arm swings back, then drives down on frame 2.
            arm_near: (
                at(&[-7, 1, 10, 4], index),
                at(&[-5, -2, 2, -1], index),
            ),
            arm_far: (-2, at(&[0, 1, 2, 1], index)),
            mouth: Mouth::Open,
            ..Pose::default()
        },

        AnimState::Attack => Pose {
            // Telegraph back, strike forward, follow through, recover.
            body_dy: at(&[0, 0, 1, 0], index),
            lean: at(&[-2, 1, 3, 1], index),
            arm_near: (
                at(&[-8, 5, 13, 5], index),
                at(&[-3, -4, -2, -2], index),
            ),
            arm_far: (at(&[3, -2, -4, -2], index), 0),
            leg_near: (at(&[-1, 2, 3, 1], index), 0),
            leg_far: (at(&[1, -1, -2, -1], index), 0),
            mouth: Mouth::Open,
            ..Pose::default()
        },

        AnimState::Hurt => Pose {
            body_dy: at(&[1, 2], index),
            head_dy: at(&[1, 1], index),
            lean: at(&[-3, -4], index),
            arm_near: (-3, -2),
            arm_far: (-4, -1),
            leg_near: (-2, 0),
            leg_far: (2, 0),
            mouth: Mouth::Tight,
        },

        AnimState::Death => Pose {
            // Buckle and topple, staying on the canvas rather than sinking
            // out through the bottom of it.
            body_dy: at(&[1, 4, 7, 9, 10], index),
            head_dy: at(&[1, 3, 5, 7, 8], index),
            lean: at(&[-2, -5, -8, -11, -13], index),
            arm_near: (at(&[-2, -5, -9, -12, -14], index), 0),
            arm_far: (at(&[2, 4, 7, 9, 10], index), 0),
            leg_near: (at(&[2, 5, 8, 10, 11], index), 0),
            leg_far: (at(&[-2, -4, -6, -8, -9], index), 0),
            mouth: Mouth::Tight,
        },
    }
}

/// Draw the eyes and mouth onto an already-drawn head.
fn draw_face(
    canvas: &mut Canvas,
    style: &CharacterStyle,
    pose: &Pose,
    face_dy: i32,
    blinking: bool,
) {
    use layout::*;

    let lid = ramp_from(style.skin).shadow;
    let sclera = [238.0, 236.0, 228.0];
    let iris = style.eye;
    let pupil = [
        iris[0] * 0.35 + 10.0,
        iris[1] * 0.35 + 10.0,
        iris[2] * 0.35 + 14.0,
    ];

    for centre_x in [EYE_LEFT_X + pose.lean, EYE_RIGHT_X + pose.lean] {
        let x0 = centre_x - EYE_W / 2;
        let y0 = EYE_Y + face_dy - EYE_H / 2;

        if blinking {
            // A closed lid: one dark line across the socket.
            for dx in 0..EYE_W {
                canvas.put(x0 + dx, y0 + EYE_H / 2, lid);
            }
            continue;
        }

        for dy in 0..EYE_H {
            for dx in 0..EYE_W {
                let Some(_) = rounded_inset(dx, dy, EYE_W, EYE_H, 2.0) else {
                    continue;
                };

                // Iris fills the middle of the eye, sclera the corners.
                let in_iris = dx >= 1 && dx <= EYE_W - 2 && dy >= 1 && dy <= EYE_H - 2;
                let colour = if dx == EYE_W / 2 && dy == EYE_H / 2 {
                    pupil
                } else if in_iris {
                    iris
                } else {
                    sclera
                };

                canvas.put(x0 + dx, y0 + dy, colour);
            }
        }
    }

    // Mouth.
    let mouth_y = MOUTH_Y + face_dy;
    let mouth_x = CENTRE_X + pose.lean;

    match pose.mouth {
        Mouth::Neutral => {
            for dx in -3..=3 {
                canvas.put(mouth_x + dx, mouth_y, lid);
            }
        }
        Mouth::Tight => {
            for dx in -2..=2 {
                canvas.put(mouth_x + dx, mouth_y, lid);
            }
        }
        Mouth::Open => {
            let inner = [58.0, 32.0, 38.0];
            for dy in 0..4 {
                for dx in -2..=2 {
                    // Rounded: pull in the corners on the outer rows.
                    if (dy == 0 || dy == 3) && (dx as i32).abs() == 2 {
                        continue;
                    }
                    canvas.put(mouth_x + dx, mouth_y + dy - 1, inner);
                }
            }
        }
    }
}

/// Draw one frame of a character.
pub fn character_frame(
    style: &CharacterStyle,
    state: AnimState,
    frame: u32,
    blinking: bool,
) -> Texture {
    use layout::*;

    let mut canvas = Canvas::new(CHAR_W, CHAR_H);
    let pose = pose(state, frame);
    let seed = style.seed;

    if style.build == Build::Blob {
        // A blob is one squat body that sits low, with a face on it.
        let w = 34;
        let h = 26;
        let x = CENTRE_X - w / 2;
        let y = CHAR_H as i32 - h + pose.body_dy.min(0);

        draw_part(&mut canvas, x, y, w, h, 12.0, style.cloth, seed);

        // Eyes sit on the upper half of the blob.
        let eye_y = y + 8;
        for centre_x in [CENTRE_X - 7, CENTRE_X + 7] {
            if blinking {
                for dx in -2..=2 {
                    canvas.put(centre_x + dx, eye_y, ramp_from(style.cloth).shadow);
                }
            } else {
                for dy in -2..=2i32 {
                    for dx in -2..=2i32 {
                        if dx.abs() + dy.abs() > 3 {
                            continue;
                        }
                        let colour = if dx == 0 && dy == 0 {
                            [24.0, 20.0, 30.0]
                        } else {
                            [238.0, 236.0, 228.0]
                        };
                        canvas.put(centre_x + dx, eye_y + dy, colour);
                    }
                }
            }
        }

        return canvas.into_texture();
    }

    // Hulks are broader and squatter than the standard humanoid.
    let bulk = if style.build == Build::Hulk { 6 } else { 0 };

    let body_dy = pose.body_dy;
    let head_dy = body_dy + pose.head_dy;

    // Shadowed variants, for the limbs on the far side of the body.
    let far_cloth = ramp_from(style.cloth).shadow;
    let far_trouser = ramp_from(style.trouser).shadow;
    let far_skin = ramp_from(style.skin).shadow;
    let boot = [
        style.trouser[0] * 0.55 + 18.0,
        style.trouser[1] * 0.5 + 14.0,
        style.trouser[2] * 0.5 + 20.0,
    ];

    // Back to front: far limbs, near limbs, torso, near arm, neck, head.
    draw_limb(
        &mut canvas,
        ARM_FAR_X + pose.lean - bulk,
        ARM_Y + pose.arm_far.1 + body_dy,
        ARM_W + bulk,
        ARM_H,
        pose.arm_far.0,
        far_cloth,
        far_skin,
        4,
        seed ^ 0x11,
    );

    // Legs shorten rather than running off the bottom of the canvas, so a
    // sinking death pose keeps its feet instead of having them clipped away.
    let leg_height = |top_y: i32| (CHAR_H as i32 - top_y).clamp(6, LEG_H);

    let leg_far_y = LEG_Y + pose.leg_far.1 + body_dy;
    draw_limb(
        &mut canvas,
        LEG_FAR_X,
        leg_far_y,
        LEG_W,
        leg_height(leg_far_y),
        pose.leg_far.0,
        far_trouser,
        ramp_from(boot).shadow,
        4,
        seed ^ 0x22,
    );

    let leg_near_y = LEG_Y + pose.leg_near.1 + body_dy;
    draw_limb(
        &mut canvas,
        LEG_NEAR_X,
        leg_near_y,
        LEG_W,
        leg_height(leg_near_y),
        pose.leg_near.0,
        style.trouser,
        boot,
        4,
        seed ^ 0x33,
    );

    draw_part(
        &mut canvas,
        TORSO_X + pose.lean - bulk / 2,
        TORSO_Y + body_dy,
        TORSO_W + bulk,
        TORSO_H,
        5.0,
        style.cloth,
        seed ^ 0x44,
    );

    draw_limb(
        &mut canvas,
        ARM_NEAR_X + pose.lean,
        ARM_Y + pose.arm_near.1 + body_dy,
        ARM_W + bulk,
        ARM_H,
        pose.arm_near.0,
        style.cloth,
        style.skin,
        4,
        seed ^ 0x55,
    );

    // A short neck, so the head sits on the body instead of floating.
    draw_part(
        &mut canvas,
        CENTRE_X - 4 + pose.lean,
        HEAD_Y + HEAD_H - 3 + head_dy,
        8,
        6,
        2.0,
        far_skin,
        seed ^ 0x88,
    );

    draw_part(
        &mut canvas,
        HEAD_X + pose.lean,
        HEAD_Y + head_dy,
        HEAD_W,
        HEAD_H,
        7.0,
        style.skin,
        seed ^ 0x66,
    );

    // Hair sits as a cap over the top of the head.
    draw_part(
        &mut canvas,
        HEAD_X + pose.lean + 1,
        HEAD_Y + head_dy,
        HEAD_W - 2,
        9,
        4.0,
        style.hair,
        seed ^ 0x77,
    );

    draw_face(&mut canvas, style, &pose, head_dy, blinking);

    canvas.into_texture()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::anim::{clip, ALL_STATES};

    fn frame_of(state: AnimState, frame: u32) -> Texture {
        character_frame(&player_style(), state, frame, false)
    }

    /// Count pixels that are not fully transparent.
    fn opaque_count(texture: &Texture) -> usize {
        texture
            .pixels
            .chunks_exact(4)
            .filter(|pixel| pixel[3] > 0)
            .count()
    }

    fn pixels_differ(a: &Texture, b: &Texture) -> usize {
        a.pixels
            .chunks_exact(4)
            .zip(b.pixels.chunks_exact(4))
            .filter(|(x, y)| x != y)
            .count()
    }

    #[test]
    fn frames_are_the_configured_character_size() {
        let texture = frame_of(AnimState::Idle, 0);

        assert_eq!(texture.width, CHAR_W);
        assert_eq!(texture.height, CHAR_H);
        assert_eq!(texture.pixels.len(), (CHAR_W * CHAR_H * 4) as usize);
    }

    #[test]
    fn every_state_and_frame_draws_without_panicking() {
        for state in ALL_STATES {
            for frame in 0..clip(state).frames {
                let texture = character_frame(&player_style(), state, frame, false);

                assert!(
                    opaque_count(&texture) > 200,
                    "{state:?} frame {frame} drew almost nothing"
                );
            }
        }
    }

    #[test]
    fn the_character_does_not_fill_the_whole_canvas() {
        let texture = frame_of(AnimState::Idle, 0);
        let total = (CHAR_W * CHAR_H) as usize;

        assert!(
            opaque_count(&texture) < total * 3 / 4,
            "a character should have space around it, not be a solid block"
        );
    }

    #[test]
    fn the_character_stands_on_the_bottom_of_the_canvas() {
        let texture = frame_of(AnimState::Idle, 0);

        let bottom_row_filled = (0..CHAR_W)
            .filter(|&x| texture.pixel(x, CHAR_H - 1)[3] > 0)
            .count();

        assert!(
            bottom_row_filled > 0,
            "feet must touch the bottom row, or the character floats"
        );
    }

    #[test]
    fn the_top_of_the_canvas_is_clear_of_the_character() {
        let texture = frame_of(AnimState::Idle, 0);

        let top_row_filled = (0..CHAR_W)
            .filter(|&x| texture.pixel(x, 0)[3] > 0)
            .count();

        assert_eq!(
            top_row_filled, 0,
            "leave headroom so a bob or hat does not clip"
        );
    }

    #[test]
    fn the_character_is_roughly_centred_horizontally() {
        let texture = frame_of(AnimState::Idle, 0);

        let mut weighted = 0.0;
        let mut total = 0.0;
        for y in 0..CHAR_H {
            for x in 0..CHAR_W {
                if texture.pixel(x, y)[3] > 0 {
                    weighted += x as f32;
                    total += 1.0;
                }
            }
        }

        let centre = weighted / total;
        let expected = CHAR_W as f32 / 2.0;

        assert!(
            (centre - expected).abs() < 4.0,
            "centre of mass at {centre:.1}, expected near {expected:.1}"
        );
    }

    #[test]
    fn walk_frames_are_visibly_different_from_one_another() {
        let first = frame_of(AnimState::Walk, 0);
        let third = frame_of(AnimState::Walk, 2);

        assert!(
            pixels_differ(&first, &third) > 60,
            "a walk cycle whose frames look alike is not an animation"
        );
    }

    #[test]
    fn different_states_look_different() {
        let idle = frame_of(AnimState::Idle, 0);
        let attack = frame_of(AnimState::Attack, 1);

        assert!(
            pixels_differ(&idle, &attack) > 60,
            "attacking should not look like standing still"
        );
    }

    #[test]
    fn blinking_changes_only_a_small_part_of_the_face() {
        let open = character_frame(&player_style(), AnimState::Idle, 0, false);
        let shut = character_frame(&player_style(), AnimState::Idle, 0, true);

        let changed = pixels_differ(&open, &shut);

        assert!(changed > 0, "blinking should actually close the eyes");
        assert!(
            changed < 120,
            "{changed} pixels changed; a blink should move eyes, not the body"
        );
    }

    #[test]
    fn the_face_carries_eye_coloured_pixels() {
        let texture = frame_of(AnimState::Idle, 0);
        let eye = player_style().eye;

        let found = texture.pixels.chunks_exact(4).any(|pixel| {
            pixel[3] > 0
                && (pixel[0] as f32 - eye[0]).abs() < 60.0
                && (pixel[1] as f32 - eye[1]).abs() < 60.0
                && (pixel[2] as f32 - eye[2]).abs() < 60.0
        });

        assert!(found, "the character should have visible eyes");
    }

    #[test]
    fn the_mouth_changes_shape_with_state() {
        assert_eq!(pose(AnimState::Idle, 0).mouth, Mouth::Neutral);
        assert_eq!(pose(AnimState::Hurt, 0).mouth, Mouth::Tight);
        assert_eq!(pose(AnimState::Attack, 1).mouth, Mouth::Open);
    }

    #[test]
    fn limbs_actually_swing_through_a_walk_cycle() {
        let swings: Vec<i32> = (0..clip(AnimState::Walk).frames)
            .map(|frame| pose(AnimState::Walk, frame).leg_near.0)
            .collect();

        let min = *swings.iter().min().unwrap();
        let max = *swings.iter().max().unwrap();

        assert!(
            max - min >= 4,
            "legs barely move across the cycle: {swings:?}"
        );
    }

    #[test]
    fn opposite_limbs_swing_in_opposition() {
        // A walk where both legs move together is a hop, not a walk.
        let opposed = (0..clip(AnimState::Walk).frames)
            .filter(|&frame| {
                let pose = pose(AnimState::Walk, frame);
                pose.leg_near.0.signum() != pose.leg_far.0.signum()
            })
            .count();

        assert!(
            opposed >= 4,
            "legs should counter-swing on most frames, only {opposed} did"
        );
    }

    #[test]
    fn no_pixel_is_pure_black_or_pure_white() {
        // An art-direction rule: shadows are blue-shifted, highlights warm.
        for state in ALL_STATES {
            let texture = character_frame(&player_style(), state, 0, false);

            for pixel in texture.pixels.chunks_exact(4) {
                if pixel[3] == 0 {
                    continue;
                }

                let flat_black = pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0;
                let flat_white = pixel[0] == 255 && pixel[1] == 255 && pixel[2] == 255;

                assert!(!flat_black, "{state:?} has a pure black pixel");
                assert!(!flat_white, "{state:?} has a pure white pixel");
            }
        }
    }

    #[test]
    fn shading_gives_every_material_more_than_one_tone() {
        let texture = frame_of(AnimState::Idle, 0);

        let tones: std::collections::BTreeSet<[u8; 3]> = texture
            .pixels
            .chunks_exact(4)
            .filter(|pixel| pixel[3] > 0)
            .map(|pixel| [pixel[0], pixel[1], pixel[2]])
            .collect();

        assert!(
            tones.len() > 20,
            "only {} distinct colours; the sprite is flat",
            tones.len()
        );
    }

    #[test]
    fn generation_is_deterministic() {
        assert_eq!(frame_of(AnimState::Walk, 2), frame_of(AnimState::Walk, 2));
    }

    #[test]
    fn two_characters_with_different_styles_look_different() {
        let mut other = player_style();
        other.cloth = [170.0, 60.0, 60.0];

        let a = character_frame(&player_style(), AnimState::Idle, 0, false);
        let b = character_frame(&other, AnimState::Idle, 0, false);

        assert!(pixels_differ(&a, &b) > 40, "recolouring should be visible");
    }

    #[test]
    fn a_blob_has_no_legs_to_swing() {
        let mut blob = player_style();
        blob.build = Build::Blob;

        let texture = character_frame(&blob, AnimState::Walk, 0, false);

        // A blob is squat: nothing should be drawn in the top quarter.
        let top_quarter_filled = (0..CHAR_H / 4)
            .flat_map(|y| (0..CHAR_W).map(move |x| (x, y)))
            .filter(|&(x, y)| texture.pixel(x, y)[3] > 0)
            .count();

        assert_eq!(
            top_quarter_filled, 0,
            "a blob should sit low, not stand upright"
        );
    }
}
