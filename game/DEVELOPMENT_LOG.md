# Development Log

Newest first. Each entry records what changed, what it cost, and what was
actually verified as opposed to assumed.

## Quests

Ten chained objectives — dig, mine, gather, smelt, craft a pick, clear
slimes, descend, fight through the dark, smelt gold, kill the Warden — with
rewards paid automatically, since there is no quest-giver to walk back to.

Progress is counted on every quest including locked ones, so a slime killed
before the quest opens is still banked. Gathering objectives read current
stock but never regress, so spending the ore afterwards does not undo the
quest. Tests pin the chain's shape: prerequisites point backwards (ruling out
cycles), exactly one quest opens the chain, every quest traces back to the
start, and one test drives the whole chain to completion.

**Known gap:** quest progress is not written to save files yet. Saving and
reloading resets the log. Fixing this means a save format bump.

## Audio

Ten effects and two ambient beds, synthesised as PCM and wrapped in WAV at
startup. Sample sites are unreachable, and generating keeps the whole bank a
few kilobytes of code.

Quality is enforced by tests: effects begin and end in silence so they cannot
click, nothing clips, ambience carries no DC offset, and the bed's partials
complete whole cycles over the loop so it does not tick at the seam. One test
pins that the dig sound is noise-based rather than periodic — a single sine
reads as a beep, not an impact.

**Verified:** all twelve files decode with Python's stdlib `wave` module at
the declared rate and width, zero clipped samples.
**Not verified:** how they sound. This container has no audio device.

## Visual effects

A fixed-capacity particle pool that never allocates while playing, with
sprites allocated once and reused. Mining throws chips coloured from the
broken tile; blows throw sparks; hits shake the camera. Shake is capped and
uses two incommensurable frequencies so it does not read as a regular wobble.

## Scenery

Trees, pines, cacti, bushes, boulders, cave fungus and crystals, placed
deterministically by a local-maximum rule over a hash, which spaces them out
without tracking state.

**Bug found by looking at a screenshot:** `cave_prop` treated any air tile
over solid ground as a cave floor, so mushrooms sprouted across the open
desert. One of my own tests had encoded the same mistake, so it passed while
the game was wrong. The test now builds a genuinely enclosed tunnel.

## Characters and animation

Nine clips with a state machine; action states play to completion rather than
being cut off by a footstep. Blinking is staggered per character by a hash.

Characters are built from head, torso, arms and legs with a drawn face.

**Bug found by looking:** limbs were translated rather than pivoted, so arms
visibly detached from the shoulder when swinging. They now shear from the
joint. Hands, feet and a neck followed, and legs shorten against the canvas
floor so a collapsing death keeps its feet.

## Standing constraints

| Constraint | Consequence |
|---|---|
| Asset sites unreachable | All art and audio generated in code |
| No GPU | Rendering verified by headless capture on llvmpipe |
| No Android NDK | APK has never been built; pipeline untested past preflight |
| No audio device | Audio verified as data, not by listening |
