//! Synthesised sound.
//!
//! Every sound in the game is generated as PCM and wrapped in a WAV, because
//! sample libraries (Freesound, Pixabay and the rest) are unreachable from
//! the build environment. Keeping it synthesised also means the whole sound
//! bank costs a few kilobytes of code rather than megabytes of audio.

use crate::noise::hash01;

/// Sample rate for effects. Plenty for short percussive sounds.
pub const SFX_RATE: u32 = 22_050;

/// Sample rate for the ambient bed, which is all low-frequency content.
pub const AMBIENT_RATE: u32 = 22_050;

/// Bytes of WAV header before the sample data begins.
pub const WAV_HEADER_LEN: usize = 44;

/// A short sound effect.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum Sfx {
    /// Pick biting into rock.
    Dig,
    /// A tile giving way.
    Break,
    /// A blow landing on something alive.
    Hit,
    /// Taking damage.
    Hurt,
    /// Leaving the ground.
    Jump,
    /// Coming back down.
    Land,
    /// Something going into the bag.
    Pickup,
    /// A recipe completing.
    Craft,
    /// A boss arriving.
    Roar,
    /// Interface feedback.
    Click,
}

/// Every effect, for pre-generating the bank.
pub const ALL_SFX: [Sfx; 10] = [
    Sfx::Dig,
    Sfx::Break,
    Sfx::Hit,
    Sfx::Hurt,
    Sfx::Jump,
    Sfx::Land,
    Sfx::Pickup,
    Sfx::Craft,
    Sfx::Roar,
    Sfx::Click,
];

/// Wrap mono 16-bit samples in a WAV container.
pub fn encode_wav_mono(sample_rate: u32, samples: &[i16]) -> Vec<u8> {
    let data_len = (samples.len() * 2) as u32;
    let mut wav = Vec::with_capacity(WAV_HEADER_LEN + data_len as usize);

    wav.extend_from_slice(b"RIFF");
    wav.extend_from_slice(&(36 + data_len).to_le_bytes());
    wav.extend_from_slice(b"WAVE");

    wav.extend_from_slice(b"fmt ");
    wav.extend_from_slice(&16u32.to_le_bytes()); // chunk size
    wav.extend_from_slice(&1u16.to_le_bytes()); // uncompressed PCM
    wav.extend_from_slice(&1u16.to_le_bytes()); // mono
    wav.extend_from_slice(&sample_rate.to_le_bytes());
    wav.extend_from_slice(&(sample_rate * 2).to_le_bytes()); // bytes per second
    wav.extend_from_slice(&2u16.to_le_bytes()); // block align
    wav.extend_from_slice(&16u16.to_le_bytes()); // bits per sample

    wav.extend_from_slice(b"data");
    wav.extend_from_slice(&data_len.to_le_bytes());

    for sample in samples {
        wav.extend_from_slice(&sample.to_le_bytes());
    }

    wav
}

/// White noise in `-1.0..1.0`, deterministic in `index`.
fn noise(seed: u64, index: usize) -> f32 {
    hash01(seed, index as i64) * 2.0 - 1.0
}

/// Exponential decay envelope: 1.0 at the start, approaching 0 by the end.
fn decay(progress: f32, sharpness: f32) -> f32 {
    (-progress * sharpness).exp()
}

/// Fade the first and last few milliseconds so a sound cannot click.
fn apply_edge_fade(samples: &mut [f32], rate: u32) {
    let fade = ((rate as f32 * 0.004) as usize).max(1).min(samples.len() / 2);
    let count = samples.len();

    for index in 0..fade {
        let gain = index as f32 / fade as f32;
        samples[index] *= gain;
        samples[count - 1 - index] *= gain;
    }
}

