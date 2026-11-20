//! The backdrop: sky gradient, sun and moon, stars, and distant hills.
//!
//! All of it derives from the time of day, so dawn and dusk come for free
//! rather than needing to be scripted.

use crate::art::Texture;
use crate::daynight::TimeOfDay;
use crate::noise::{fbm_1d, hash01};
use crate::paint::Canvas;

/// Parallax layers of distant hills, nearest last.
pub const HILL_LAYERS: usize = 3;

/// How fast each hill layer scrolls relative to the camera. Smaller is
/// further away.
pub const HILL_PARALLAX: [f32; HILL_LAYERS] = [0.06, 0.14, 0.28];

/// Width of a hill layer texture, in pixels. Tiles horizontally.
pub const HILL_WIDTH: u32 = 1024;

/// Height of a hill layer texture, in pixels.
pub const HILL_HEIGHT: u32 = 320;

/// Colours of the sky at a moment: overhead and at the horizon.
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct SkyColours {
    pub zenith: [f32; 3],
    pub horizon: [f32; 3],
}

/// Blend between two colours.
fn mix(a: [f32; 3], b: [f32; 3], t: f32) -> [f32; 3] {
    let t = t.clamp(0.0, 1.0);
    [
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
    ]
}

/// Key sky colours through the cycle, as (fraction, zenith, horizon).
///
/// The cycle runs dawn, day, dusk, night and back to dawn. Interpolating
/// between these is what gives sunrise and sunset for free.
const SKY_KEYS: [(f32, [f32; 3], [f32; 3]); 6] = [
    // Dawn: cool overhead, warm at the horizon.
    (0.00, [92.0, 116.0, 176.0], [228.0, 158.0, 122.0]),
    // Morning into full day.
    (0.12, [78.0, 134.0, 206.0], [166.0, 204.0, 232.0]),
    (0.30, [66.0, 126.0, 204.0], [158.0, 200.0, 232.0]),
    // Dusk: the sky reddens.
    (0.47, [96.0, 100.0, 158.0], [236.0, 136.0, 96.0]),
    // Night.
    (0.58, [16.0, 22.0, 44.0], [34.0, 40.0, 68.0]),
    (0.86, [20.0, 28.0, 56.0], [52.0, 56.0, 92.0]),
];

/// Sky colours for a moment in the cycle.
pub fn sky_colours(time: &TimeOfDay) -> SkyColours {
    let fraction = time.fraction();

    // Find the pair of keys this moment falls between, wrapping at the end.
    let mut previous = SKY_KEYS[SKY_KEYS.len() - 1];
    let mut next = SKY_KEYS[0];
    let mut span_start = previous.0 - 1.0;
    let mut span_end = next.0;

    for pair in SKY_KEYS.windows(2) {
        if fraction >= pair[0].0 && fraction < pair[1].0 {
            previous = pair[0];
            next = pair[1];
            span_start = pair[0].0;
            span_end = pair[1].0;
            break;
        }
    }

    // Past the final key, wrap around to the first.
    if fraction >= SKY_KEYS[SKY_KEYS.len() - 1].0 {
        previous = SKY_KEYS[SKY_KEYS.len() - 1];
        next = SKY_KEYS[0];
        span_start = previous.0;
        span_end = 1.0;
    }

    let span = (span_end - span_start).max(1e-6);
    let t = ((fraction - span_start) / span).clamp(0.0, 1.0);
    // Smoothstep, so there is no kink as one key hands over to the next.
    let t = t * t * (3.0 - 2.0 * t);

    SkyColours {
        zenith: mix(previous.1, next.1, t),
        horizon: mix(previous.2, next.2, t),
    }
}

/// Fraction of the cycle at which the sun rises and sets.
const SUNRISE: f32 = 0.02;
const SUNSET: f32 = 0.48;

/// Trace a body across the sky over `start..end`, or `None` outside it.
fn arc(fraction: f32, start: f32, end: f32) -> Option<(f32, f32)> {
    if fraction < start || fraction > end {
        return None;
    }

    let along = (fraction - start) / (end - start);

    // Across the screen left to right, and up over in an arc. y is measured
    // down from the top, so the peak is the smallest y.
    let x = along;
    let height = (along * std::f32::consts::PI).sin();
    let y = 0.82 - height * 0.72;

    Some((x.clamp(0.0, 1.0), y.clamp(0.0, 1.0)))
}

