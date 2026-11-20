//! Procedural character sprites: bodies built from parts, with faces.
//!
//! Characters are assembled from head, torso, arms and legs so animation can
//! move the parts independently, rather than being drawn as one blob. Eyes
//! and mouth are drawn last, on top of the head.

use crate::anim::AnimState;
use crate::art::Texture;
use crate::paint::{
    draw_disc, draw_limb, draw_part, draw_spike, draw_taper, ramp_from, rounded_inset, Canvas,
};

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
    /// A floating armoured eye under a hood, with no legs at all.
    Sentinel,
    /// A segmented serpent rearing up out of the ground in an S-curve.
    Wyrm,
    /// A slab of animated stone: shoulders wider than its stance, with a
    /// head sunk between them.
    Colossus,
    /// A gaunt crowned figure with a cape that flares to the floor.
    Crowned,
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

/// How an enemy kind looks. Indexed by `EnemyKindId`.
pub fn enemy_style(kind: crate::enemy::EnemyKindId) -> CharacterStyle {
    match kind.0 {
        // Slime: a squat green blob.
        0 => CharacterStyle {
            build: Build::Blob,
            skin: [120.0, 200.0, 110.0],
            cloth: [96.0, 186.0, 96.0],
            trouser: [76.0, 150.0, 78.0],
            hair: [96.0, 186.0, 96.0],
            eye: [40.0, 70.0, 48.0],
            seed: 0xE000,
        },
        // Cave Crawler: wiry and rust-coloured.
        1 => CharacterStyle {
            build: Build::Humanoid,
            skin: [176.0, 132.0, 104.0],
            cloth: [182.0, 104.0, 56.0],
            trouser: [116.0, 72.0, 44.0],
            hair: [84.0, 52.0, 34.0],
            eye: [222.0, 176.0, 70.0],
            seed: 0xE001,
        },
        // Deep Stalker: tall and violet, with pale eyes.
        2 => CharacterStyle {
            build: Build::Humanoid,
            skin: [150.0, 126.0, 168.0],
            cloth: [118.0, 70.0, 150.0],
            trouser: [72.0, 46.0, 96.0],
            hair: [54.0, 34.0, 72.0],
            eye: [226.0, 230.0, 240.0],
            seed: 0xE002,
        },
        // Gloom Brute: heavy, red, and broad.
        _ => CharacterStyle {
            build: Build::Hulk,
            skin: [182.0, 108.0, 96.0],
            cloth: [158.0, 52.0, 48.0],
            trouser: [94.0, 38.0, 40.0],
            hair: [66.0, 28.0, 30.0],
            eye: [244.0, 196.0, 80.0],
            seed: 0xE003,
        },
    }
}

/// How tall a creature is drawn, in tiles.
///
/// Drawn size is deliberately allowed to differ a little from the physics
/// box: a slime that collides as a 1.8-tile body still looks absurd drawn
/// that tall, and a brute should loom.
pub fn enemy_height_tiles(kind: crate::enemy::EnemyKindId) -> f32 {
    match kind.0 {
        0 => 1.05, // Slime: low to the ground
        1 => 1.60, // Cave Crawler: wiry
        2 => 1.85, // Deep Stalker: tall
        _ => 2.05, // Gloom Brute: looming
    }
}

/// How tall a boss is drawn, in tiles.
///
/// Each boss gets its own figure rather than one shared scale: a colossus
/// that is merely as big as a serpent is not a colossus.
pub fn boss_height_tiles(kind: crate::boss::BossKindId) -> f32 {
    match kind.0 {
        0 => 2.70, // The Warden: hangs at head height
        1 => 3.00, // Rimewyrm: reared up tall
        2 => 3.80, // Sand Colossus: the largest thing in the game
        _ => 3.20, // Hollow King: tall and gaunt
    }
}

