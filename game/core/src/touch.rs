//! On-screen control layout for touch devices.
//!
//! Pure geometry, so the thumb zones can be tested without a phone. Screen
//! coordinates have their origin at the top left with `y` increasing
//! downward, matching what the windowing layer reports.

/// Fraction of the shorter screen edge used as the movement stick's radius.
const STICK_RADIUS_FRACTION: f32 = 0.20;

/// Fraction of the shorter screen edge used for the action buttons.
const BUTTON_RADIUS_FRACTION: f32 = 0.13;

/// Inset of control centres from the screen edges, as a fraction of the
/// shorter edge. Keeps thumbs clear of rounded corners and gesture bars.
const EDGE_INSET: f32 = 0.26;

/// Where a touch landed, and therefore what it means.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Zone {
    /// The movement stick.
    Stick,
    /// The jump button.
    Jump,
    /// The place-block button.
    Build,
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

    /// Which control, if any, a touch at `(x, y)` belongs to.
    pub fn zone_at(&self, x: f32, y: f32) -> Zone {
        let inside = |centre: (f32, f32), radius: f32| {
            (x - centre.0).powi(2) + (y - centre.1).powi(2) <= radius * radius
        };

        if inside(self.stick_centre(), self.stick_radius()) {
            Zone::Stick
        } else if inside(self.jump_centre(), self.button_radius()) {
            Zone::Jump
        } else if inside(self.build_centre(), self.button_radius()) {
            Zone::Build
        } else {
            Zone::World
        }
    }

    /// Horizontal steering from a touch on the stick, in `[-1, 1]`.
    ///
    /// Returns 0.0 for a touch at the exact centre, and saturates at the
    /// stick's edge so the player need not be precise.
    pub fn stick_axis(&self, x: f32, _y: f32) -> f32 {
        let (centre_x, _) = self.stick_centre();

        ((x - centre_x) / self.stick_radius()).clamp(-1.0, 1.0)
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
    }

    #[test]
    fn every_control_sits_fully_on_screen() {
        for (width, height) in [(2340.0, 1080.0), (1280.0, 720.0), (2000.0, 1200.0)] {
            let controls = Controls::new(width, height);

            for (name, (cx, cy), radius) in [
                ("stick", controls.stick_centre(), controls.stick_radius()),
                ("jump", controls.jump_centre(), controls.button_radius()),
                ("build", controls.build_centre(), controls.button_radius()),
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

    #[test]
    fn the_stick_is_neutral_at_its_centre() {
        let controls = phone();
        let (x, y) = controls.stick_centre();

        assert_eq!(controls.stick_axis(x, y), 0.0);
    }

    #[test]
    fn pushing_the_stick_left_steers_left() {
        let controls = phone();
        let (x, y) = controls.stick_centre();

        let axis = controls.stick_axis(x - controls.stick_radius() * 0.5, y);

        assert!(axis < 0.0, "expected leftward steering, got {axis}");
    }

    #[test]
    fn pushing_the_stick_right_steers_right() {
        let controls = phone();
        let (x, y) = controls.stick_centre();

        let axis = controls.stick_axis(x + controls.stick_radius() * 0.5, y);

        assert!(axis > 0.0, "expected rightward steering, got {axis}");
    }

    #[test]
    fn the_stick_saturates_rather_than_running_away() {
        let controls = phone();
        let (x, y) = controls.stick_centre();

        // Far outside the stick, as happens when a thumb slides.
        let axis = controls.stick_axis(x + controls.width, y);

        assert!(
            (axis - 1.0).abs() < 1e-5,
            "axis should clamp to 1.0, got {axis}"
        );
    }

    #[test]
    fn stick_output_always_stays_within_range() {
        let controls = phone();
        let (cx, cy) = controls.stick_centre();

        for step in -60..60 {
            let x = cx + step as f32 * 20.0;
            let axis = controls.stick_axis(x, cy);

            assert!(
                (-1.0..=1.0).contains(&axis),
                "axis {axis} out of range at x={x}"
            );
        }
    }
}