/// Convert a float buffer to 16-bit, normalised to `peak`.
fn to_pcm(samples: &[f32], peak: f32) -> Vec<i16> {
    let loudest = samples
        .iter()
        .fold(0.0f32, |acc, value| acc.max(value.abs()))
        .max(1e-6);

    let gain = peak / loudest;

    samples
        .iter()
        .map(|value| (value * gain * i16::MAX as f32) as i16)
        .collect()
}

/// Shape and length of one effect.
struct Recipe {
    seconds: f32,
    /// Peak level, leaving headroom below full scale.
    peak: f32,
}

fn recipe(kind: Sfx) -> Recipe {
    match kind {
        Sfx::Dig => Recipe { seconds: 0.18, peak: 0.55 },
        Sfx::Break => Recipe { seconds: 0.34, peak: 0.70 },
        Sfx::Hit => Recipe { seconds: 0.22, peak: 0.75 },
        Sfx::Hurt => Recipe { seconds: 0.40, peak: 0.70 },
        Sfx::Jump => Recipe { seconds: 0.20, peak: 0.45 },
        Sfx::Land => Recipe { seconds: 0.22, peak: 0.50 },
        Sfx::Pickup => Recipe { seconds: 0.26, peak: 0.42 },
        Sfx::Craft => Recipe { seconds: 0.55, peak: 0.48 },
        Sfx::Roar => Recipe { seconds: 1.40, peak: 0.80 },
        Sfx::Click => Recipe { seconds: 0.07, peak: 0.30 },
    }
}

/// Render one sound effect as a WAV.
pub fn sfx_wav(kind: Sfx) -> Vec<u8> {
    let Recipe { seconds, peak } = recipe(kind);

    let count = (SFX_RATE as f32 * seconds) as usize;
    let mut buffer = vec![0.0f32; count];
    let seed = 0xA0D1 ^ ((kind as u64 + 1) * 0x9E37_79B9);

    for (index, slot) in buffer.iter_mut().enumerate() {
        let progress = index as f32 / count as f32;
        let t = index as f32 / SFX_RATE as f32;
        let tone = |hz: f32| (t * hz * std::f32::consts::TAU).sin();

        *slot = match kind {
            // Granular scrape plus a low thump: reads as stone, not a beep.
            Sfx::Dig => {
                noise(seed, index) * decay(progress, 7.0) * 0.6
                    + tone(90.0 - progress * 30.0) * decay(progress, 11.0) * 0.5
            }

            // A crack, then rubble.
            Sfx::Break => {
                noise(seed, index) * decay(progress, 4.0) * 0.8
                    + tone(140.0 - progress * 80.0) * decay(progress, 6.0) * 0.4
                    + noise(seed ^ 0xBB, index / 3) * decay(progress, 2.5) * 0.3
            }

            // Sharp transient with a short body.
            Sfx::Hit => {
                noise(seed, index) * decay(progress, 22.0) * 0.9
                    + tone(320.0 - progress * 200.0) * decay(progress, 9.0) * 0.6
            }

            // A falling cry.
            Sfx::Hurt => {
                tone(420.0 - progress * 260.0) * decay(progress, 4.0) * 0.8
                    + noise(seed, index) * decay(progress, 14.0) * 0.25
            }

            // Rising blip.
            Sfx::Jump => tone(220.0 + progress * 340.0) * decay(progress, 5.5),

            // Soft thud with grit.
            Sfx::Land => {
                tone(120.0 - progress * 50.0) * decay(progress, 9.0) * 0.8
                    + noise(seed, index) * decay(progress, 18.0) * 0.4
            }

            // Two quick ascending notes.
            Sfx::Pickup => {
                let note = if progress < 0.5 { 660.0 } else { 880.0 };
                tone(note) * decay(progress % 0.5, 9.0)
            }

            // A small three-note flourish.
            Sfx::Craft => {
                let note = match progress {
                    p if p < 0.33 => 523.0,
                    p if p < 0.66 => 659.0,
                    _ => 784.0,
                };
                tone(note) * decay(progress % 0.33, 7.0) * 0.9
            }

            // Low growl: detuned bass plus a slow rasp.
            Sfx::Roar => {
                let swell = (progress * std::f32::consts::PI).sin();
                (tone(58.0) + tone(61.0) * 0.8 + tone(87.0) * 0.4) * swell * 0.5
                    + noise(seed, index / 2) * swell * 0.25
            }

            // Tiny tick.
            Sfx::Click => tone(1400.0) * decay(progress, 26.0),
        };
    }

    apply_edge_fade(&mut buffer, SFX_RATE);
    encode_wav_mono(SFX_RATE, &to_pcm(&buffer, peak))
}