/// How a boss looks. Indexed by `BossKindId`.
///
/// Every boss has its own silhouette. Four recoloured hulks read as one
/// creature in four jerseys, which is the opposite of a set-piece fight.
pub fn boss_style(kind: crate::boss::BossKindId) -> CharacterStyle {
    match kind.0 {
        // The Warden: slate and iron.
        0 => CharacterStyle {
            build: Build::Sentinel,
            skin: [142.0, 148.0, 158.0],
            cloth: [86.0, 94.0, 112.0],
            trouser: [56.0, 62.0, 78.0],
            hair: [44.0, 48.0, 62.0],
            eye: [120.0, 230.0, 236.0],
            seed: 0xB000,
        },
        // Rimewyrm: pale ice.
        1 => CharacterStyle {
            build: Build::Wyrm,
            skin: [206.0, 224.0, 238.0],
            cloth: [128.0, 180.0, 220.0],
            trouser: [80.0, 126.0, 170.0],
            hair: [168.0, 206.0, 232.0],
            eye: [60.0, 120.0, 190.0],
            seed: 0xB001,
        },
        // Sand Colossus: sunbaked stone.
        2 => CharacterStyle {
            build: Build::Colossus,
            skin: [208.0, 180.0, 128.0],
            cloth: [186.0, 150.0, 92.0],
            trouser: [132.0, 104.0, 62.0],
            hair: [150.0, 120.0, 74.0],
            eye: [240.0, 120.0, 50.0],
            seed: 0xB002,
        },
        // Hollow King: void and gold.
        _ => CharacterStyle {
            build: Build::Crowned,
            skin: [92.0, 80.0, 108.0],
            cloth: [56.0, 44.0, 74.0],
            trouser: [40.0, 32.0, 56.0],
            hair: [212.0, 176.0, 86.0],
            eye: [250.0, 206.0, 96.0],
            seed: 0xB003,
        },
    }
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
    let mut canvas = Canvas::new(CHAR_W, CHAR_H);
    let pose = pose(state, frame);

    match style.build {
        Build::Blob => draw_blob(&mut canvas, style, &pose, blinking),
        Build::Sentinel => draw_sentinel(&mut canvas, style, &pose, blinking),
        Build::Wyrm => draw_wyrm(&mut canvas, style, &pose, blinking),
        Build::Colossus => draw_colossus(&mut canvas, style, &pose, blinking),
        Build::Crowned => draw_crowned(&mut canvas, style, &pose, blinking),
        Build::Humanoid | Build::Hulk => draw_upright(&mut canvas, style, &pose, blinking),
    }

    canvas.into_texture()
}

/// A blob is one squat body that sits low, with a face on it.
///
/// It fills most of the canvas height so that scaling the sprite down for a
/// small creature does not leave it a speck.
fn draw_blob(canvas: &mut Canvas, style: &CharacterStyle, pose: &Pose, blinking: bool) {
    use layout::*;

    let seed = style.seed;

    {
        let w = 38;
        let h = 46;
        let x = CENTRE_X - w / 2;
        let y = CHAR_H as i32 - h + pose.body_dy.min(0);

        draw_part(canvas, x, y, w, h, 12.0, style.cloth, seed);

        // Eyes sit on the upper half of the blob.
        let eye_y = y + 14;
        for centre_x in [CENTRE_X - 8, CENTRE_X + 8] {
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

    }
}

/// The standard two-arm, two-leg figure: the player, most enemies, and the
/// hulks, which are the same skeleton carrying more mass.
fn draw_upright(canvas: &mut Canvas, style: &CharacterStyle, pose: &Pose, blinking: bool) {
    use layout::*;

    let seed = style.seed;

    // Hulks are broader than the standard humanoid. Bulk goes mostly into
    // the chest: widening the arms by the same amount turns them into slabs.
    let hulk = style.build == Build::Hulk;
    let torso_bulk = if hulk { 8 } else { 0 };
    let bulk = if hulk { 2 } else { 0 };
    let arm_spread = if hulk { 2 } else { 0 };

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
        canvas,
        ARM_FAR_X + pose.lean - arm_spread,
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
        canvas,
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
        canvas,
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
        canvas,
        TORSO_X + pose.lean - torso_bulk / 2,
        TORSO_Y + body_dy,
        TORSO_W + torso_bulk,
        TORSO_H,
        5.0,
        style.cloth,
        seed ^ 0x44,
    );

    draw_limb(
        canvas,
        ARM_NEAR_X + pose.lean + arm_spread,
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
        canvas,
        CENTRE_X - 4 + pose.lean,
        HEAD_Y + HEAD_H - 3 + head_dy,
        8,
        6,
        2.0,
        far_skin,
        seed ^ 0x88,
    );

    draw_part(
        canvas,
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
        canvas,
        HEAD_X + pose.lean + 1,
        HEAD_Y + head_dy,
        HEAD_W - 2,
        9,
        4.0,
        style.hair,
        seed ^ 0x77,
    );

    draw_face(canvas, style, pose, head_dy, blinking);
}

