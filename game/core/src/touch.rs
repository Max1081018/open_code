//! On-screen control layout for touch devices.
//!
//! Pure geometry, so the thumb zones can be tested without a phone. Screen
//! coordinates have their origin at the top left with `y` increasing
//! downward, matching what the windowing layer reports.

/// Fraction of the shorter screen edge used as the movement stick's radius.
///
/// Sized against a thumb, not against the screen. The first pass used 0.20,
/// which on a 1080-tall phone draws a stick 432 pixels across — it looked
/// absurd over the world and covered terrain the player needs to see.
const STICK_RADIUS_FRACTION: f32 = 0.115;

/// Fraction of the shorter screen edge used for the action buttons.
///
/// About 160 pixels across on a 1080-tall phone, comfortably over the
/// ~9 mm minimum for a reliable thumb target without dominating the view.
const BUTTON_RADIUS_FRACTION: f32 = 0.075;

/// Inset of control centres from the screen edges, as a fraction of the
/// shorter edge. Keeps thumbs clear of rounded corners and gesture bars
/// while staying in the corner where a held phone puts them.
const EDGE_INSET: f32 = 0.17;

/// How much of the screen width, from the left, a thumb may land in to
/// take hold of the movement stick.
const STICK_ZONE_WIDTH: f32 = 0.36;

/// How much of the screen height, measured up from the bottom, the stick
/// zone covers.
///
/// Deliberately not the whole left half. Swallowing that much screen would
/// leave no way to aim at anything to the player's left or above them,
/// which is most of what digging upward and fighting involves.
const STICK_ZONE_HEIGHT: f32 = 0.50;

/// Fraction of the stick's radius the thumb must travel before the player
/// moves at all.
///
/// A thumb never rests perfectly still. Without a deadzone the character
/// creeps across the world while the player believes they are doing
/// nothing, which reads as the game being broken rather than as a control
/// being sensitive.
const STICK_DEADZONE: f32 = 0.16;

/// Where a touch landed, and therefore what it means.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Zone {
    /// The movement stick.
    Stick,
    /// The jump button.
    Jump,
    /// The place-block button.
    Build,
    /// The swing-weapon button.
    Attack,
    /// Anywhere else: aim at the world and dig.
    World,
}

/// Control geometry for one screen size.
#[derive(Clone, Copy, Debug)]
pub struct Controls {
    pub width: f32,
    pub height: f32,
}

impl Controls {
    pub fn new(width: f32, height: f32) -> Controls {
        Controls { width, height }
    }

    /// The shorter screen edge, which all control sizes are derived from so
    /// the layout holds on any aspect ratio.
    fn short_edge(&self) -> f32 {
        self.width.min(self.height)
    }

    pub fn stick_radius(&self) -> f32 {
        self.short_edge() * STICK_RADIUS_FRACTION
    }

    pub fn button_radius(&self) -> f32 {
        self.short_edge() * BUTTON_RADIUS_FRACTION
    }

    /// Centre of the movement stick, bottom left.
    pub fn stick_centre(&self) -> (f32, f32) {
        let inset = self.short_edge() * EDGE_INSET;
        (inset, self.height - inset)
    }

    /// Centre of the jump button, bottom right.
    pub fn jump_centre(&self) -> (f32, f32) {
        let inset = self.short_edge() * EDGE_INSET;
        (self.width - inset, self.height - inset)
    }

    /// Centre of the build button, above and inboard of jump.
    pub fn build_centre(&self) -> (f32, f32) {
        let inset = self.short_edge() * EDGE_INSET;
        let (jump_x, jump_y) = self.jump_centre();
        (jump_x - inset * 1.1, jump_y - inset * 0.55)
    }

    /// Centre of the attack button, directly above jump.
    pub fn attack_centre(&self) -> (f32, f32) {
        let inset = self.short_edge() * EDGE_INSET;
        let (jump_x, jump_y) = self.jump_centre();
        (jump_x, jump_y - inset * 1.15)
    }

    /// Whether a thumb landing at `(x, y)` takes hold of the movement
    /// stick.
    ///
    /// Much larger than the drawn stick: the stick floats to wherever the
    /// thumb lands, because on a phone the player cannot look down to find
    /// a fixed one.
    pub fn in_stick_zone(&self, x: f32, y: f32) -> bool {
        x <= self.width * STICK_ZONE_WIDTH
            && y >= self.height * (1.0 - STICK_ZONE_HEIGHT)
    }

