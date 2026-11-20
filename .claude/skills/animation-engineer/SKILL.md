---
name: animation-engineer
description: How animation works in Deepdelve. Load before adding or changing any animated sprite, animation state, or frame timing.
---

# Animation in Deepdelve

## Architecture

Animation is **data in core, playback in core, drawing in the frontend**.

```
core/src/anim.rs     clip definitions, state machine, frame selection
core/src/sprite.rs   procedural generation of each frame
app                  uploads frames as GPU textures, swaps per frame index
```

The frontend must never decide *which* frame to show. It asks core and draws
the answer. This keeps animation testable without a GPU, which matters because
the build environment has none.

## Clips

A clip is a frame count, a frame duration, and whether it loops.

| State | Frames | ms/frame | Loops | Notes |
|---|---|---|---|---|
| Idle | 4 | 180 | yes | Breathing; subtle vertical bob, blink |
| Walk | 6 | 110 | yes | Full stride cycle |
| Run | 6 | 70 | yes | Same poses, faster, more lean |
| Jump | 2 | — | no | Hold frame 1 while rising |
| Fall | 2 | — | no | Hold frame 1 while descending |
| Mine | 4 | 90 | yes | Arm arcs; impact on frame 2 |
| Attack | 4 | 70 | no | Telegraph, strike, follow-through, recover |
| Hurt | 2 | 120 | no | Recoil, flash |
| Death | 5 | 140 | no | Hold the final frame |

Timings are tuned for readability at 60fps, not realism. A walk cycle slower
than ~90ms/frame reads as wading; faster than ~60ms reads as skittering.

## State selection

State is derived from physics, never set directly by input:

```
not on_ground && vy < 0   → Jump
not on_ground && vy >= 0  → Fall
|vx| > run threshold      → Run
|vx| > 0.1                → Walk
otherwise                 → Idle
```

Action states (Mine, Attack, Hurt, Death) **override** locomotion and play to
completion before locomotion resumes. Death overrides everything and never
exits.

## Faces

Eyes and mouth are driven separately from the body clip, so a character can
blink while walking and grimace while hurt.

- **Blinking** is time-driven, not frame-driven: closed for ~90ms every
  2.5–4s, offset per character by a hash so a crowd does not blink in unison.
  Synchronised blinking is deeply uncanny; this is worth the extra code.
- **Mouth** maps to state: neutral line when idle, open when attacking or
  falling, tight when hurt.

## Rules

- Generate frames **once** at startup and cache them. Regenerating a sprite
  per frame will destroy mobile performance.
- Frame count × variants × characters is a memory budget. Keep total
  generated sprite memory under ~16 MB.
- Every clip must have a test asserting frame count, total duration, and that
  a non-looping clip clamps rather than wrapping.
- Sprite origin is **bottom-centre**, matching the physics body's feet. An
  origin mismatch shows up as a character sinking into the floor.