/// Sclera, iris, pupil and a catchlight, for a creature where one eye is the
/// whole face. The catchlight goes upper-left like every other highlight.
fn draw_great_eye(
    canvas: &mut Canvas,
    cx: i32,
    cy: i32,
    radius: f32,
    style: &CharacterStyle,
    blinking: bool,
) {
    let lid = ramp_from(style.cloth).shadow;

    if blinking {
        let half = radius.round() as i32;
        for dy in -1..=1 {
            for dx in -half..=half {
                canvas.put(cx + dx, cy + dy, lid);
            }
        }
        return;
    }

    let seed = style.seed;

    draw_disc(canvas, cx, cy, radius, [236.0, 234.0, 226.0], seed ^ 0xE1);
    draw_disc(canvas, cx, cy, (radius * 0.62).max(2.0), style.eye, seed ^ 0xE2);
    draw_disc(
        canvas,
        cx,
        cy,
        (radius * 0.26).max(1.0),
        [26.0, 22.0, 32.0],
        seed ^ 0xE3,
    );

    let offset = (radius * 0.40).round() as i32;
    for dy in 0..2 {
        for dx in 0..2 {
            canvas.put(cx - offset + dx, cy - offset + dy, [246.0, 244.0, 236.0]);
        }
    }
}

/// A hooded orb that hangs in the air, built around one great eye.
///
/// It is deliberately legless: a thing with no feet reads as hovering even
/// before it moves, which is most of what sells a guardian over a brute.
fn draw_sentinel(canvas: &mut Canvas, style: &CharacterStyle, pose: &Pose, blinking: bool) {
    use layout::*;

    let seed = style.seed;
    let cx = CENTRE_X;
    let cy = 34 + pose.body_dy;

    // A veil hanging under the core, so the body tapers away instead of
    // ending in a cut-off circle.
    draw_taper(
        canvas,
        cx,
        cy + 10,
        24,
        22,
        8,
        ramp_from(style.trouser).shadow,
        seed ^ 0x01,
    );

    // Armoured shell, then a hood over its upper half. The hood is kept
    // narrower than the shell so a rim of plate still shows at the sides;
    // covering the whole disc turns the sentinel into a dark lozenge.
    draw_disc(canvas, cx, cy, 15.0, style.cloth, seed ^ 0x03);
    draw_taper(canvas, cx, cy - 16, 11, 14, 26, style.hair, seed ^ 0x04);

    // Two shards mounted at either side, counter-swinging so the sentinel
    // is never quite still even while it hovers. Drawn over the shell:
    // behind it they are swallowed whole and read as stray dots.
    for (side, sway) in [(-1, pose.arm_far.0), (1, pose.arm_near.0)] {
        draw_disc(
            canvas,
            cx + side * 16,
            cy + sway,
            4.5,
            style.skin,
            seed ^ 0x02,
        );
    }

    // The core, and the eye that is this creature's whole face.
    draw_disc(canvas, cx, cy + 2, 10.0, style.skin, seed ^ 0x05);
    draw_great_eye(canvas, cx, cy + 2, 7.5, style, blinking);
}