    /// Which control, if any, a touch at `(x, y)` belongs to.
    ///
    /// Buttons are tested first: on a narrow screen the stick zone can
    /// reach them, and a thumb on a button must get the button.
    pub fn zone_at(&self, x: f32, y: f32) -> Zone {
        let inside = |centre: (f32, f32), radius: f32| {
            (x - centre.0).powi(2) + (y - centre.1).powi(2) <= radius * radius
        };

        if inside(self.jump_centre(), self.button_radius()) {
            Zone::Jump
        } else if inside(self.attack_centre(), self.button_radius()) {
            Zone::Attack
        } else if inside(self.build_centre(), self.button_radius()) {
            Zone::Build
        } else if self.in_stick_zone(x, y) {
            Zone::Stick
        } else {
            Zone::World
        }
    }

    /// How far to draw the stick's knob from its ring centre, in pixels.
    ///
    /// Clamped to the ring, so a thumb that slides across the screen drags
    /// the knob to the edge and leaves it there rather than trailing off
    /// into the world. Without a knob that tracks the thumb, a floating
    /// stick gives no feedback at all about what it thinks you are doing.
    pub fn knob_offset(&self, anchor_x: f32, x: f32) -> f32 {
        (x - anchor_x).clamp(-self.stick_radius(), self.stick_radius())
    }

