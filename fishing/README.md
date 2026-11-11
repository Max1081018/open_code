# Reel Trouble 🎣

A calm, funny, low-poly **first-person fishing game** for mobile, made in
**Godot 4.3**. Start with bare hands on a little island, sell clams for your
first rod, then cast anywhere, tap to reel in your goofy catch, drop it on the
boards and punch it out before it jumps at you.

Everything — the island, animated water, the rod, the fish, and all the sound
effects — is generated in code from simple shapes and sine-wave shaders, so
there are no art or audio files to manage.

![Catch screen](docs/catch.png)

## How to play (Island 1 - Bait Bay)

You play in first person on a little island with a jetty, a weapon shop, a fish
market and a moored motorboat.

1. **Walk** with the left stick, **look** by dragging the right half. Push the
   stick to the edge to break into a run (the threshold is in Settings), and
   tap **JUMP** to hop up the shop steps.
2. You start with **bare hands**. **PICK UP** clams on the beach (they stack in one
   of your **4 slots**) and **SELL** them at the **FISH MARKET**.
3. Buy a **Fishing Rod** at **BAIT & BLADE** (look at it: it outlines white, press **BUY**).
   Tap a slot along the bottom to hold what's in it; tap it again for bare hands.
4. With the rod, anywhere there's water: **hold CAST** to charge, let go. Wait —
   on **HOOK!** tap it, then tap **REEL** a few times (rarer fish take more taps;
   stop and it swims off).
5. The catch hangs off your rod while you walk. **DROP** it (or put the rod away),
   then **PUNCH** it — or **HIT** it with a weapon — until it's knocked out. Be quick:
   live fish flop about and leap at you.
6. **GRAB** it: it goes into a slot (each slot shows a little 3D picture of what's in it), so you can switch to the rod and back. Hold it
   at the market and **SELL** (or drop it on the counter).
7. Buy the **Boat Key** and the **Sea Chart** (both on the little table in the shop):
   with both, the boat is yours to **SAIL**. Buy the **Boss Reel** too, catch **the
   Baby Kraken** from the deck, beat it, sail home and sell it. The buyer hands you
   a map: **Island 2 unlocks**.

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

You see your own arms (rigged and animated): relaxed hands while you walk,
fists up and jabbing left-right when you punch, a reach to pick things up, a
push to drop, throw or hand over. Whatever you hold is really in your grip: the
rod sits in your fist (the wrist aims it, pulls it back to charge, flicks the
cast and jerks the hook), a knife is held blade-up and slashes, a clam sits in
your fist, and a fish is held out by its tail. Only the boss shows a health
bar; ordinary fish just fight until they're knocked out.

Settings let you change look sensitivity, HUD size and opacity, fixed or
floating joystick, graphics (Low / Medium / High / Ultra), resolution (Auto, or a
fixed 50-100% of the screen), shadows, weather,
your hands and body, an FPS counter and more. Tap **JUMP** to hop; you also
walk straight up steps and kerbs.

The weather changes every few minutes: clear, cloudy, breezy, foggy, a
drizzle, and now and then proper rain; the wind moves the grass and palms.

## Performance

Built for phones on the GL Compatibility renderer:

- multi-part models are batched into one mesh per material at load, so the
  island view is ~270 draw calls instead of ~1700;
- the 3D world is drawn at a lower resolution than the screen and scaled up
  behind a full-resolution HUD (Low ~480 rows, Medium ~620, High ~800, Ultra
  native with edge smoothing), capped at 60 fps;
- the HUD only redraws when something on it changes;
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
run's Artifacts. Trigger it from the repo's **Actions** tab → *Build Reel
Trouble APK* → **Run workflow**.

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
| `game.gd` | The whole game: world, inventory, free-roam rod fishing, live fish and punching, clams, shops, boat and boss |
| `touch_controls.gd` | The on-screen controls: joystick, RUN, action/secondary buttons (with cast and reel rings), the 4-slot hotbar, look-at info, catch card, coins |
| `hud.gd` | Old fixed-camera fishing HUD (no longer shown) |
| `status_ui.gd` | Health and breath bars, hit flash, underwater tint, death screen |
| `ui_draw.gd` / `ui_theme.gd` | Shared HUD drawing kit (round buttons, pills, bars, vector icons) and colours |
| `fp_arms.gd` | First-person arms: the rigged PSX arms, clip blending, wrist aim, items held in the fist |
| `world_fx.gd` | Splashes and ripples, seagulls, fish shadows |
| `assets/grass.gdshader` | Wind-swayed grass tufts and wildflowers (MultiMesh) |
| `water.gdshader` | Animated low-poly water (its wave formula is mirrored in `game.gd` so the bobber floats correctly) |
| `sfx.gd` | Procedurally generated sound effects |
| `tools/play.sh` | Headless play-test + screenshot harness |

## Credits

- First-person arms: "PSX First Person Arms" (free game assets pack), rigged
  and animated; the wrist is re-aimed in code so the fist grips the rod.
- 3D models from Kenney (Nature, Pirate, Watercraft kits) and KayKit
  (Adventurers, Fantasy Weapons Bits), CC0.
- Stylized water shader: see `assets/water/LICENSE.txt`.