/// Where the sun sits, as a fraction of the screen: x from 0 (left) to 1
/// (right), y from 0 (top) to 1 (horizon). Returns `None` when it is down.
pub fn sun_position(time: &TimeOfDay) -> Option<(f32, f32)> {
    arc(time.fraction(), SUNRISE, SUNSET)
}

/// Where the moon sits, on the same terms as the sun.
pub fn moon_position(time: &TimeOfDay) -> Option<(f32, f32)> {
    // The moon takes the other half of the cycle.
    arc(time.fraction(), SUNSET + 0.04, 0.98)
}

/// How visible the stars are, from 0.0 to 1.0.
pub fn star_alpha(time: &TimeOfDay) -> f32 {
    let fraction = time.fraction();

    // Fade up after sunset and back down before dawn.
    let rising = ((fraction - SUNSET) / 0.09).clamp(0.0, 1.0);
    let falling = ((0.97 - fraction) / 0.09).clamp(0.0, 1.0);

    let visible = rising.min(falling);

    // Smoothstep so the fade has no corners.
    visible * visible * (3.0 - 2.0 * visible)
}

/// Draw one parallax hill layer as a silhouette with transparency above it.
pub fn hill_layer(seed: u64, layer: usize) -> Texture {
    let mut canvas = Canvas::new(HILL_WIDTH, HILL_HEIGHT);

    let depth = layer as f32 / (HILL_LAYERS.max(2) - 1) as f32;

    // Aerial perspective: distant ridges wash out toward the sky and sit
    // higher up the frame.
    let near = [58.0, 70.0, 92.0];
    let far = [150.0, 168.0, 196.0];
    let base = mix(far, near, depth);

    let layer_seed = seed ^ (layer as u64 + 1).wrapping_mul(0x9E37_79B9_7F4A_7C15);

    let periods = 2.0 + layer as f32;
    let amplitude = HILL_HEIGHT as f32 * (0.10 + depth * 0.16);
    let baseline = HILL_HEIGHT as f32 * (0.45 - depth * 0.12);

    let mut ridges: Vec<f32> = (0..HILL_WIDTH)
        .map(|x| {
            let along = x as f32 / HILL_WIDTH as f32;
            let wave = fbm_1d(layer_seed, along * periods, 3) - 0.5;
            let detail = fbm_1d(layer_seed ^ 0x55, along * periods * 3.0, 2) - 0.5;

            baseline + (wave * 2.0 + detail * 0.6) * amplitude
        })
        .collect();

    // fbm is not periodic, so the two ends of the strip do not meet on their
    // own. Ease the tail back to the first column's height, which closes the
    // join exactly when the layer repeats.
    let blend = (HILL_WIDTH / 6).max(1);
    let first = ridges[0];
    for step in 0..blend {
        let index = (HILL_WIDTH - blend + step) as usize;
        let t = (step + 1) as f32 / blend as f32;

        ridges[index] = ridges[index] * (1.0 - t) + first * t;
    }

    for x in 0..HILL_WIDTH {
        let top = ridges[x as usize].clamp(4.0, HILL_HEIGHT as f32 - 2.0) as u32;

        for y in top..HILL_HEIGHT {
            // Slightly darker toward the base, for a sense of bulk.
            let down = (y - top) as f32 / (HILL_HEIGHT - top).max(1) as f32;
            let shade = 1.0 - down * 0.18;

            canvas.put(
                x as i32,
                y as i32,
                [base[0] * shade, base[1] * shade, base[2] * shade],
            );
        }
    }

    canvas.into_texture()
}

