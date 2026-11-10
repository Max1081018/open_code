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
Each fish has its own rarity, price per kg, bite strength and fight speed; a
better **Reel** makes rarer fish bite more often.

**Watch out:** rarer fish fight back. A landed fish can wind up and leap at you
(whack it during the warning to stop it), and wading too deep runs out your
breath until you drown. Dying drops what you're carrying and costs 10% of your
coins; you wake up on the jetty.

Caught fish are real physics objects: grab them, carry them, throw them, or
drop them on the market counter to sell.

**Fishing feel:** the bobber nibbles before the real bite (tap too early and
you spook the fish), a lightning-fast tap on **HOOK!** is a *Perfect Hook*
that starts the fish closer with a slack line, and landing fish in a row
builds a **streak** (+10% coins per fish, up to +50%) that a snapped line or
a missed bite resets. Watch for fish shadows swimming off the jetty.

**Wanted board:** the fish market always wants one species and pays double
for it; sell one and a new request goes up.

**Journal:** every species you've landed, how many and your best weight. The
first catch of each species pays a +15 coin bonus.

You see your own hands: they swing as you walk, reach for things you look at,
grip the rod and turn the reel crank while you reel, hold your weapon for the
whack, carry fish by the sides, and flinch up in front of your face when a
fish winds up to jump.

Settings let you change look sensitivity, HUD size and opacity, fixed or
floating joystick, graphics preset (Low/Medium/High), shadows, weather, your
hands and body, an FPS counter and more.

## Performance

Built for phones on the GL Compatibility renderer:

- multi-part models are batched into one mesh per material at load, so the
  island view is ~270 draw calls instead of ~1700;
- only large props cast shadows (2 cascades, 48 m); the shop interior only
  draws when you're near it; clouds, seagulls, grass and fish shadows are
  single meshes / MultiMeshes;
- HUDs reuse their style boxes instead of allocating every frame;
- Low preset: no shadows, no MSAA, a third of the grass, shorter view.

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
| `hud.gd` | Fishing HUD: action button, fight meters, catch card, messages |
| `touch_controls.gd` | Walking HUD: joystick, RUN, action/secondary buttons, look info |
| `status_ui.gd` | Health and breath bars, hit flash, underwater tint, death screen |
| `ui_draw.gd` / `ui_theme.gd` | Shared HUD drawing kit (round buttons, pills, bars, vector icons) and colours |
| `fp_hands.gd` / `assets/hand.gdshader` | First-person hands: pose blending, gestures, finger curl |
| `world_fx.gd` | Splashes and ripples, seagulls, fish shadows |
| `assets/grass.gdshader` | Wind-swayed grass tufts and wildflowers (MultiMesh) |
| `water.gdshader` | Animated low-poly water (its wave formula is mirrored in `game.gd` so the bobber floats correctly) |
| `sfx.gd` | Procedurally generated sound effects |
| `tools/play.sh` | Headless play-test + screenshot harness |

## Credits

- Hand model: ["Hand (low poly)"](https://sketchfab.com/3d-models/hand-low-poly-d6c802a74a174c8c805deb20186d1877)
  by scribbletoad, licensed [CC-BY-4.0](http://creativecommons.org/licenses/by/4.0/)
  (re-posed and mirrored in code).
- 3D models from Kenney (Nature, Pirate, Watercraft kits) and KayKit
  (Adventurers, Fantasy Weapons Bits), CC0.
- Stylized water shader: see `assets/water/LICENSE.txt`.
