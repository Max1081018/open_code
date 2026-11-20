"""Cuts a seamless loop from an ambience recording: the first `length`
seconds, with the `fade` seconds that follow cross-faded into the start,
so the end flows back into the beginning without a click.

python3 tools/make_loop.py in.wav out.ogg [length] [fade]
"""
import subprocess, sys
import numpy as np

src, dst = sys.argv[1], sys.argv[2]
length = float(sys.argv[3]) if len(sys.argv) > 3 else 40.0
fade = float(sys.argv[4]) if len(sys.argv) > 4 else 3.0
rate = 44100
raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", src, "-ac", "1", "-ar", str(rate),
                      "-f", "f32le", "-"], capture_output=True, check=True).stdout
x = np.frombuffer(raw, dtype=np.float32).copy()
n, f = int(length * rate), int(fade * rate)
if len(x) < n + f:
    raise SystemExit("recording too short")
body, tail = x[:n].copy(), x[n:n + f]
ramp = np.linspace(0.0, 1.0, f, dtype=np.float32)
# Equal-power crossfade: the tail fades out over the start fading in.
body[:f] = body[:f] * np.sqrt(ramp) + tail * np.sqrt(1.0 - ramp)
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "f32le", "-ar", str(rate), "-ac", "1", "-i", "-",
                "-c:a", "libvorbis", "-q:a", "3", dst], input=body.tobytes(), check=True)
print("wrote", dst, len(body) / rate, "s")
