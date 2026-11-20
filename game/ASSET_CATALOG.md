# Asset catalogue

Everything the game ships, where it came from, and what may be done with it.

Deepdelve is mostly **generated**: tiles, characters, props, icons, the sky
and the ambient music are all produced in code at startup, so there is no
texture or sprite file anywhere in the repository. The exception is sound
effects, which are licensed recordings. Synthesis makes a passable click;
it does not make a pickaxe biting into rock sound like anything other than
a synthesiser.

## Sound effects — licensed recordings

Ten clips from [Soundza](https://soundza.com), under the
[Soundza Standard License](https://soundza.com/license): free for commercial
and personal use, no attribution required. The licence does forbid
redistributing the files **on their own** or as a sample pack — shipping
them inside a game is exactly the intended use, extracting them back out
and republishing them is not.

They live in `assets/audio/sfx/` and are compiled into the binary with
`include_bytes!` (see `core/src/audio.rs`), so there is no asset directory
to ship beside the APK and no load-failure path to handle on a phone.

| Effect | Clip | Source |
|---|---|---|
| `Dig` | Stones 4 | https://soundza.com/sound/stones-4 |
| `Break` | Stones 2 | https://soundza.com/sound/stones-2-1 |
| `Hit` | Blade 3 | https://soundza.com/sound/blade-3 |
| `Hurt` | Male Pain Grunts | https://soundza.com/sound/male-pain-grunts |
| `Jump` | Footstep on Dirt and Gravel | https://soundza.com/sound/footstep-on-dirt-and-gravel |
| `Land` | Dirt Gravel Footstep Short | https://soundza.com/sound/dirt-gravel-footstep-short |
| `Pickup` | Gem 3 | https://soundza.com/sound/gem-3 |
| `Craft` | Metal Hammer Hit 2 | https://soundza.com/sound/metal-hammer-hit-2 |
| `Roar` | Creature Roar 2 | https://soundza.com/sound/creature-roar-2 |
| `Click` | Lock 1 | https://soundza.com/sound/lock-1 |

Seven of the ten come from one pack (*Fantasy RPG SFX*) deliberately. A
sound bank assembled from ten unrelated recordings has the audio equivalent
of mismatched art: different rooms, different microphones, different noise
floors. Jump and Land are two different gravel footsteps — a push-off and a
landing — rather than a chiptune blip, for the same reason.

### How they were prepared

`tools/prepare_sfx.py` converts the downloads into one format. Raw, they are
24-bit stereo at 44.1–48 kHz, totalling 1.28 MB; prepared they are **mono,
16-bit, 22 050 Hz, 209 kB** — about six times smaller, with no audible
difference through a handset speaker.

The script also does three things that matter more than the format:

* **Trims the head twice.** A silence floor alone leaves a quiet creep-in
  intact. Two clips crept in for over a tenth of a second before their real
  transient, which reads as input lag rather than as a slow sound. A second
  pass cuts to 25% of the clip's own peak, keeping 15 ms of run-up so the
  natural attack survives. Every effect now fires within 14 ms.
* **Level-matches** every clip to the same peak, so nothing is startling
  next to the rest.
* **Fades 4 ms at each end**, so a non-zero first or last sample cannot
  click.

`core/src/audio.rs` has tests pinning all of this: format, non-silence,
onset latency, duration, level match, and a total size budget.

## Ambient music — generated

Still synthesised, and should stay that way. The beds are twenty-second
loops; as 22 kHz samples they would cost roughly 880 kB *each*, more than
every sound effect put together. A generated loop is also seamless by
construction, which a trimmed recording is not.

## Everything visual — generated

No image files. Tiles (48×48, six variants each), characters, props, item
icons, the parallax sky and the particle sprites are all drawn in code.
`.claude/skills/pixel-art-direction/SKILL.md` is the art bible that keeps
them one style.

This began as a constraint — the asset sites are unreachable from the build
environment — but it earns its place: one generator means guaranteed
cohesion, six free variants of every material instead of visible tiling, and
an APK that carries no textures at all.

### Generated art that was tried and rejected

Image generation via the 3D AI Studio connector produces good foliage, which
is where procedural art is weakest. It is **not** in use: the connector's
asset CDN is blocked by the build environment's network policy, so only a
6 kB lossy preview can be retrieved, and lossy compression is fatal to pixel
art — it bleeds colour across exactly the hard edges that define it.

If that host is ever reachable, trees and a parallax backdrop are the two
places where generated art would beat the generators, because neither needs
to tile seamlessly nor animate across frames.