/// A segmented serpent reared up out of the ground in an S-curve.
///
/// The curve is the silhouette: a column of discs down the centre would
/// read as a totem pole. Each segment's offset comes from a sine along the
/// body, and the pose shifts its phase so the whole length writhes.
fn draw_wyrm(canvas: &mut Canvas, style: &CharacterStyle, pose: &Pose, blinking: bool) {
    use layout::*;

    /// Enough segments to read as a continuous body at this size.
    const SEGMENTS: i32 = 8;

    /// How far the body swings off centre, in pixels.
    const AMPLITUDE: f32 = 9.0;

    /// Starting phase, so an idle wyrm is already curved rather than straight.
    const REST_PHASE: f32 = std::f32::consts::FRAC_PI_4;

    let seed = style.seed;
    let phase =
        REST_PHASE + pose.body_dy as f32 * 0.22 + pose.arm_near.0 as f32 * 0.12;

    let along = |index: i32| index as f32 / (SEGMENTS - 1) as f32;
    let centre = |t: f32| {
        CENTRE_X + (AMPLITUDE * (t * 1.6 * std::f32::consts::PI + phase).sin()).round() as i32
    };
    let radius = |t: f32| 11.0 - t * 6.0;

    // Tail first, so each segment overlaps the one behind it and the body
    // reads as continuous rather than as beads on a string.
    for index in (0..SEGMENTS).rev() {
        let t = along(index);
        let (x, y, r) = (centre(t), 14 + (t * 70.0).round() as i32, radius(t));

        // Alternating tones give the body banding, like a snake.
        let base = if index % 2 == 0 {
            style.cloth
        } else {
            style.trouser
        };
        draw_disc(canvas, x, y, r, base, seed ^ (0x51 + index as u64));

        // A dorsal fin on the outside of the curve, where a real spine
        // would show through.
        let outward = if x >= CENTRE_X { 1 } else { -1 };
        draw_spike(
            canvas,
            x + outward * (r as i32 - 2),
            y - 1,
            2,
            (r * 0.8) as i32,
            style.hair,
            seed ^ (0x61 + index as u64),
        );
    }

    // The head: the first segment again, slightly larger, with a jaw and a
    // pair of eyes set forward.
    let head_x = centre(0.0);
    let head_y = 14;

    draw_disc(canvas, head_x, head_y, 12.0, style.skin, seed ^ 0x71);

    // Jaw, slung below and ahead of the skull.
    draw_taper(
        canvas,
        head_x + 3,
        head_y + 6,
        8,
        16,
        10,
        ramp_from(style.skin).shadow,
        seed ^ 0x72,
    );

    for side in [-1, 1] {
        draw_great_eye(
            canvas,
            head_x + side * 5,
            head_y - 2,
            3.5,
            style,
            blinking,
        );
    }

    // Horns, which is what tells a wyrm from an eel at a glance.
    for side in [-1, 1] {
        draw_spike(
            canvas,
            head_x + side * 8,
            head_y - 6,
            2,
            9,
            style.hair,
            seed ^ 0x73,
        );
    }
}

