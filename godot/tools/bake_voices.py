"""Bakes every line in assets/story/dialogue.json to a voiced Ogg file with
Piper (https://github.com/rhasspy/piper, MIT; voices from
huggingface.co/rhasspy/piper-voices, each under its own licence, listed in
ASSET_CATALOG.md). Done offline at build time: the game ships plain audio
files, so voices work on any phone with no model, no network and no CPU
cost at runtime.

Re-run after editing dialogue.json; unchanged lines are skipped (a hash of
voice + text is kept beside each file).

Run from godot/:  python3 tools/bake_voices.py
"""
import hashlib, json, os, subprocess, sys, tempfile, urllib.request, wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(os.path.expanduser("~"), ".cache", "piper-voices")
HF = "https://huggingface.co/rhasspy/piper-voices/resolve/main"


def voice_path(name):
    lang, region_name, quality = name.split("-")[0], name.split("-")[1], name.split("-")[-1]
    family = lang.split("_")[0]
    os.makedirs(CACHE, exist_ok=True)
    model = os.path.join(CACHE, name + ".onnx")
    for suffix in (".onnx", ".onnx.json"):
        target = os.path.join(CACHE, name + suffix)
        if not os.path.exists(target):
            url = f"{HF}/{family}/{lang}/{region_name}/{quality}/{name}{suffix}"
            print("downloading", url)
            urllib.request.urlretrieve(url, target)
    return model


def main():
    from piper import PiperVoice, SynthesisConfig
    with open(os.path.join(ROOT, "assets/story/dialogue.json")) as fh:
        story = json.load(fh)
    out_dir = os.path.join(ROOT, "assets/voice")
    os.makedirs(out_dir, exist_ok=True)
    voices = {}
    made = skipped = 0
    for line_id, line in story["lines"].items():
        speaker = story["speakers"][line["speaker"]]
        key = hashlib.sha1((speaker["voice"] + str(speaker.get("length_scale", 1.0)) + line["text"]).encode()).hexdigest()
        target = os.path.join(out_dir, line_id + ".ogg")
        stamp = target + ".sha1"
        if os.path.exists(target) and os.path.exists(stamp) and open(stamp).read() == key:
            skipped += 1
            continue
        if speaker["voice"] not in voices:
            voices[speaker["voice"]] = PiperVoice.load(voice_path(speaker["voice"]))
        voice = voices[speaker["voice"]]
        config = SynthesisConfig(length_scale=speaker.get("length_scale", 1.0), noise_scale=0.667, noise_w_scale=0.8)
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            wav_path = tmp.name
        with wave.open(wav_path, "wb") as w:
            voice.synthesize_wav(line["text"], w, syn_config=config)
        # A touch of room and warmth so the voices sit in the world rather
        # than on top of it; mono Vorbis keeps each line small.
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path,
                        "-af", "highpass=f=70,aecho=0.8:0.5:28:0.12,loudnorm=I=-18:TP=-2",
                        "-ac", "1", "-ar", "22050", "-c:a", "libvorbis", "-q:a", "4", target], check=True)
        os.remove(wav_path)
        with open(stamp, "w") as fh:
            fh.write(key)
        made += 1
        print("voiced", line_id)
    print(f"{made} lines voiced, {skipped} unchanged")


if __name__ == "__main__":
    main()