/// Render a seamless ambient loop as a WAV.
///
/// `warmth` from 0.0 to 1.0 shifts the bed from cold and cavernous toward
/// warm and open, so the underground and the surface can sound different.
pub fn ambient_wav(seed: u64, seconds: f32, warmth: f32) -> Vec<u8> {
    let count = (AMBIENT_RATE as f32 * seconds) as usize;
    let mut buffer = vec![0.0f32; count];
    let warmth = warmth.clamp(0.0, 1.0);

    // Every partial completes a whole number of cycles over the loop, which
    // is what makes the end meet the beginning without a seam.
    let root = 55.0 + warmth * 18.0;
    let partials: [(f32, f32); 5] = [
        (1.0, 1.00),
        (1.5, 0.55),
        (2.0, 0.40),
        (3.0, 0.22 + warmth * 0.18),
        (4.0, 0.12 * warmth),
    ];

    for (voice, (ratio, level)) in partials.into_iter().enumerate() {
        // Round to a whole cycle count so the partial loops cleanly.
        let cycles = (root * ratio * seconds).round().max(1.0);
        let drift = hash01(seed, voice as i64) * 0.4 - 0.2;

        // The tremolo also has to complete whole cycles.
        let sway_cycles = (1.0 + voice as f32 * 0.5).round();

        for (index, slot) in buffer.iter_mut().enumerate() {
            let phase = index as f32 / count as f32;
            let sway =
                0.75 + 0.25 * (phase * sway_cycles * std::f32::consts::TAU + drift).sin();

            *slot += (phase * cycles * std::f32::consts::TAU + drift).sin() * level * sway;
        }
    }

    // A breath of air movement, also looped so it does not seam.
    for (index, slot) in buffer.iter_mut().enumerate() {
        let phase = index as f32 / count as f32;
        let breath = (phase * 2.0 * std::f32::consts::TAU).sin() * 0.5 + 0.5;
        let band = noise(seed ^ 0x5EA, index / 64) * 0.06 * (1.0 - warmth * 0.5);

        *slot += band * breath;
    }

    // Ambience sits under the effects rather than fighting them.
    encode_wav_mono(AMBIENT_RATE, &to_pcm(&buffer, 0.38))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Pull the sample data back out of a WAV for inspection.
    fn samples_of(wav: &[u8]) -> Vec<i16> {
        wav[WAV_HEADER_LEN..]
            .chunks_exact(2)
            .map(|pair| i16::from_le_bytes([pair[0], pair[1]]))
            .collect()
    }

    fn peak(samples: &[i16]) -> i32 {
        samples.iter().map(|s| (*s as i32).abs()).max().unwrap_or(0)
    }

    fn rms(samples: &[i16]) -> f64 {
        if samples.is_empty() {
            return 0.0;
        }
        let sum: f64 = samples.iter().map(|s| (*s as f64).powi(2)).sum();
        (sum / samples.len() as f64).sqrt()
    }

    #[test]
    fn a_wav_starts_with_the_expected_container_markers() {
        let wav = encode_wav_mono(SFX_RATE, &[0, 1, -1]);

        assert_eq!(&wav[0..4], b"RIFF");
        assert_eq!(&wav[8..12], b"WAVE");
        assert_eq!(&wav[12..16], b"fmt ");
        assert_eq!(&wav[36..40], b"data");
    }

    #[test]
    fn the_wav_header_declares_mono_sixteen_bit_pcm() {
        let wav = encode_wav_mono(SFX_RATE, &[0; 8]);

        let format = u16::from_le_bytes([wav[20], wav[21]]);
        let channels = u16::from_le_bytes([wav[22], wav[23]]);
        let rate = u32::from_le_bytes([wav[24], wav[25], wav[26], wav[27]]);
        let bits = u16::from_le_bytes([wav[34], wav[35]]);

        assert_eq!(format, 1, "should be uncompressed PCM");
        assert_eq!(channels, 1, "should be mono");
        assert_eq!(rate, SFX_RATE);
        assert_eq!(bits, 16);
    }

    #[test]
    fn the_declared_sizes_match_the_actual_data() {
        let samples = vec![0i16; 1000];
        let wav = encode_wav_mono(SFX_RATE, &samples);

        let riff_size = u32::from_le_bytes([wav[4], wav[5], wav[6], wav[7]]) as usize;
        let data_size = u32::from_le_bytes([wav[40], wav[41], wav[42], wav[43]]) as usize;

        assert_eq!(data_size, samples.len() * 2, "data chunk size");
        assert_eq!(riff_size, wav.len() - 8, "riff size counts all that follows");
        assert_eq!(wav.len(), WAV_HEADER_LEN + samples.len() * 2);
    }

    #[test]
    fn samples_survive_the_round_trip() {
        let samples = vec![0i16, 1000, -1000, i16::MAX, i16::MIN];

        let recovered = samples_of(&encode_wav_mono(SFX_RATE, &samples));

        assert_eq!(recovered, samples);
    }

    #[test]
    fn every_effect_produces_an_audible_sound() {
        for kind in ALL_SFX {
            let samples = samples_of(&sfx_wav(kind));

            assert!(!samples.is_empty(), "{kind:?} is empty");
            assert!(
                peak(&samples) > 2000,
                "{kind:?} peaks at only {}, which is inaudible",
                peak(&samples)
            );
        }
    }

    #[test]
    fn no_effect_clips_at_full_scale() {
        for kind in ALL_SFX {
            let samples = samples_of(&sfx_wav(kind));

            assert!(
                peak(&samples) < 32_000,
                "{kind:?} peaks at {} and will clip",
                peak(&samples)
            );
        }
    }

    #[test]
    fn effects_begin_and_end_in_silence() {
        // A sound that starts or stops mid-waveform clicks on every play.
        for kind in ALL_SFX {
            let samples = samples_of(&sfx_wav(kind));

            assert!(
                samples[0].abs() < 600,
                "{kind:?} starts at {} and will click",
                samples[0]
            );
            assert!(
                samples[samples.len() - 1].abs() < 600,
                "{kind:?} ends at {} and will click",
                samples[samples.len() - 1]
            );
        }
    }

    #[test]
    fn effects_are_short_enough_to_feel_responsive() {
        for kind in ALL_SFX {
            let samples = samples_of(&sfx_wav(kind));
            let seconds = samples.len() as f32 / SFX_RATE as f32;

            assert!(
                seconds < 2.5,
                "{kind:?} runs {seconds:.2}s, too long for a game effect"
            );
            assert!(seconds > 0.01, "{kind:?} is too short to hear");
        }
    }

    #[test]
    fn different_effects_actually_sound_different() {
        for pair in ALL_SFX.windows(2) {
            let first = sfx_wav(pair[0]);
            let second = sfx_wav(pair[1]);

            assert_ne!(
                first, second,
                "{:?} and {:?} are the same sound",
                pair[0], pair[1]
            );
        }
    }

    #[test]
    fn a_roar_is_weightier_than_a_click() {
        let roar = samples_of(&sfx_wav(Sfx::Roar));
        let click = samples_of(&sfx_wav(Sfx::Click));

        assert!(
            roar.len() > click.len(),
            "a boss arriving should last longer than a button press"
        );
        assert!(
            rms(&roar) > rms(&click),
            "a roar should carry more energy than a click"
        );
    }

    #[test]
    fn effect_synthesis_is_deterministic() {
        assert_eq!(sfx_wav(Sfx::Dig), sfx_wav(Sfx::Dig));
    }

    #[test]
    fn the_ambient_bed_runs_for_the_length_asked_for() {
        let wav = ambient_wav(1, 4.0, 0.5);
        let samples = samples_of(&wav);

        let seconds = samples.len() as f32 / AMBIENT_RATE as f32;

        assert!(
            (seconds - 4.0).abs() < 0.1,
            "asked for 4s, got {seconds:.2}s"
        );
    }

    #[test]
    fn the_ambient_bed_is_audible_but_gentle() {
        let samples = samples_of(&ambient_wav(1, 4.0, 0.5));

        assert!(peak(&samples) > 1500, "ambience should be audible");
        assert!(
            peak(&samples) < 20_000,
            "ambience should sit under the effects, not fight them"
        );
    }

    #[test]
    fn the_ambient_bed_loops_without_a_seam() {
        // The last sample must line up with the first, or the loop ticks.
        let samples = samples_of(&ambient_wav(1, 4.0, 0.5));

        let first = samples[0] as i32;
        let last = samples[samples.len() - 1] as i32;

        assert!(
            (first - last).abs() < 900,
            "loop seam jumps from {last} to {first} and will tick"
        );
    }

    #[test]
    fn warm_and_cold_beds_differ() {
        let cold = ambient_wav(1, 2.0, 0.0);
        let warm = ambient_wav(1, 2.0, 1.0);

        assert_ne!(cold, warm, "warmth should change the sound");
    }

    #[test]
    fn different_seeds_give_different_beds() {
        assert_ne!(ambient_wav(1, 2.0, 0.5), ambient_wav(2, 2.0, 0.5));
    }

    #[test]
    fn ambient_synthesis_is_deterministic() {
        assert_eq!(ambient_wav(3, 2.0, 0.4), ambient_wav(3, 2.0, 0.4));
    }

    #[test]
    fn ambience_has_no_standing_dc_offset() {
        // A constant offset wastes headroom and can thump on some hardware.
        let samples = samples_of(&ambient_wav(1, 4.0, 0.5));

        let mean: f64 =
            samples.iter().map(|s| *s as f64).sum::<f64>() / samples.len() as f64;

        assert!(
            mean.abs() < 400.0,
            "ambience sits at a DC offset of {mean:.0}"
        );
    }

    #[test]
    fn the_whole_sound_bank_stays_small() {
        // Everything is generated, so this is really a guard on run time and
        // memory rather than on download size.
        let total: usize = ALL_SFX.iter().map(|&k| sfx_wav(k).len()).sum();

        assert!(
            total < 2_000_000,
            "the effect bank is {total} bytes, which is too much to hold"
        );
    }

    #[test]
    fn an_unused_salt_still_produces_valid_audio() {
        // Guards the encoder against zero-length input.
        let wav = encode_wav_mono(SFX_RATE, &[]);

        assert_eq!(wav.len(), WAV_HEADER_LEN);
        assert_eq!(&wav[0..4], b"RIFF");
    }

    #[test]
    fn noise_is_used_rather_than_a_pure_tone_for_percussive_sounds() {
        // A dig made of a single sine reads as a beep, not an impact. Check
        // the waveform is not periodic by comparing halves.
        let samples = samples_of(&sfx_wav(Sfx::Dig));
        let half = samples.len() / 2;

        let matching = samples[..half]
            .iter()
            .zip(&samples[half..])
            .filter(|(a, b)| (**a as i32 - **b as i32).abs() < 50)
            .count();

        assert!(
            matching < half * 3 / 4,
            "the dig sound is too periodic; it will read as a beep"
        );
    }
}
