# Deadzone

A first-person low-poly zombie survival game for Android, built in Godot 4.3
(GL Compatibility).

This is the basics, working end to end: ground, movement, zombies that hunt
you, shooting, searching containers, dying and coming back. Buildings, better
art and the rest of the survival systems come on top of it.

## What works now

- **Open ground.** Terrain is generated from noise in 48 m chunks that load and
  unload around you, with forest, rocks and undergrowth scattered into them.
- **Zombies.** The Zombie Lite model on an 18-bone rig, driven by an
  AnimationTree state machine: a blend space for idle/walk/run/sprint, and
  states for attacking, biting, flinching, staggering, crawling, getting up and
  dying. They see you in a cone, hear gunfire, steer round trees, shuffle up
  kerbs, and go down differently depending on where you hit them - a leg can
  put one on its belly to crawl after you. Each one rolls its own build, skin,
  shirt and trousers.
- **Your own hands.** The arms in front of you are the same model with its head
  and legs folded away, playing clips retargeted onto the same rig. A weapon is
  mounted on the hand's bone and squared up to the view automatically.
- **Fighting.** Pistol with magazines, reloading and spread; melee; head, body
  and leg hits; a crosshair that tells you what you are looking at.
- **Survival.** Health, stamina, food and water, containers to search, items
  that stack in a six-slot hotbar, death and respawn.
- **Day and night.** A real sky shader with sun, moon, stars and drifting
  cloud; the light, the fog and how far zombies can see all follow the clock.

## Testing

Everything is checked headlessly - there is no hand-made scene to open.

    godot --headless --path zombie --script res://tools/_chk.gd      # parse check
    godot --headless --path zombie -- --autotest --screen=basics --frames=3000

`--screen=basics` walks the whole loop a player goes through (find a container,
search it, kill a zombie, take a hit, die, respawn) and prints what happened at
each step, so a run either reports the loop working or names the step that
stopped. Other screens: `play`, `zombies`, `tour`, `night`.

For pictures, run it windowed with `--shot=<file>`:

    xvfb-run -a godot --path zombie --rendering-driver opengl3 --resolution 1280x720 \
        -- --autotest --screen=zombies --frames=130 --shot=/tmp/shot.png

## Tools

- `tools/retarget.gd` bakes the animation library: clips from the Quaternius
  Universal Animation Library (65-bone Unreal rig) are retargeted onto the
  zombie's 18-bone rig and saved as `assets/chars/zombie_anims.res`. Run it
  again after adding clips to `WANT`.
- `tools/anim_preview.gd` renders frames of a baked clip so a retarget can be
  checked by eye.

Assets and licences: `assets/CREDITS.md`.
