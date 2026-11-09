# Lazy Lake 🎣

A calm, funny, low-poly **first-person fishing game** for mobile, made in
**Godot 4.3**. Cast off a little island, wait for a bite, tap to hook, then reel
your goofy catch in while keeping the line from snapping.

Everything — the island, animated water, the rod, the fish, and all the sound
effects — is generated in code from simple shapes and sine-wave shaders, so
there are no art or audio files to manage.

![Catch screen](docs/catch.png)

## How to play (Island 1 - Bait Bay)

You play in first person on a little island with a jetty, a weapon shop, a fish
market and a moored motorboat.

1. **Walk** with the left stick, **look** by dragging the right half, tap **RUN** to sprint.
2. At the end of the jetty press **FISH**. Hold to charge, release to cast.
   On **TAP!** tap fast to hook, then hold to reel while keeping the tension out of the red.
3. The catch lands on the deck: **tap to whack it**. Your equipped weapon takes fewer whacks.
4. It goes into your hands. Carry up to 5, then walk to the **FISH MARKET** and **SELL**.
5. Spend coins at **BAIT & BLADE**: look at an item (it outlines white) and press **BUY**.
   Beginner gear: Gutting Knife, Fisherman's Dirk, Scaling Grips, Bait Hatchet.
6. Buy the **Boss Reel**, then walk to the boat and **SAIL** out to the boss waters.
7. Land **the Baby Kraken**, sail home and sell it. The buyer hands you a map:
   **Island 2 unlocks** (coming soon).

Real catches include Minnow, Perch, Sunfish, Trout, Bass, Carp, Catfish, Pike,
a rare Golden Koi, and junk like an old boot, a message in a bottle and a sunken chest.

Settings let you change look sensitivity, HUD size and opacity, fixed or
floating joystick, graphics preset (Low/Medium/High), shadows and more.

## Run it on a computer

1. Install [Godot 4.3](https://godotengine.org/download) (the normal version, not .NET).
2. Open Godot → **Import** → pick this `fishing/` folder's `project.godot`.
3. Press **Play** (▶). Click-and-hold acts as the touch controls.

## Build it for your phone (Android)

**Easiest (in the Godot editor):**
1. In Godot: **Editor → Manage Export Templates → Download and Install**.
2. **Project → Export → Add… → Android**, then **Export Project** to get an `.apk`.
3. Copy the `.apk` to your phone and open it (allow "install from this source").

Godot's docs walk through the one-time Android SDK setup:
<https://docs.godotengine.org/en/4.3/tutorials/export/exporting_for_android.html>

**Automated (GitHub Actions):** the workflow at
`.github/workflows/fishing-apk.yml` builds an APK you can download from the
run's Artifacts. Trigger it from the repo's **Actions** tab → *Build Lazy Lake
APK* → **Run workflow**.

## Play-test it headlessly (no screen)

`tools/play.sh` imports the project and runs it under a virtual display with
software OpenGL. The game's `--autotest` mode plays real casts with synthetic
touch input, saves a screenshot, and prints the result — this is how the game
is checked on a server with no GPU.

```bash
GODOT=/path/to/Godot_v4.3-stable_linux.x86_64 fishing/tools/play.sh 1600 shot.png
```

## Files

| File | What it is |
| --- | --- |
| `game.gd` | The whole game: world, rod, cast/bite/reel loop, fish, state machine |
| `hud.gd` | Touch controls, meters, messages |
| `water.gdshader` | Animated low-poly water (its wave formula is mirrored in `game.gd` so the bobber floats correctly) |
| `sfx.gd` | Procedurally generated sound effects |
| `tools/play.sh` | Headless play-test + screenshot harness |
