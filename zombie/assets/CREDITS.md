# Assets and licences

Everything shipped in `zombie/assets` and where it came from. Anything whose
licence is not a clear public-domain style grant is flagged so it can be
swapped out before the game is published.

| Asset | Used for | Source | Licence |
|---|---|---|---|
| `chars/AtlasZombieLite_Walker.fbx` | the zombie, and the player's own arms | Atlas Zombie Lite v1.0 | **Marketplace standard licence** — the pack ships no custom licence; check the store terms before release |
| `chars/ual.glb` | source clips for retargeting (not shipped in the build) | Universal Animation Library \[Standard\], Quaternius | CC0 1.0 |
| `chars/zombie_anims.res` | the retargeted clips the game actually plays | baked here from the two above | follows its sources |
| `nature/*.fbx` | trees, bushes, rocks, grass | Ultimate Nature Pack, Quaternius | CC0 1.0 |
| `props/*.glb` | crates, barrels, chests, camps | Kenney Survival Kit | CC0 1.0 |
| `loot/*.fbx` | guns, tools, food, medical | Survival Pack (Sept 2020), Quaternius | CC0 1.0 |
| `models/guns/pistol_1911.*` | the starting pistol | Free Guns Pack 1.2 | pack ships no licence file — **verify before release** |
| `shaders/sky.gdshader` | day/night sky | written here, following the palette and structure of "Day and Night Sky" by Dimension Almios | MIT (see `shaders/day_night_sky_LICENSE.txt`) |
| `shaders/wind.gdshader` | grass and foliage movement | written here | — |

## Notes

`ual.glb` is only needed by `tools/retarget.gd`, which bakes the animation
library offline. It is excluded from exports so the 7 MB of mannequin and its
clips do not ship in the APK.