/// A slab of animated stone: all of its mass in the shoulders.
///
/// The head is sunk between them rather than sitting on a neck, which is
/// what makes it read as masonry that stood up rather than a big person.
fn draw_colossus(canvas: &mut Canvas, style: &CharacterStyle, pose: &Pose, blinking: bool) {
    use layout::*;

    let seed = style.seed;
    let bob = pose.body_dy;
    let dark = ramp_from(style.trouser).shadow;

    // Short, planted legs. A colossus does not stride.
    for (x, sway, base) in [
        (10, pose.leg_far.0, dark),
        (22, pose.leg_near.0, style.trouser),
    ] {
        draw_limb(canvas, x, 58 + bob, 9, 30, sway, base, base, 5, seed ^ 0x81);
    }

    // A waist narrower than the shoulders, with daylight either side of it.
    // Fill the midriff edge to edge and the whole figure becomes a wall:
    // the slab only reads as a slab if something below it is slimmer.
    draw_part(canvas, 13, 30 + bob, 14, 32, 4.0, style.cloth, seed ^ 0x82);

    // The shoulder slab: the signature of the silhouette.
    draw_part(canvas, 1, 14 + bob, 38, 18, 6.0, style.cloth, seed ^ 0x83);

    // A small head, sunk down between the shoulders.
    draw_part(
        canvas,
        CENTRE_X - 7,
        7 + bob,
        14,
        16,
        5.0,
        style.skin,
        seed ^ 0x84,
    );

    // Arms hung outside the waist, with a gap between each and the body so
    // they read as hanging. They stop above the hips: fists level with the
    // legs bridge the gaps and the whole figure goes back to being a wall.
    draw_limb(
        canvas,
        1,
        24 + bob + pose.arm_far.1,
        9,
        32,
        pose.arm_far.0,
        dark,
        dark,
        8,
        seed ^ 0x85,
    );
    draw_limb(
        canvas,
        30,
        24 + bob + pose.arm_near.1,
        9,
        32,
        pose.arm_near.0,
        style.cloth,
        style.skin,
        8,
        seed ^ 0x86,
    );

    // Eyes are slits of molten light in the stone, not a face.
    let eye_y = 14 + bob;
    for side in [-1, 1] {
        let cx = CENTRE_X + side * 4;

        if blinking {
            for dx in -2..=2 {
                canvas.put(cx + dx, eye_y, ramp_from(style.skin).shadow);
            }
            continue;
        }

        for dy in 0..2 {
            for dx in -2..=2 {
                canvas.put(cx + dx, eye_y + dy, style.eye);
            }
        }
    }

    // A crack running down the chest, so the slab is not one clean shape.
    let crack = ramp_from(style.cloth).shadow;
    for step in 0..18 {
        let drift = ((step / 5) % 3) - 1;
        canvas.put(CENTRE_X + drift, 34 + bob + step, crack);
    }
}

