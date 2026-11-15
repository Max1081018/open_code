//! Deterministic value noise.
//!
//! Hand-rolled rather than pulled from a crate so that worldgen stays
//! dependency-free and every property we rely on (determinism, range,
//! continuity) is pinned by tests in this repo.

/// Largest `f32` strictly below 1.0, so returned values never reach the
/// exclusive upper bound through rounding.
const JUST_UNDER_ONE: f32 = 1.0 - f32::EPSILON;

/// A deterministic hash of `i` under `seed`, in `[0, 1)`.
///
/// SplitMix64-style finalizer: cheap, no state, and well-distributed enough
/// that neighbouring integers look unrelated.
pub fn hash01(seed: u64, i: i64) -> f32 {
    let mut z = (i as u64)
        .wrapping_mul(0x9E37_79B9_7F4A_7C15)
        .wrapping_add(seed.wrapping_mul(0xBF58_476D_1CE4_E5B9));
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^= z >> 31;

    // Top 24 bits: exactly the mantissa width of f32, so every result is
    // representable and the division is exact.
    (z >> 40) as f32 / (1u32 << 24) as f32
}

/// Smooth 1-D value noise in `[0, 1)`, interpolating `hash01` at integer points.
pub fn value_noise_1d(seed: u64, x: f32) -> f32 {
    let cell = x.floor();
    let frac = x - cell;

    let left = hash01(seed, cell as i64);
    let right = hash01(seed, cell as i64 + 1);

    // Smoothstep easing: zero first derivative at both ends, so octaves of
    // this stack without visible grid creases.
    let t = frac * frac * (3.0 - 2.0 * frac);

    left + (right - left) * t
}

/// Fractal (summed-octave) 1-D noise in `[0, 1)`.
///
/// Each octave doubles frequency and halves amplitude, and gets its own seed
/// so the layers do not correlate.
pub fn fbm_1d(seed: u64, x: f32, octaves: u32) -> f32 {
    let mut sum = 0.0;
    let mut normaliser = 0.0;
    let mut amplitude = 0.5;
    let mut frequency = 1.0;

    for octave in 0..octaves {
        let octave_seed = seed ^ (octave as u64 + 1).wrapping_mul(0x9E37_79B9_7F4A_7C15);
        sum += value_noise_1d(octave_seed, x * frequency) * amplitude;
        normaliser += amplitude;

        amplitude *= 0.5;
        frequency *= 2.0;
    }

    if normaliser == 0.0 {
        return 0.0;
    }

    (sum / normaliser).clamp(0.0, JUST_UNDER_ONE)
}

/// A deterministic hash of the lattice point `(x, y)` under `seed`, in `[0, 1)`.
///
/// `x` and `y` get different multipliers so the field is not symmetric across
/// the diagonal, which would otherwise show up as seams in carved caves.
pub fn hash01_2d(seed: u64, x: i64, y: i64) -> f32 {
    let mut z = (x as u64)
        .wrapping_mul(0x9E37_79B9_7F4A_7C15)
        ^ (y as u64).wrapping_mul(0xC2B2_AE3D_27D4_EB4F)
        ^ seed.wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^= z >> 31;

    (z >> 40) as f32 / (1u32 << 24) as f32
}

/// Smooth 2-D value noise in `[0, 1)`, interpolating `hash01_2d` at lattice points.
pub fn value_noise_2d(seed: u64, x: f32, y: f32) -> f32 {
    let cell_x = x.floor();
    let cell_y = y.floor();
    let (ix, iy) = (cell_x as i64, cell_y as i64);

    let corner_00 = hash01_2d(seed, ix, iy);
    let corner_10 = hash01_2d(seed, ix + 1, iy);
    let corner_01 = hash01_2d(seed, ix, iy + 1);
    let corner_11 = hash01_2d(seed, ix + 1, iy + 1);

    let fx = x - cell_x;
    let fy = y - cell_y;
    let tx = fx * fx * (3.0 - 2.0 * fx);
    let ty = fy * fy * (3.0 - 2.0 * fy);

    let upper = corner_00 + (corner_10 - corner_00) * tx;
    let lower = corner_01 + (corner_11 - corner_01) * tx;

    upper + (lower - upper) * ty
}