/// Draw a field of stars, to be faded in at night.
pub fn star_field(seed: u64, width: u32, height: u32) -> Texture {
    let mut canvas = Canvas::new(width, height);

    // Roughly one star per 900 pixels: a scattering, not a disco ball.
    let count = (width * height / 900).max(1);

    for index in 0..count {
        let x = (hash01(seed, index as i64 * 3) * width as f32) as i32;
        let y = (hash01(seed, index as i64 * 3 + 1) * height as f32) as i32;

        // Vary brightness so the field has depth.
        let brightness = 150.0 + hash01(seed, index as i64 * 3 + 2) * 105.0;

        canvas.put(x, y, [brightness, brightness, brightness * 0.97]);
    }

    canvas.into_texture()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::daynight::DAY_LENGTH;

    fn at(fraction: f32) -> TimeOfDay {
        let mut time = TimeOfDay::dawn();
        time.advance(DAY_LENGTH * fraction);
        time
    }

    fn luminance(c: [f32; 3]) -> f32 {
        0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    }

    #[test]
    fn midday_sky_is_brighter_than_midnight_sky() {
        let noon = sky_colours(&at(0.25));
        let night = sky_colours(&at(0.70));

        assert!(
            luminance(noon.zenith) > luminance(night.zenith) + 40.0,
            "noon should be clearly brighter overhead"
        );
    }

    #[test]
    fn the_horizon_is_never_darker_than_the_zenith() {
        // Haze keeps the horizon lighter; the reverse looks wrong.
        for step in 0..60 {
            let colours = sky_colours(&at(step as f32 / 60.0));

            assert!(
                luminance(colours.horizon) >= luminance(colours.zenith) - 1.0,
                "at {}, horizon is darker than overhead",
                step as f32 / 60.0
            );
        }
    }

    #[test]
    fn dusk_is_warmer_than_noon() {
        // Sunset should redden rather than just dimming.
        let noon = sky_colours(&at(0.25)).horizon;
        let dusk = sky_colours(&at(0.48)).horizon;

        let noon_warmth = noon[0] / noon[2].max(1.0);
        let dusk_warmth = dusk[0] / dusk[2].max(1.0);

        assert!(
            dusk_warmth > noon_warmth,
            "dusk ({dusk_warmth:.2}) should be redder than noon ({noon_warmth:.2})"
        );
    }

    #[test]
    fn sky_colours_stay_in_range() {
        for step in 0..120 {
            let colours = sky_colours(&at(step as f32 / 120.0));

            for channel in colours.zenith.iter().chain(colours.horizon.iter()) {
                assert!(
                    (0.0..=255.0).contains(channel),
                    "colour channel {channel} out of range"
                );
            }
        }
    }

    #[test]
    fn sky_colours_change_smoothly() {
        let mut previous = sky_colours(&at(0.0));

        for step in 1..=400 {
            let current = sky_colours(&at(step as f32 / 400.0));

            let jump = (current.zenith[0] - previous.zenith[0]).abs()
                + (current.zenith[1] - previous.zenith[1]).abs()
                + (current.zenith[2] - previous.zenith[2]).abs();

            assert!(jump < 12.0, "sky jumped by {jump} at step {step}");
            previous = current;
        }
    }

    #[test]
    fn the_sun_is_up_by_day_and_down_by_night() {
        assert!(sun_position(&at(0.25)).is_some(), "sun should be up at noon");
        assert!(sun_position(&at(0.70)).is_none(), "sun should be down at night");
    }

    #[test]
    fn the_moon_is_up_at_night_and_down_by_day() {
        assert!(moon_position(&at(0.70)).is_some(), "moon should be up at night");
        assert!(moon_position(&at(0.25)).is_none(), "moon should be down at noon");
    }

    #[test]
    fn the_sun_climbs_and_then_sets() {
        // y is 0 at the top of the screen, so a smaller y is higher up.
        let morning = sun_position(&at(0.10)).expect("sun up").1;
        let noon = sun_position(&at(0.25)).expect("sun up").1;
        let evening = sun_position(&at(0.42)).expect("sun up").1;

        assert!(noon < morning, "the sun should be higher at noon than at dawn");
        assert!(noon < evening, "the sun should be lower again by evening");
    }

    #[test]
    fn the_sun_crosses_the_sky_from_one_side_to_the_other() {
        let morning = sun_position(&at(0.08)).expect("sun up").0;
        let evening = sun_position(&at(0.44)).expect("sun up").0;

        assert!(
            evening > morning + 0.4,
            "the sun should travel across the sky, not hover"
        );
    }

    #[test]
    fn the_sun_stays_on_screen_whenever_it_is_up() {
        for step in 0..200 {
            if let Some((x, y)) = sun_position(&at(step as f32 / 200.0)) {
                assert!((0.0..=1.0).contains(&x), "sun x {x} off screen");
                assert!((0.0..=1.0).contains(&y), "sun y {y} off screen");
            }
        }
    }

    #[test]
    fn stars_come_out_at_night_and_not_by_day() {
        assert!(star_alpha(&at(0.25)) < 0.05, "no stars at noon");
        assert!(star_alpha(&at(0.70)) > 0.6, "stars should be out at night");
    }

    #[test]
    fn stars_fade_in_and_out_rather_than_snapping() {
        let mut previous = star_alpha(&at(0.0));

        for step in 1..=400 {
            let current = star_alpha(&at(step as f32 / 400.0));

            assert!(
                (current - previous).abs() < 0.06,
                "stars jumped from {previous} to {current}"
            );
            assert!((0.0..=1.0).contains(&current));
            previous = current;
        }
    }

    #[test]
    fn hill_layers_are_the_declared_size() {
        for layer in 0..HILL_LAYERS {
            let texture = hill_layer(7, layer);

            assert_eq!(texture.width, HILL_WIDTH);
            assert_eq!(texture.height, HILL_HEIGHT);
        }
    }

    #[test]
    fn hills_have_sky_above_them_and_solid_ground_below() {
        let texture = hill_layer(7, 1);

        let top_filled = (0..texture.width)
            .filter(|&x| texture.pixel(x, 0)[3] > 0)
            .count();
        let bottom_filled = (0..texture.width)
            .filter(|&x| texture.pixel(x, texture.height - 1)[3] > 0)
            .count();

        assert_eq!(top_filled, 0, "the top of a hill layer should be open sky");
        assert_eq!(
            bottom_filled as u32, texture.width,
            "the bottom should be solid, or the layer floats"
        );
    }

    #[test]
    fn hill_layers_tile_without_a_visible_join() {
        // The left and right edges meet when the layer repeats, so their
        // silhouette heights have to agree.
        for layer in 0..HILL_LAYERS {
            let texture = hill_layer(7, layer);

            let height_at = |x: u32| {
                (0..texture.height)
                    .find(|&y| texture.pixel(x, y)[3] > 0)
                    .unwrap_or(texture.height)
            };

            let left = height_at(0) as i32;
            let right = height_at(texture.width - 1) as i32;

            assert!(
                (left - right).abs() <= 2,
                "layer {layer} joins {left} to {right} and will show a seam"
            );
        }
    }

    #[test]
    fn distant_layers_are_paler_than_near_ones() {
        // Aerial perspective: further hills wash out toward the sky.
        let far = hill_layer(7, 0);
        let near = hill_layer(7, HILL_LAYERS - 1);

        let mean = |texture: &Texture| {
            let pixels: Vec<f32> = texture
                .pixels
                .chunks_exact(4)
                .filter(|p| p[3] > 0)
                .map(|p| (p[0] as f32 + p[1] as f32 + p[2] as f32) / 3.0)
                .collect();
            pixels.iter().sum::<f32>() / pixels.len() as f32
        };

        assert!(
            mean(&far) > mean(&near),
            "distant hills should be paler than near ones"
        );
    }

    #[test]
    fn hill_layers_differ_from_one_another() {
        assert_ne!(hill_layer(7, 0).pixels, hill_layer(7, 1).pixels);
    }

    #[test]
    fn hill_generation_is_deterministic() {
        assert_eq!(hill_layer(7, 1), hill_layer(7, 1));
    }

    #[test]
    fn parallax_factors_increase_toward_the_viewer() {
        for pair in HILL_PARALLAX.windows(2) {
            assert!(pair[1] > pair[0], "layers should get nearer, not further");
        }
        assert!(
            HILL_PARALLAX[HILL_LAYERS - 1] < 1.0,
            "even the nearest backdrop must lag the world"
        );
    }

    #[test]
    fn the_star_field_is_mostly_empty_sky() {
        let texture = star_field(7, 256, 256);

        let lit = texture
            .pixels
            .chunks_exact(4)
            .filter(|p| p[3] > 0)
            .count();
        let fraction = lit as f32 / (256.0 * 256.0);

        assert!(fraction > 0.0001, "there should be some stars");
        assert!(
            fraction < 0.03,
            "a sky that is {:.1}% stars is a disco ball",
            fraction * 100.0
        );
    }

    #[test]
    fn star_generation_is_deterministic() {
        assert_eq!(star_field(3, 64, 64), star_field(3, 64, 64));
    }
}
