# Ethereal Tales: rebrand and performance engineering report

Download (latest build, Android arm64, ~249 MB):
**https://github.com/Max1081018/open_code/releases/download/ethereal-tales-build-7/EtherealTales.apk**
It installs over the older Lanternbound builds (same package id and signing key).

Everything below was measured in this cloud container (no phone). Numbers
that depend on a phone's GPU are not claimed. **No frame rate on a phone has
been measured; 60 FPS is not claimed.**

## Changes implemented

### Rebrand (Lanternbound -> Ethereal Tales)
- Project name, Android app label, title logo (re-rendered in the game's
  Cinzel), splash, app icon, menus, CI release names (`EtherealTales.apk`,
  "Ethereal Tales build N"). Verified inside the built APK: label
  "Ethereal Tales", versionName 0.5.N, adaptive + legacy + monochrome launcher
  icons, splash.
- Icon pipeline `tools/make_brand.py` (one command from the supplied art):
  full-bleed master, 192 launcher, adaptive foreground (art inside the
  launcher safe zone so the title survives circle masks) and background
  (blurred bleed), a 96 px small version (her face; the title is unreadable
  at 48 px), 1920x1080 splash. Purple stays the accent; islands keep their
  own palettes.
- Kept on purpose: package id `com.lanternbound.game` (changing it would
  install a second app and lose saves), internal file names, the legacy 2D
  save path. Desktop saves migrate from the old folder once
  (`Settings._migrate_user_dir`); Android saves are unaffected.

### Main menu
- The painting and its 2D life render once into a fixed 1920x1080 layer
  (1280x720 on Low) and are scaled to the screen, instead of running the
  full-screen shader at the phone's native resolution (often 3200x1440).
- The vista shader samples a small noise texture instead of sine hashes and
  runs each effect only inside its part of the painting.
- The 3D view (1920x1080, MSAA 4x, glow) only renders on the character
  screen; the title's lantern wisp is 2D. MSAA 2x on phones.

### Missing rendering
- Character and scenery LOD chains were collapsing small parts (straps,
  eyes, trims) to slivers that vanished at mid distance. Chains are now
  trimmed (`LodUtil`): characters to 5% over four levels, scenery 6%, never
  a level under 120 triangles, no LODs at all on surfaces under 400.
- Every character gets a cull margin so animated limbs and lunges never
  blink out at the screen edge.

### Loading and shader stutter
- Controlled warm-up (`WarmUp`) behind a real progress veil when the world
  opens: bakes every scenery kind (up to ~150 ms each on a phone, previously
  paid mid-walk), loads and draws the starting island's foes and guardian,
  fires each spell effect once, so the GPU driver compiles those shaders
  now. Only this island's foes, not everything.
- The world builds only the nearest 3x3 chunks synchronously; the rest
  stream on worker threads behind the veil (previously the whole radius
  froze `_ready`).
- The loading screen's progress was already real (threaded loads); kept.
- Tried and reverted: caching character scenes for the session (shared
  materials tripped the renderer); documented in code.

### World, characters, AI, presets
- Presets Low / Medium / High / Ultra now also set: shadow reach (off / 50 /
  90 / 140 m), cascades, shadow map size (1024 / 1024 / 2048 / 4096),
  softness, LOD aggressiveness, draw distance of scenery, flora and props
  (x0.65 / 0.85 / 1.0 / 1.3). Low caps at a steady 30 FPS.
- Adaptive resolution (on by default, settings toggle): the 3D view steps
  down to as low as 50% while frames run long, back up with headroom; UI
  stays sharp.
- Far, unaware foes think at a quarter rate (still moving every tick, so
  they never drift or freeze); far characters and NPCs animate at a third of
  the rate (`AnimLod`). Fighting, searching or returning foes and guardians
  always run in full.
- Enemy hit flash only while it shows (an extra transparent pass per foe
  mesh is gone) and faded material copies handed back before a foe is freed
  (the "material is null" renderer errors are gone).
- Physics reviewed: terrain uses heightmaps, buildings boxes, props simple
  shapes; sky isles use trimesh (needed for their shape, few of them).
  Collision audit earlier this session: the Root Stair gates, Sun Gate and
  shrine were made solid.

### Android and CI
- Each CI build has its own version code. The signing key can come from a
  repository secret (`ANDROID_KEYSTORE_B64`); today it lives only in the
  Actions cache, which is evicted after 7 unused days.
- Renderer stays GL Compatibility (OpenGL ES 3): the widest device support
  and no Vulkan pipeline-compile stalls on low-end phones.
- Textures VRAM-compressed (ETC2) on Android (earlier pass, verified in APK).

## Performance before and after