/// Fractal (summed-octave) 2-D noise in `[0, 1)`.
pub fn fbm_2d(seed: u64, x: f32, y: f32, octaves: u32) -> f32 {
    let mut sum = 0.0;
    let mut normaliser = 0.0;
    let mut amplitude = 0.5;
    let mut frequency = 1.0;

    for octave in 0..octaves {
        let octave_seed = seed ^ (octave as u64 + 1).wrapping_mul(0x9E37_79B9_7F4A_7C15);
        sum += value_noise_2d(octave_seed, x * frequency, y * frequency) * amplitude;
        normaliser += amplitude;

        amplitude *= 0.5;
        frequency *= 2.0;
    }

    if normaliser == 0.0 {
        return 0.0;
    }

    (sum / normaliser).clamp(0.0, JUST_UNDER_ONE)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash01_is_deterministic_for_the_same_inputs() {
        for i in -50..50 {
            assert_eq!(hash01(42, i), hash01(42, i), "hash01(42, {i}) changed");
        }
    }

    #[test]
    fn hash01_stays_within_the_unit_range() {
        for i in -500..500 {
            let v = hash01(9, i);
            assert!((0.0..1.0).contains(&v), "hash01(9, {i}) = {v} out of range");
        }
    }

    #[test]
    fn hash01_differs_across_seeds() {
        let differing = (0..200).filter(|&i| hash01(1, i) != hash01(2, i)).count();

        assert!(
            differing > 190,
            "different seeds should give different noise; only {differing}/200 differed"
        );
    }

    #[test]
    fn value_noise_matches_hash_at_integer_points() {
        for i in 0..20 {
            let noise = value_noise_1d(5, i as f32);
            let hash = hash01(5, i);

            assert!(
                (noise - hash).abs() < 1e-5,
                "at x={i}, value noise {noise} should anchor to hash {hash}"
            );
        }
    }

    #[test]
    fn value_noise_is_continuous_between_integer_points() {
        let mut previous = value_noise_1d(11, 0.0);

        for step in 1..=1000 {
            let x = step as f32 * 0.01;
            let current = value_noise_1d(11, x);

            assert!(
                (current - previous).abs() < 0.05,
                "value noise jumped from {previous} to {current} at x={x}"
            );
            previous = current;
        }
    }

    #[test]
    fn hash01_2d_is_deterministic_for_the_same_inputs() {
        for x in -20..20 {
            for y in -20..20 {
                assert_eq!(
                    hash01_2d(42, x, y),
                    hash01_2d(42, x, y),
                    "hash01_2d(42, {x}, {y}) changed"
                );
            }
        }
    }

    #[test]
    fn hash01_2d_stays_within_the_unit_range() {
        for x in -60..60 {
            for y in -60..60 {
                let v = hash01_2d(9, x, y);
                assert!(
                    (0.0..1.0).contains(&v),
                    "hash01_2d(9, {x}, {y}) = {v} out of range"
                );
            }
        }
    }

    #[test]
    fn hash01_2d_is_not_symmetric_across_the_diagonal() {
        // A hash that treats (x, y) and (y, x) alike paints visible diagonal
        // seams through the caves, so pin the asymmetry.
        let differing = (1..100)
            .filter(|&i| hash01_2d(4, i, i * 2) != hash01_2d(4, i * 2, i))
            .count();

        assert!(
            differing > 95,
            "swapped coordinates should hash differently; only {differing}/99 differed"
        );
    }

    #[test]
    fn value_noise_2d_matches_hash_at_lattice_points() {
        for x in 0..12 {
            for y in 0..12 {
                let noise = value_noise_2d(5, x as f32, y as f32);
                let hash = hash01_2d(5, x, y);

                assert!(
                    (noise - hash).abs() < 1e-5,
                    "at ({x}, {y}), value noise {noise} should anchor to hash {hash}"
                );
            }
        }
    }

    #[test]
    fn value_noise_2d_is_continuous_along_both_axes() {
        for axis in 0..2 {
            let mut previous = value_noise_2d(11, 0.0, 0.0);

            for step in 1..=400 {
                let d = step as f32 * 0.01;
                let (x, y) = if axis == 0 { (d, 0.0) } else { (0.0, d) };
                let current = value_noise_2d(11, x, y);

                assert!(
                    (current - previous).abs() < 0.05,
                    "2-D noise jumped from {previous} to {current} at ({x}, {y})"
                );
                previous = current;
            }
        }
    }

    #[test]
    fn fbm_2d_stays_within_the_unit_range() {
        for step in 0..1500 {
            let x = step as f32 * 0.31;
            let y = step as f32 * 0.17;
            let v = fbm_2d(3, x, y, 5);

            assert!(
                (0.0..1.0).contains(&v),
                "fbm_2d(3, {x}, {y}, 5) = {v} out of range"
            );
        }
    }

    #[test]
    fn fbm_stays_within_the_unit_range() {
        for step in 0..2000 {
            let x = step as f32 * 0.37;
            let v = fbm_1d(3, x, 5);

            assert!((0.0..1.0).contains(&v), "fbm_1d(3, {x}, 5) = {v} out of range");
        }
    }
}
