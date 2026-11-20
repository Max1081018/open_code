#!/usr/bin/env python3
"""Turn downloaded sound effects into the form the game ships.

Library sounds arrive as 24-bit stereo at 44.1 or 48 kHz, which is studio
master format: for a phone game it is four to six times larger than it needs
to be and the difference is inaudible through a handset speaker. This
normalises every effect to one format so the audio budget is predictable,
and does the four things a raw download always needs:

  * mix to mono        — these are point sources in a 2D world, and the
                         stereo image of the original recording is not ours
  * resample to 22 kHz — matches the rate the synthesised fallbacks use
  * trim leading quiet — a sound that starts 50 ms late feels unresponsive
                         when it is triggered by a button press
  * level-match        — so no one effect is startling next to the others

Run from anywhere:  python3 tools/prepare_sfx.py <raw-dir> <out-dir>

Only the standard library is used: this has to run in environments where
installing an audio package is not an option.
"""

import array
import os
import struct
import sys
import wave

#: Output sample rate. Matches `SFX_RATE` in core/src/audio.rs.
RATE = 22_050

#: Peak each effect is scaled to. Short of 1.0 so that two effects landing
#: on the same frame do not clip the mix.
TARGET_PEAK = 0.82

#: Amplitude below which the head of a file counts as silence.
SILENCE = 0.02

#: Fraction of a sound's own peak that counts as "the sound has started".
#: An absolute threshold is not enough on its own: a recording can creep in
#: above the silence floor for a tenth of a second before the real transient,
#: which reads as lag when the effect is fired by a button press.
ONSET_FRACTION = 0.25

#: Seconds of run-up kept before that transient, so the natural attack of
#: the recording survives the tightening.
RUN_UP = 0.015

#: Seconds of fade at each end. Enough to kill a click from a non-zero
#: first or last sample, short enough not to soften a transient.
FADE = 0.004


def decode(path):
    """Read any PCM wav as mono floats in -1..1, with its sample rate."""
    with wave.open(path, "rb") as source:
        channels = source.getnchannels()
        width = source.getsampwidth()
        rate = source.getframerate()
        raw = source.readframes(source.getnframes())

    if width == 2:
        samples = array.array("h")
        samples.frombytes(raw)
        scale = 1.0 / 32768.0
        flat = [value * scale for value in samples]
    elif width == 3:
        # 24-bit has no array typecode; sign-extend each triple by hand.
        count = len(raw) // 3
        flat = [0.0] * count
        for index in range(count):
            chunk = raw[index * 3 : index * 3 + 3]
            value = chunk[0] | (chunk[1] << 8) | (chunk[2] << 16)
            if value & 0x800000:
                value -= 0x1000000
            flat[index] = value / 8388608.0
    elif width == 4:
        samples = array.array("i")
        samples.frombytes(raw)
        flat = [value / 2147483648.0 for value in samples]
    else:
        raise ValueError(f"{path}: unsupported sample width {width}")

    if channels == 1:
        return flat, rate

    frames = len(flat) // channels
    return [
        sum(flat[frame * channels : (frame + 1) * channels]) / channels
        for frame in range(frames)
    ], rate


def resample(samples, source_rate, target_rate):
    """Linear resample. Good enough for short effects at these rates."""
    if source_rate == target_rate or not samples:
        return samples

    ratio = source_rate / target_rate
    count = max(1, int(len(samples) / ratio))
    out = [0.0] * count

    for index in range(count):
        position = index * ratio
        left = int(position)
        right = min(left + 1, len(samples) - 1)
        blend = position - left
        out[index] = samples[left] * (1.0 - blend) + samples[right] * blend

    return out


def trim_head(samples):
    """Drop everything before the sound actually starts.

    Two stages, because either alone gets it wrong. The silence floor
    catches digital silence but leaves a quiet creep-in intact; the
    peak-relative onset catches the creep-in but, used alone on a sound
    that fades up deliberately, would eat the fade. Taking the later of the
    two cuts and keeping a run-up before it preserves the attack.
    """
    if not samples:
        return samples

    peak = max(abs(value) for value in samples)
    if peak <= 1e-6:
        return samples

    first_sound = next(
        (index for index, value in enumerate(samples) if abs(value) >= SILENCE),
        0,
    )
    first_loud = next(
        (
            index
            for index, value in enumerate(samples)
            if abs(value) >= peak * ONSET_FRACTION
        ),
        0,
    )

    cut = max(first_sound, first_loud - int(RATE * RUN_UP))
    return samples[max(0, cut) :]


def normalise(samples):
    peak = max((abs(value) for value in samples), default=0.0)
    if peak <= 1e-6:
        return samples

    gain = TARGET_PEAK / peak
    return [value * gain for value in samples]


def fade_edges(samples):
    span = min(int(RATE * FADE), len(samples) // 2)
    if span <= 0:
        return samples

    for index in range(span):
        ramp = index / span
        samples[index] *= ramp
        samples[-1 - index] *= ramp

    return samples


def convert(src, dst):
    samples, rate = decode(src)
    samples = fade_edges(normalise(trim_head(resample(samples, rate, RATE))))

    out = array.array(
        "h", (int(max(-1.0, min(1.0, value)) * 32767) for value in samples)
    )

    with wave.open(dst, "wb") as sink:
        sink.setnchannels(1)
        sink.setsampwidth(2)
        sink.setframerate(RATE)
        sink.writeframes(out.tobytes())

    return len(out) / RATE


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 1

    raw_dir, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)

    total = 0
    for name in sorted(os.listdir(raw_dir)):
        if not name.endswith(".wav"):
            continue

        src = os.path.join(raw_dir, name)
        dst = os.path.join(out_dir, name)
        seconds = convert(src, dst)
        size = os.path.getsize(dst)
        total += size

        print(
            f"{name:12s} {os.path.getsize(src):>8,}b -> {size:>7,}b  {seconds:.2f}s"
        )

    print(f"{'total':12s} {'':>9} {total:>8,}b")
    return 0


if __name__ == "__main__":
    sys.exit(main())