Harness: `tools/bench.sh OUT.jsonl FRAMES [gpu|cpu] [scenarios]`.
GPU pass = software OpenGL at 640x360 (draw calls, primitives, memory, load
and hitch are meaningful; frame times are the software renderer's).

| Scene | Frame (sw GL) | Draw calls | Primitives | Video mem | Worst settle hitch | Load (_ready) |
|---|---|---|---|---|---|---|
| Menu | 60.6 -> **31.5 ms** | 242 -> 243 | 2.7k -> 2.7k | 106 -> **48 MB** | 476 -> 204 ms | - |
| Town | 1138 -> 1041 ms | 966 -> 991 | 1.69 M -> 1.74 M | 174 -> 178 MB | 7485 -> **1920 ms** | 16.1 -> **6.1 s** |
| Jungle | 3696 -> **2074 ms** | 1025 -> 1025 | 2.20 M -> 2.22 M | 173 -> 212 MB | 4821 -> 2256 ms | 7.4 -> 6.4 s |
| Sky | 597 -> 703 ms | 595 -> 617 | 0.73 M -> 0.86 M | 208 -> 217 MB | 1704 -> 1336 ms | 6.6 -> 6.0 s |
| Coast (after LOD rebalance) | 1010 -> 734 ms | 879 -> **858** | 0.94 M -> **0.93 M** | 180 -> 220 MB | 2414 -> **850 ms** | 7.1 -> 6.7 s |
| Combat (4 foes) | 1388 -> 1098 ms | 1361 -> 1360 | 2.10 M -> 2.10 M | 174 -> 178 MB | 3439 -> 1202 ms | 6.7 -> 6.2 s |
| Guardian fight | 3331 -> 2381 ms | 1095 -> 1025 | 2.42 M -> 2.22 M | 207 -> 212 MB | 3761 -> 3639 ms | 7.4 -> 7.0 s |

(Town to guardian rows except coast were measured before the final LOD
rebalance, which lowered primitives further on the coast; the other rows
were not re-run.)

- The warm-up itself takes 30 to 70 s **on this software renderer** (each
  frame costs ~1-2 s here); on a phone it is a few seconds. It is load time
  behind the veil, not play.
- Video memory rose 5 to 40 MB in the world: the warm-up keeps every scenery
  kind's meshes resident so they never bake mid-walk. A deliberate trade.
- CPU pass (no renderer): this harness's frame time is pinned at the
  engine's pacing floor (6.9 ms), and script/physics time varied in both
  directions between runs (random spawns), so **no CPU-side improvement is
  claimed** from it. The AI/animation throttles reduce work in principle;
  they need a phone profile to quantify.

## Tests
- Full suite: **148 passed, 0 failed** (headless).
- Remaining engine noise in the test log: two "material is null" lines from
  `test_discovery` freeing the old 2D level immediately (test-only path).
- Visual checks (screenshots): title screen at 20:9 (fills, animated,
  new logo), town and coast views, distant characters intact.
- Not done: a physical-device run, extended-play soak test on a phone,
  repeated scene-transition memory test on a phone.

## Remaining bottlenecks
1. World load on the main thread: `world` ~3.4 s, `town` ~1.5-1.8 s,
   `secrets_bosses` ~0.9-1.2 s (this CPU). Next to move onto threads or
   spread across frames behind the veil.
2. Draw calls 850 to 1360 and 0.9 to 2.2 M primitives on High: above a
   comfortable budget for low-end phones (~800 / ~1 M). Low and Medium cut
   shadows, draw distance and grass, but were not measured separately.
3. Grass and the town's MultiMesh batches carry most triangles.

## Android-specific limitations
- Not run on a real device in this session: frame rate, thermals, memory
  and touch latency on hardware are unmeasured.
- APK ~249 MB (Godot engine ~88 MB, ETC2 textures ~130 MB).
- Signing key in the Actions cache only (see above); its password is in the
  workflow file. Make your own key for a store release.

## Missing credentials / external requirements
- Google sign-in: see `GOOGLE_SIGN_IN.md` (OAuth consent screen, an Android
  OAuth client for `com.lanternbound.game` with SHA-1
  `6b92daf8d77a77fcea723ad0347a0cd347ef7af5`, a Web client ID, optionally a
  backend). A maintained plugin candidate is identified, not installed.
- Tools: no relevant skills found; gdUnit4 noted (not needed, the project's
  runner covers 148 tests); no new dependencies installed.

## Exact next task
Install build 7 on the phone, enable **Show FPS**, and report the FPS on
the title screen, in the town and in the jungle on Medium and High (and
whether adaptive resolution kicks in). With those numbers: move the
`world` and `town` build stages behind the veil across frames, then cut
draw calls on High toward ~800 (merge town prop batches, trim grass on
Medium).