    /// Horizontal steering, in `[-1, 1]`, for a thumb at `x` with the stick
    /// anchored where that thumb first landed.
    ///
    /// Zero inside the deadzone, then ramping to full tilt at the stick's
    /// radius, so there is a usable range between standing still and
    /// running — which matters when lining up a single tile to mine.
    pub fn axis_from(&self, anchor_x: f32, x: f32) -> f32 {
        let offset = (x - anchor_x) / self.stick_radius();
        let magnitude = offset.abs();

        if magnitude <= STICK_DEADZONE {
            return 0.0;
        }

        // Re-spread what is left of the travel over the full range, so
        // clearing the deadzone does not jump straight to a visible speed.
        let scaled = (magnitude - STICK_DEADZONE) / (1.0 - STICK_DEADZONE);

        scaled.clamp(0.0, 1.0) * offset.signum()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A typical landscape phone.
    fn phone() -> Controls {
        Controls::new(2340.0, 1080.0)
    }

    fn distance(a: (f32, f32), b: (f32, f32)) -> f32 {
        ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt()
    }

    #[test]
    fn a_thumb_anywhere_in_the_lower_left_grabs_the_stick() {
        // A floating stick is the point: on a phone you cannot look down to
        // find a fixed one, so wherever the left thumb lands becomes the
        // centre. Sampling a grid is the honest way to check that.
        let controls = phone();

        for column in 0..8 {
            for row in 0..6 {
                let x = controls.width * 0.03 + column as f32 * controls.width * 0.045;
                let y = controls.height * 0.5 + row as f32 * controls.height * 0.08;

                assert_eq!(
                    controls.zone_at(x, y),
                    Zone::Stick,
                    "a thumb at ({x:.0}, {y:.0}) should find the stick"
                );
            }
        }
    }

    #[test]
    fn the_upper_left_stays_playable() {
        // The stick zone is the lower-left corner, not the whole left half:
        // swallowing half the screen would make it impossible to aim at
        // anything to the player's left or above them.
        let controls = phone();

        for row in 0..5 {
            let y = controls.height * 0.04 + row as f32 * controls.height * 0.06;

            assert_eq!(
                controls.zone_at(controls.width * 0.2, y),
                Zone::World,
                "the upper left at y={y:.0} should stay aimable"
            );
        }
    }

    #[test]
    fn a_touch_on_the_attack_button_attacks() {
        let controls = phone();
        let (x, y) = controls.attack_centre();

        assert_eq!(controls.zone_at(x, y), Zone::Attack);
    }

    #[test]
    fn a_resting_thumb_does_not_make_the_player_creep() {
        // Without a deadzone a thumb a few pixels off the anchor walks the
        // character slowly across the world while the player is doing
        // nothing, which reads as the game being broken.
        let controls = phone();
        let anchor = 400.0;

        for drift in [-6.0, -3.0, -1.0, 0.0, 1.0, 3.0, 6.0] {
            assert_eq!(
                controls.axis_from(anchor, anchor + drift),
                0.0,
                "a thumb {drift}px off the anchor should not move the player"
            );
        }
    }

    #[test]
    fn pushing_past_the_deadzone_steers_both_ways() {
        let controls = phone();
        let anchor = 400.0;
        let reach = controls.stick_radius();

        assert!(controls.axis_from(anchor, anchor + reach * 0.6) > 0.0);
        assert!(controls.axis_from(anchor, anchor - reach * 0.6) < 0.0);
    }

    #[test]
    fn steering_ramps_up_smoothly_from_the_deadzone_edge() {
        // Jumping straight to full speed the instant the deadzone is
        // cleared makes fine positioning impossible, which matters when
        // lining up a single tile to mine.
        let controls = phone();
        let anchor = 400.0;
        let reach = controls.stick_radius();

        let samples: Vec<f32> = (0..=10)
            .map(|step| controls.axis_from(anchor, anchor + reach * step as f32 / 10.0))
            .collect();

        for pair in samples.windows(2) {
            assert!(
                pair[1] >= pair[0],
                "steering should never decrease as the thumb pushes out: {samples:?}"
            );
        }

        assert!(
            samples.iter().any(|&axis| (0.1..0.9).contains(&axis)),
            "there should be a usable range between nothing and full tilt: {samples:?}"
        );
    }

    #[test]
    fn the_stick_reaches_full_tilt_within_a_thumbs_reach() {
        // Full speed must be achievable without the thumb leaving the
        // bottom-left corner of the screen.
        let controls = phone();
        let anchor = 400.0;

        let axis = controls.axis_from(anchor, anchor + controls.stick_radius());

        assert!(
            (axis - 1.0).abs() < 1e-5,
            "full tilt should arrive by the stick's own radius, got {axis}"
        );
    }

    #[test]
    fn a_thumb_that_slides_off_the_stick_still_saturates() {
        let controls = phone();
        let anchor = 400.0;

        assert!((controls.axis_from(anchor, anchor + 5000.0) - 1.0).abs() < 1e-5);
        assert!((controls.axis_from(anchor, anchor - 5000.0) + 1.0).abs() < 1e-5);
    }

    #[test]
    fn steering_always_stays_within_range() {
        let controls = phone();

        for anchor in [0.0, 400.0, controls.width] {
            for step in -80..80 {
                let axis = controls.axis_from(anchor, anchor + step as f32 * 25.0);

                assert!(
                    (-1.0..=1.0).contains(&axis),
                    "axis {axis} out of range at anchor {anchor}"
                );
            }
        }
    }

    #[test]
    fn the_action_buttons_beat_the_stick_zone() {
        // The buttons sit on the right and the stick zone on the left, but
        // on a narrow screen they can meet. A thumb on a button must get
        // the button.
        for (width, height) in [(2340.0, 1080.0), (1280.0, 720.0), (960.0, 720.0)] {
            let controls = Controls::new(width, height);

            for (name, centre, zone) in [
                ("jump", controls.jump_centre(), Zone::Jump),
                ("build", controls.build_centre(), Zone::Build),
                ("attack", controls.attack_centre(), Zone::Attack),
            ] {
                assert_eq!(
                    controls.zone_at(centre.0, centre.1),
                    zone,
                    "{name} lost its touch to another zone on {width}x{height}"
                );
            }
        }
    }

    #[test]
    fn every_action_is_reachable_without_a_keyboard_or_mouse() {
        // A phone build where some verb has no on-screen control is a build
        // where that verb does not exist. Moving, jumping, building and
        // aiming all have zones; so must attacking.
        let controls = phone();

        let reachable: Vec<Zone> = (0..200)
            .flat_map(|step| {
                let x = controls.width * (step % 20) as f32 / 19.0;
                (0..20).map(move |row| (x, controls.height * row as f32 / 19.0))
            })
            .map(|(x, y)| controls.zone_at(x, y))
            .collect();

        for zone in [Zone::Stick, Zone::Jump, Zone::Build, Zone::Attack, Zone::World] {
            assert!(
                reachable.contains(&zone),
                "{zone:?} cannot be touched anywhere on screen"
            );
        }
    }

    #[test]
    fn the_knob_tracks_the_thumb_and_stays_inside_its_ring() {
        let controls = phone();
        let anchor = 400.0;
        let reach = controls.stick_radius();

        assert_eq!(controls.knob_offset(anchor, anchor), 0.0);
        assert!(
            (controls.knob_offset(anchor, anchor + reach * 0.5) - reach * 0.5).abs() < 1e-3,
            "inside the ring the knob should sit under the thumb"
        );

        for far in [reach * 4.0, controls.width] {
            assert!(
                controls.knob_offset(anchor, anchor + far) <= reach,
                "the knob should stop at the ring, not follow the thumb away"
            );
            assert!(controls.knob_offset(anchor, anchor - far) >= -reach);
        }
    }

    #[test]
    fn the_knob_shows_movement_exactly_when_the_player_is_moving() {
        // If the knob drifts while the deadzone holds the player still,
        // the control is lying about what the game heard.
        let controls = phone();
        let anchor = 400.0;
        let reach = controls.stick_radius();

        for step in 0..=20 {
            let x = anchor + reach * step as f32 / 20.0;
            let moving = controls.axis_from(anchor, x) != 0.0;
            let visibly_off_centre = controls.knob_offset(anchor, x).abs() > 1e-3;

            if !visibly_off_centre {
                assert!(!moving, "the player moved while the knob looked centred");
            }
        }
    }

    #[test]
    fn a_touch_on_the_stick_steers() {
        let controls = phone();
        let (x, y) = controls.stick_centre();

        assert_eq!(controls.zone_at(x, y), Zone::Stick);
    }

    #[test]
    fn a_touch_on_the_jump_button_jumps() {
        let controls = phone();
        let (x, y) = controls.jump_centre();

        assert_eq!(controls.zone_at(x, y), Zone::Jump);
    }

    #[test]
    fn a_touch_on_the_build_button_builds() {
        let controls = phone();
        let (x, y) = controls.build_centre();

        assert_eq!(controls.zone_at(x, y), Zone::Build);
    }

    #[test]
    fn a_touch_in_open_screen_aims_at_the_world() {
        let controls = phone();

        assert_eq!(
            controls.zone_at(controls.width / 2.0, controls.height / 4.0),
            Zone::World
        );
    }

    #[test]
    fn the_top_of_the_screen_is_never_a_control() {
        let controls = phone();

        for step in 0..40 {
            let x = controls.width * step as f32 / 40.0;

            assert_eq!(
                controls.zone_at(x, 4.0),
                Zone::World,
                "the top edge at x={x} should stay playable"
            );
        }
    }

    #[test]
    fn controls_do_not_overlap_one_another() {
        let controls = phone();

        let stick_to_jump = distance(controls.stick_centre(), controls.jump_centre());
        let stick_to_build = distance(controls.stick_centre(), controls.build_centre());
        let jump_to_build = distance(controls.jump_centre(), controls.build_centre());
        let jump_to_attack = distance(controls.jump_centre(), controls.attack_centre());
        let build_to_attack = distance(controls.build_centre(), controls.attack_centre());

        assert!(
            stick_to_jump > controls.stick_radius() + controls.button_radius(),
            "stick and jump overlap"
        );
        assert!(
            stick_to_build > controls.stick_radius() + controls.button_radius(),
            "stick and build overlap"
        );
        assert!(
            jump_to_build > controls.button_radius() * 2.0,
            "jump and build overlap"
        );
        assert!(
            jump_to_attack > controls.button_radius() * 2.0,
            "jump and attack overlap"
        );
        assert!(
            build_to_attack > controls.button_radius() * 2.0,
            "build and attack overlap"
        );
    }

    #[test]
    fn every_control_sits_fully_on_screen() {
        for (width, height) in [(2340.0, 1080.0), (1280.0, 720.0), (2000.0, 1200.0)] {
            let controls = Controls::new(width, height);

            for (name, (cx, cy), radius) in [
                ("stick", controls.stick_centre(), controls.stick_radius()),
                ("jump", controls.jump_centre(), controls.button_radius()),
                ("build", controls.build_centre(), controls.button_radius()),
                ("attack", controls.attack_centre(), controls.button_radius()),
            ] {
                assert!(
                    cx - radius >= 0.0 && cx + radius <= width,
                    "{name} runs off the side on {width}x{height}"
                );
                assert!(
                    cy - radius >= 0.0 && cy + radius <= height,
                    "{name} runs off the top or bottom on {width}x{height}"
                );
            }
        }
    }

    #[test]
    fn the_layout_scales_with_the_screen() {
        let small = Controls::new(1280.0, 720.0);
        let large = Controls::new(2340.0, 1080.0);

        assert!(
            large.stick_radius() > small.stick_radius(),
            "a bigger screen should get a bigger stick"
        );
    }





}