/// A gaunt crowned figure whose cape flares to the floor.
///
/// Where the colossus is mass, this is outline: a narrow body inside a wide
/// cape, under a crown that breaks the top of the silhouette.
fn draw_crowned(canvas: &mut Canvas, style: &CharacterStyle, pose: &Pose, blinking: bool) {
    use layout::*;

    let seed = style.seed;
    let bob = pose.body_dy;
    let head_dy = bob + pose.head_dy;
    let lean = pose.lean;

    // The cape goes down first, behind everything else.
    draw_taper(
        canvas,
        CENTRE_X + lean,
        26 + bob,
        58,
        20,
        34,
        ramp_from(style.cloth).shadow,
        seed ^ 0x91,
    );

    let far_trouser = ramp_from(style.trouser).shadow;
    let leg_height = |top_y: i32| (CHAR_H as i32 - top_y).clamp(6, 30);

    // Gaunt limbs: thinner than a humanoid's, which is what "hollow" means
    // in a silhouette.
    for (x, swing, base) in [
        (12, pose.leg_far, far_trouser),
        (23, pose.leg_near, style.trouser),
    ] {
        let y = 58 + swing.1 + bob;
        draw_limb(
            canvas,
            x,
            y,
            5,
            leg_height(y),
            swing.0,
            base,
            base,
            4,
            seed ^ 0x92,
        );
    }

    draw_limb(
        canvas,
        7 + lean,
        34 + pose.arm_far.1 + bob,
        5,
        26,
        pose.arm_far.0,
        ramp_from(style.skin).shadow,
        ramp_from(style.skin).shadow,
        4,
        seed ^ 0x93,
    );

    draw_part(
        canvas,
        CENTRE_X - 7 + lean,
        32 + bob,
        14,
        28,
        4.0,
        style.cloth,
        seed ^ 0x94,
    );

    // Ribs showing through: three pale bars across the narrow chest. They
    // have to be lighter than the cloth, not darker, or they vanish into
    // a body this dark.
    let rib = ramp_from(style.skin).highlight;
    for row in 0..3 {
        let y = 38 + bob + row * 5;
        for dx in -5..=5 {
            canvas.put(CENTRE_X + lean + dx, y, rib);
        }
    }

    draw_limb(
        canvas,
        28 + lean,
        34 + pose.arm_near.1 + bob,
        5,
        26,
        pose.arm_near.0,
        style.skin,
        style.skin,
        4,
        seed ^ 0x95,
    );

    // A narrow skull, taller than it is wide.
    draw_part(
        canvas,
        CENTRE_X - 9 + lean,
        13 + head_dy,
        18,
        20,
        6.0,
        style.skin,
        seed ^ 0x96,
    );

    // The crown: a band with three heavy points. Five thin spikes were
    // tried first and read as spiky blonde hair; a band is what says metal.
    for &(offset, height) in &[(-6, 9), (0, 14), (6, 9)] {
        draw_spike(
            canvas,
            CENTRE_X + offset + lean,
            16 + head_dy,
            3,
            height,
            style.hair,
            seed ^ 0x97,
        );
    }

    draw_part(
        canvas,
        CENTRE_X - 9 + lean,
        14 + head_dy,
        18,
        4,
        1.0,
        style.hair,
        seed ^ 0x98,
    );

    // Sunken sockets with a point of light in each: no sclera, because a
    // skull has none.
    let socket = [30.0, 26.0, 36.0];
    for side in [-1, 1] {
        let cx = CENTRE_X + side * 4 + lean;
        let cy = 21 + head_dy;

        for dy in -2..=2i32 {
            for dx in -2..=2i32 {
                if dx.abs() + dy.abs() > 3 {
                    continue;
                }
                canvas.put(cx + dx, cy + dy, socket);
            }
        }

        if !blinking {
            for dy in 0..2 {
                for dx in 0..2 {
                    canvas.put(cx + dx - 1, cy + dy - 1, style.eye);
                }
            }
        }
    }
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
    fn every_enemy_kind_has_its_own_look() {
        use crate::enemy::ENEMIES;

        let mut seen = Vec::new();
        for index in 0..ENEMIES.len() {
            let style = enemy_style(crate::enemy::EnemyKindId(index as u16));

            assert!(
                !seen.contains(&style.seed),
                "enemy {index} reuses another's seed"
            );
            seen.push(style.seed);

            let texture = character_frame(&style, AnimState::Idle, 0, false);
            assert!(opaque_count(&texture) > 150, "enemy {index} drew almost nothing");
        }
    }

    #[test]
    fn every_boss_kind_has_its_own_look() {
        use crate::boss::BOSSES;

        for index in 0..BOSSES.len() {
            let style = boss_style(crate::boss::BossKindId(index as u16));
            let texture = character_frame(&style, AnimState::Idle, 0, false);

            assert!(opaque_count(&texture) > 150, "boss {index} drew almost nothing");
        }
    }

    #[test]
    fn the_slime_is_a_blob_and_the_brute_is_a_hulk() {
        assert_eq!(enemy_style(crate::enemy::SLIME).build, Build::Blob);
        assert_eq!(enemy_style(crate::enemy::GLOOM_BRUTE).build, Build::Hulk);
    }

    #[test]
    fn enemies_do_not_all_look_the_same() {
        let crawler = character_frame(
            &enemy_style(crate::enemy::CAVE_CRAWLER),
            AnimState::Idle,
            0,
            false,
        );
        let stalker = character_frame(
            &enemy_style(crate::enemy::DEEP_STALKER),
            AnimState::Idle,
            0,
            false,
        );

        assert!(pixels_differ(&crawler, &stalker) > 200);
    }

    /// Which pixels are drawn at all, ignoring colour. Silhouette is what
    /// tells a creature apart at a glance on a phone screen.
    fn silhouette(texture: &Texture) -> Vec<bool> {
        texture
            .pixels
            .chunks_exact(4)
            .map(|pixel| pixel[3] > 0)
            .collect()
    }

    /// Fraction of the canvas where two silhouettes disagree.
    fn silhouette_difference(a: &Texture, b: &Texture) -> f32 {
        let (a, b) = (silhouette(a), silhouette(b));
        let differing = a.iter().zip(&b).filter(|(x, y)| x != y).count();

        differing as f32 / a.len() as f32
    }

    /// Topmost row holding anything, and the width of the widest row.
    fn top_row(texture: &Texture) -> u32 {
        (0..CHAR_H)
            .find(|&y| (0..CHAR_W).any(|x| texture.pixel(x, y)[3] > 0))
            .unwrap_or(CHAR_H)
    }

    /// Pixels actually drawn on one row. Counted rather than measured
    /// left-to-right, because a row holding two outstretched arms and
    /// nothing between them spans the canvas without being broad.
    fn row_mass(texture: &Texture, y: u32) -> u32 {
        (0..CHAR_W)
            .filter(|&x| texture.pixel(x, y)[3] > 0)
            .count() as u32
    }

    fn heaviest_row(texture: &Texture) -> (u32, u32) {
        (0..CHAR_H)
            .map(|y| (y, row_mass(texture, y)))
            .max_by_key(|&(_, mass)| mass)
            .unwrap()
    }

    /// Horizontal centre of mass across a band of rows.
    fn centre_x(texture: &Texture, rows: std::ops::Range<u32>) -> f32 {
        let mut weighted = 0.0;
        let mut total = 0.0;

        for y in rows {
            for x in 0..CHAR_W {
                if texture.pixel(x, y)[3] > 0 {
                    weighted += x as f32;
                    total += 1.0;
                }
            }
        }

        if total == 0.0 {
            return CHAR_W as f32 / 2.0;
        }

        weighted / total
    }

    fn boss_frame(kind: crate::boss::BossKindId) -> Texture {
        character_frame(&boss_style(kind), AnimState::Idle, 0, false)
    }

    fn all_bosses() -> Vec<crate::boss::BossKindId> {
        (0..crate::boss::BOSSES.len())
            .map(|index| crate::boss::BossKindId(index as u16))
            .collect()
    }

    #[test]
    fn every_boss_reads_as_a_different_creature() {
        // Not merely a different colour: a different shape. A recoloured
        // hulk is the thing this is here to prevent.
        let kinds = all_bosses();

        for (i, &first) in kinds.iter().enumerate() {
            for &second in &kinds[i + 1..] {
                let difference = silhouette_difference(&boss_frame(first), &boss_frame(second));

                assert!(
                    difference > 0.12,
                    "{} and {} share {:.0}% of their silhouette",
                    crate::boss::kind(first).name,
                    crate::boss::kind(second).name,
                    (1.0 - difference) * 100.0
                );
            }
        }
    }

    #[test]
    fn no_boss_is_shaped_like_the_player() {
        let player = frame_of(AnimState::Idle, 0);

        for kind in all_bosses() {
            let difference = silhouette_difference(&player, &boss_frame(kind));

            assert!(
                difference > 0.15,
                "{} has the player's outline",
                crate::boss::kind(kind).name
            );
        }
    }

    #[test]
    fn the_warden_floats_instead_of_standing() {
        let texture = boss_frame(crate::boss::WARDEN);

        assert_eq!(boss_style(crate::boss::WARDEN).build, Build::Sentinel);

        let standing = (CHAR_H - 6..CHAR_H)
            .flat_map(|y| (0..CHAR_W).map(move |x| (x, y)))
            .filter(|&(x, y)| texture.pixel(x, y)[3] > 0)
            .count();

        assert_eq!(standing, 0, "a floating sentinel should have no feet");
    }

    #[test]
    fn the_rimewyrm_coils_rather_than_standing_straight() {
        let texture = boss_frame(crate::boss::RIMEWYRM);

        assert_eq!(boss_style(crate::boss::RIMEWYRM).build, Build::Wyrm);

        let head = centre_x(&texture, 0..CHAR_H / 3);
        let tail = centre_x(&texture, CHAR_H * 2 / 3..CHAR_H);

        assert!(
            (head - tail).abs() > 4.0,
            "head at {head:.1} and tail at {tail:.1}: that is a post, not a serpent"
        );
    }

    #[test]
    fn the_colossus_carries_its_bulk_in_its_shoulders() {
        let texture = boss_frame(crate::boss::SAND_COLOSSUS);

        assert_eq!(boss_style(crate::boss::SAND_COLOSSUS).build, Build::Colossus);

        let (row, mass) = heaviest_row(&texture);
        let (_, player_mass) = heaviest_row(&frame_of(AnimState::Idle, 0));

        assert!(
            mass > player_mass + 4,
            "heaviest row holds {mass}px against the player's {player_mass}px"
        );
        assert!(
            row < CHAR_H / 2,
            "the bulk should sit in the shoulders, not the feet (heaviest row {row})"
        );
    }

    #[test]
    fn the_hollow_king_wears_a_crown_that_breaks_the_outline() {
        let texture = boss_frame(crate::boss::HOLLOW_KING);

        assert_eq!(boss_style(crate::boss::HOLLOW_KING).build, Build::Crowned);

        let crowned = top_row(&texture);
        let bare = top_row(&frame_of(AnimState::Idle, 0));

        assert!(
            crowned < bare,
            "crown reaches row {crowned}, no higher than a bare head at {bare}"
        );
    }

    #[test]
    fn every_boss_animates_through_all_of_its_states() {
        for kind in all_bosses() {
            let style = boss_style(kind);
            let name = crate::boss::kind(kind).name;

            for state in ALL_STATES {
                for frame in 0..clip(state).frames {
                    let texture = character_frame(&style, state, frame, false);

                    assert!(
                        opaque_count(&texture) > 150,
                        "{name} drew almost nothing for {state:?} frame {frame}"
                    );
                }
            }
        }
    }

    #[test]
    fn every_boss_moves_between_frames_of_a_walk() {
        for kind in all_bosses() {
            let style = boss_style(kind);
            let first = character_frame(&style, AnimState::Walk, 0, false);
            let third = character_frame(&style, AnimState::Walk, 2, false);

            assert!(
                pixels_differ(&first, &third) > 40,
                "{} is a still image while walking",
                crate::boss::kind(kind).name
            );
        }
    }

    #[test]
    fn every_boss_shows_the_eyes_that_identify_it() {
        for kind in all_bosses() {
            let style = boss_style(kind);
            let texture = character_frame(&style, AnimState::Idle, 0, false);

            let found = texture.pixels.chunks_exact(4).any(|pixel| {
                pixel[3] > 0
                    && (pixel[0] as f32 - style.eye[0]).abs() < 50.0
                    && (pixel[1] as f32 - style.eye[1]).abs() < 50.0
                    && (pixel[2] as f32 - style.eye[2]).abs() < 50.0
            });

            assert!(
                found,
                "{} has no visible eye",
                crate::boss::kind(kind).name
            );
        }
    }

    #[test]
    fn bosses_loom_over_the_player_and_the_colossus_most_of_all() {
        use crate::view::PLAYER_HEIGHT_TILES;

        let heights: Vec<(&str, f32)> = all_bosses()
            .iter()
            .map(|&kind| (crate::boss::kind(kind).name, boss_height_tiles(kind)))
            .collect();

        for &(name, height) in &heights {
            assert!(
                height > PLAYER_HEIGHT_TILES * 1.2,
                "{name} is only {height} tiles tall; a boss should loom"
            );
        }

        let tallest = heights
            .iter()
            .max_by(|a, b| a.1.total_cmp(&b.1))
            .map(|&(name, _)| name);

        assert_eq!(
            tallest,
            Some("Sand Colossus"),
            "the colossus should be the largest thing in the game"
        );
    }

    #[test]
    fn no_boss_build_is_left_unused() {
        // Guards against adding a silhouette nothing ever draws.
        let used: Vec<Build> = all_bosses()
            .iter()
            .map(|&kind| boss_style(kind).build)
            .collect();

        for build in [
            Build::Sentinel,
            Build::Wyrm,
            Build::Colossus,
            Build::Crowned,
        ] {
            assert!(used.contains(&build), "{build:?} is drawn by no boss");
        }
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
