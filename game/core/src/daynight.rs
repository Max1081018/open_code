//! The day/night cycle, which drives sky colour and nocturnal spawns.

/// Seconds in one full day-night cycle.
pub const DAY_LENGTH: f32 = 600.0;

/// Fraction of the cycle at which dusk begins and dawn ends.
const DUSK: f32 = 0.5;
const DAWN: f32 = 0.875;

/// How dark the world gets at the dead of night, as a brightness floor.
const NIGHT_BRIGHTNESS: f32 = 0.22;

/// Position within the day-night cycle.
#[derive(Clone, Copy, Debug)]
pub struct TimeOfDay {
    seconds: f32,
}

impl TimeOfDay {
    /// Start at dawn, so a new game begins in daylight.
    pub fn dawn() -> TimeOfDay {
        TimeOfDay { seconds: 0.0 }
    }

    /// Advance the clock, wrapping at the end of the cycle.
    pub fn advance(&mut self, dt: f32) {
        self.seconds = (self.seconds + dt).rem_euclid(DAY_LENGTH);
    }

    /// Position in the cycle, from 0.0 at dawn to just under 1.0.
    pub fn fraction(&self) -> f32 {
        self.seconds / DAY_LENGTH
    }

    /// Whether nocturnal enemies should be spawning.
    pub fn is_night(&self) -> bool {
        let fraction = self.fraction();
        (DUSK..DAWN).contains(&fraction)
    }

    /// Daylight strength, 1.0 at noon falling to `NIGHT_BRIGHTNESS` at
    /// midnight, easing smoothly through dusk and dawn.
    ///
    /// A raised cosine rather than a ramp, so there is no visible kink at
    /// sunrise or sunset.
    pub fn sky_brightness(&self) -> f32 {
        // Noon sits a quarter of the way through the cycle.
        let phase = (self.fraction() - 0.25) * std::f32::consts::TAU;
        let daylight = (phase.cos() + 1.0) / 2.0;

        NIGHT_BRIGHTNESS + (1.0 - NIGHT_BRIGHTNESS) * daylight
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Advance a fresh clock to the given fraction of the cycle.
    fn at(fraction: f32) -> TimeOfDay {
        let mut time = TimeOfDay::dawn();
        time.advance(DAY_LENGTH * fraction);
        time
    }

    #[test]
    fn a_new_game_begins_in_daylight() {
        let time = TimeOfDay::dawn();

        assert!(!time.is_night(), "should start in the day");
        assert_eq!(time.fraction(), 0.0);
    }

    #[test]
    fn the_clock_advances_with_elapsed_time() {
        let mut time = TimeOfDay::dawn();

        time.advance(DAY_LENGTH / 4.0);

        assert!((time.fraction() - 0.25).abs() < 1e-5, "got {}", time.fraction());
    }

    #[test]
    fn the_clock_wraps_around_at_the_end_of_the_cycle() {
        let mut time = TimeOfDay::dawn();

        time.advance(DAY_LENGTH * 2.5);

        let fraction = time.fraction();
        assert!(
            (0.0..1.0).contains(&fraction),
            "fraction should wrap into range, got {fraction}"
        );
        assert!((fraction - 0.5).abs() < 1e-4, "2.5 cycles lands at midday");
    }

    #[test]
    fn midday_is_daytime_and_the_dead_of_night_is_not() {
        assert!(!at(0.25).is_night(), "midday should be day");
        assert!(at(0.7).is_night(), "the small hours should be night");
    }

    #[test]
    fn brightness_stays_within_range_across_the_whole_cycle() {
        for step in 0..200 {
            let time = at(step as f32 / 200.0);
            let brightness = time.sky_brightness();

            assert!(
                (0.0..=1.0).contains(&brightness),
                "brightness {brightness} out of range at {}",
                time.fraction()
            );
        }
    }

    #[test]
    fn noon_is_brighter_than_midnight() {
        let noon = at(0.25).sky_brightness();
        let midnight = at(0.7).sky_brightness();

        assert!(
            noon > midnight + 0.3,
            "noon {noon} should clearly outshine midnight {midnight}"
        );
    }

    #[test]
    fn midnight_is_dim_but_never_pitch_black() {
        let midnight = at(0.7).sky_brightness();

        assert!(midnight > 0.0, "the player must still see something");
        assert!(midnight < 0.4, "night should feel like night, got {midnight}");
    }

    #[test]
    fn light_changes_smoothly_rather_than_snapping() {
        let mut previous = at(0.0).sky_brightness();

        for step in 1..=500 {
            let current = at(step as f32 / 500.0).sky_brightness();

            assert!(
                (current - previous).abs() < 0.05,
                "brightness jumped from {previous} to {current} at step {step}"
            );
            previous = current;
        }
    }
}
