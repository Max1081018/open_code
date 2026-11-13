# RustMod Forge

An Android app that inspects Minecraft Java mods (Forge, NeoForge, Fabric, Quilt, legacy Forge, data
packs) and rebuilds what it can for **Horizon**, the Rust Minecraft engine, as files its launchers
import. It never runs the mod's Java code, and it never claims more than it checked.

- What Horizon can load, and why the app does what it does: [research.md](research.md)
- Module `:forge` (Android app, Kotlin + Jetpack Compose) on module `forge-core` (the engine, pure JVM)

## Install

Download `RustModForge.apk` from the repository's **Build APK** workflow artifacts (or a release)
and open it on the phone. It needs Android 8.0 (API 26) or newer. No account, no analytics; the
network is used only for an AI provider or build server you configure.

## Using it

1. **Import Java mod** (or **Import several** for a mod and its dependencies, or "Open with" from a
   file manager). The jar is copied into the app; the original is never modified.
2. The **Mod analyzer** shows the loader, Minecraft version, dependencies, entities (attributes, AI
   goals, recognised behaviours with the methods that showed them), registrations, assets, classes
   (with a bytecode viewer) and every unsupported feature.
3. Pick a **quality** and **targets**, then **Start conversion**. It runs in the background with a
   notification; cancel stops between steps and **Resume** continues (analyses are reused).
4. The **Result** lists every feature as implemented / partial / unsupported with how and why,
   every build and validation step (passed / failed / skipped / **not run**), and the files.
5. **Export**: *To Horizon Mods* writes the `.hmod` straight into Horizon Android's Mods folder
   (choose it once in Settings › Target launcher: Files › Horizon Android › Mods), or *Save as…* /
   *Share*. Then in Horizon Android: Mods › Installed › switch it on, start the game.

## Quality levels (each does real, different work)

| | Fast | Advanced | Maximum fidelity |
|---|---|---|---|
| Assets, data (upgraded to 26.3), declarations, dependency report, validation | ✓ | ✓ | ✓ |
| Behaviour reconstruction from bytecode, model rig + function AI (Android), Rust trait mod (desktop), compile via build backend | | ✓ | ✓ |
| Animation sampled every tick (instead of every 2) | | | ✓ |
| AI-assisted classification of custom Java goals the rules do not recognise; AI repair of compile errors (scoped region, bounded attempts) | | | ✓ (a provider is set by default) |

**AI**: Settings ships presets. The default (Pollinations) needs **no key**; Gemini, Groq and
OpenRouter free tiers need a free key of your own. AI is used for two narrow jobs — classifying a
custom Java goal the rules do not recognise, and fixing a compile error in a marked region — one
class or one error per request, cached, under a token budget. It cannot make Java run on Horizon,
so it does not turn an unsupported feature into a supported one.

## What each mod becomes

A jar is not one thing: its files belong in different places in Horizon, and putting them in the
wrong one is why a converted mod can look installed and change nothing.

| The jar's files | Where they go | Why |
|---|---|---|
| `assets/<mod>/**`, `data/<mod>/**`, additions to vanilla and `c` tags, atlas sources | **content mod** `.hmod` | A content mod owns its own namespaces. |
| `assets/minecraft/**` (sounds, textures, models, lang, fonts) | **resource pack** `.zip` | A content mod may not replace vanilla's files; Horizon merges a pack's `assets/minecraft/sounds.json` and the rest over vanilla. |
| `data/minecraft/**` beyond tags (recipes, loot tables, advancements) | **data pack** `.zip` | The same, per world: the game loads a world's packs into its item, recipe, loot and advancement tables. |
| Java classes | nothing is copied | Java does not run on Horizon; behaviour is rebuilt from what the bytecode shows (below). |

So a "better sounds" style mod converts to a **resource pack**, not a mod, and no `.hmod` is
written for it — an empty one would be installed and do nothing. The Result screen gives install
steps per file, because the three go to different folders. A `.hmod` may hold nothing but its
manifest, `assets/` and `data/`, so it cannot carry a `pack.png`: the mod's logo goes on the
packs, and a mod installed from a file shows no icon in the Mods list.

## Targets

| Target | Output | Notes |
|---|---|---|
| **Horizon Android** (`dev.horizon.android`, RxLauncher Rust Edition `150a414`) | `<id>-android.hmod`, `<id>-resourcepack.zip`, `<id>-datapack.zip` | Content + data pack functions. No living mob types at this revision, so a creature is a *tagged vanilla mob* driven by functions, drawn by a display-entity rig. `.hnmod` is not supported there. |
| **Desktop Horizon** (upstream `6c4c034`) | `<id>-desktop.hmod` + `<id>.hnmod` (+ the same packs) | Content with living entity types; a Rust trait mod (`register_goals`, `mob_submit`) that the desktop launcher compiles. |

## How a creature is rebuilt (example: a stalker horror mob)

From the bytecode the engine reads the entity's registration and size, `createAttributes` values,
`registerGoals` (vanilla goals with their arguments and the mod's custom goals), and recognises
behaviours by what methods call and compare: *stalks keeping N blocks*, *watches*, *vanishes
within N blocks*, *freezes / vanishes when looked at* (look vector · direction), *night only*,
*effects on players*, *sounds*, *particles*, *jumpscare overlay*, *persistence*. GeckoLib
`.geo.json` geometry and `.animation.json` clips (Molang evaluated) or `createBodyLayer()` models
become the model.

- **Android**: the body is a tagged zombie (invisible, silent, with the mod's attributes via
  `/attribute`, its loot table, an invisible helmet so it does not burn); each bone is an
  `item_display` showing a generated item model; clips are sampled into display transformations
  chosen by movement/attack state; the behaviours become a per-tick state machine (hold/face,
  chase, vanish sequence, view-direction probes, effects, sounds, a title-glyph jumpscare); a spawn
  director spawns it at night behind players; `/function <id>:summon/<name>` places one.
- **Desktop**: `register_goals` installs the vanilla goals and Rust `Goal`s for the recognised
  behaviours; `mob_submit` draws the model with `Host::draw_cube` with compiled animation tables.

## The Man From The Fog

Not bundled and not downloaded: import your own copy of the jar (and its dependencies, such as
GeckoLib, if you want them reported as imported). It is treated like any other mod — there is no
code specific to it. Expect, from the analysis of how such a mod is built: the monster's textures,
GeckoLib model and animations, sounds and its recognised behaviours rebuilt as above; renderer
fog, custom shaders, client-side GUI overlays and mixins reported as partial or unsupported with
the reason. The result screen is the authority for your copy.

## The AI engine (2.0)

The AI is not a chat box: it is an **agent that drives the conversion through the engine's own
tools**, and the engine, not the model, decides whether its work is kept.

**Provider.** OpenRouter (`/api/v1/chat/completions`) with your own free key, entered on the
**AI** screen. The model order is a preference list, checked against OpenRouter's live catalog:
anything it does not list is reported as missing and skipped. A rate-limited model is rested for
its `Retry-After` and the next free one is tried; a 5xx or timeout is retried once then skipped.
When every free model is exhausted the conversion **pauses and keeps its progress** — paid models
stay off unless you turn them on yourself. The default order is the one you asked for
(`recursive/flint-v1.0:free`, `cohere/north-mini-code:free`,
`thinkingmachines/inkling-2-small:free`, `openrouter/free`); **these names were not verifiable
from the build environment**, which cannot reach openrouter.ai, so the app checks them on your
phone and the AI screen shows which exist right now.

**Tools.** The model may only name one operation per reply; the engine executes it:
`list_classes`, `class_detail`, `disassemble` (ASM, never loaded or run), `entity_report`,
`dependencies`, `read_resource`, `search_horizon_api`, `list_generated`, `read_generated`,
`write_rust`, `write_content`, `validate`, `compile`, `remember`, `finish`. Writes are confined
to the mod's own paths; a path outside them is refused.

**Knowledge base.** `tools/build-horizon-api-index.py` extracts the API from a Horizon checkout
into `horizon-api.json`: every hook point with its signature, doc comment and event type, the
`Host` helpers, the goal types with their real constructors, the fields and methods of `Mob`,
`MobWorld`, `Cx` and the rest, the `mod_api` exports and the modding documentation, stamped with
the revision. `search_horizon_api` answers only from this, so the agent cites real APIs; when a
search finds nothing it is told the API does not exist and must report the missing capability.

**The engine has the last word.** After a run the validators run again and, where a build backend
exists, the compiler. If the agent's files raise validator errors or produce Rust that does not
compile, the previous files are **restored** and the report says so. A run can improve the output
or leave it as it was; it cannot ship something broken. Generated Rust that nothing could compile
is reported `unverified` — not passed, not failed.

**Context efficiency.** One class or one method per request, results truncated with an explicit
marker, a rolling conversation window, per-project caching of disassembly, and a persistent
knowledge base (`knowledge.json`) the agent writes findings into, so a resumed conversion does
not re-derive them. Steps and tokens are capped per conversion (AI screen).

### Verification statuses

Every output file records the steps it actually reached — `extracted`, `analyzed`,
`reconstructed`, `generated`, `compiled`, `packaged`, `loaded`, `runtime tested` — and why the
next one was not. `compiled` appears only when a compiler exited zero. `loaded` and
`runtime tested` are never set by RustMod Forge: it cannot load a mod into your game.

## What is verified, and what is not

Verified automatically (forge-core tests, run in CI):

- Analysis of **real compiled bytecode** of fixture mods (Forge + GeckoLib horror mob, Fabric with
  intermediary names, NeoForge Java-model mob, content-only pack, nested jars, mixins/reflection).
- Generated `.hmod` files pass RustMod Forge's validator for each target; in the development
  environment they also passed **Horizon's own `cargo horizon-mod check`** of both the Android
  fork and upstream, and the generated Rust trait mods **type-checked with `cargo check` against
  `horizon-client`** at the pinned revision (0 errors). Set `RMF_HORIZON_MOD_BIN`,
  `RMF_HORIZON_MOD_BIN_UPSTREAM` and `RMF_HORIZON_SRC` to run those checks in the tests.
- Security: zip-slip, absolute paths, duplicate entries, zip bombs and size limits are refused.
- The agent loop, driven by a scripted model with no network: its tools run against the real
  fixture bytecode and the real API index; writes outside the mod are refused; work that raises
  validator errors is rolled back; Rust that the compiler rejects is rolled back even when the
  model claims success; an exhausted free model pauses the run and keeps the files.
- OpenRouter's fallback: a rate-limited preference moves to the next free model, a paid model is
  never called with paid models off, and a model absent from the catalog is reported, not called.
- A sound mod that replaces vanilla sounds produces a resource pack holding those sounds, the
  mod's own sound it refers to, an icon and a `pack.mcmeta` the launcher's own format check
  accepts, plus a data pack whose loot table has been upgraded to 26.3.

**Not verified: OpenRouter itself.** The build environment cannot reach openrouter.ai, so no
live call was made from here: the provider is covered by tests with a fake transport, and the
model names you gave are checked against the catalogue on your phone.

**Not verified: running in the game.** No converted mod has been loaded in Horizon by these
tests; every report says "Runtime test: not run". Display-entity rigs (orientation, handedness,
texture faces), command behaviours and font-glyph overlays in particular need checking on a
device. A phone cannot compile Horizon: native compilation runs only on a build server.

## Build server (for desktop native mods)

`tools/forge-build-server.py` runs `cargo check` of a submitted `.hnmod` inside a Horizon checkout
at the targeted revision (see the script's header). Point Settings › Build at it.

## Architecture

```
forge-core (JVM)                               :forge (Android)
 archive/SafeArchive    limits, traversal       MainActivity, Route stack
 analysis/              metadata, resources,    ForgeViewModel (projects, work flows)
   MetadataReader       loader plugins           work/ForgeWorker (WorkManager, foreground)
   ModAnalyzer          orchestration            data/ Settings (keystore), Imports, Exports
 bytecode/              ASM, never executes      ui/ Home, Analyzer, Conversion, Result,
   ClassScanner         two-pass, bounded            Report, Library, Classes, Settings
   RegistryScanner      DeferredRegister/Registry
   EntityScanner        attributes, goals
   BehaviourScanner     traits with evidence
   JavaModelScanner     createBodyLayer
   Vanilla              Mojang/SRG/intermediary names
 geo/                   Bedrock geo/anim, Molang, pose math
 compat/HorizonCompat   per-target capabilities, hook catalog (434 hooks)
 target/                ContentModGenerator, DataUpgrader (ported from Horizon's carry),
                        RigBuilder, FunctionBackend, NativeModGenerator, OutputTree
 build/                 Packager, Validator, BuildBackend (local cargo, remote, Horizon checker)
 ai/                    providers (OpenAI-compatible, Anthropic), cache, budget, scoped repair
 pipeline/              Project (resume, backups), Quality, ConversionPipeline
 report/                ConversionReport (JSON + Markdown)
```

Extending: a new loader is a `LoaderMetadataPlugin`; a new mapping set is entries in `Vanilla`; a
new behaviour is a `TraitKind`, a rule in `BehaviourScanner` and its mapping in `FunctionBackend`
/ `NativeModGenerator`; a new engine revision updates `HorizonCompat` and `horizon-hooks.json`.

## Licences

Converting a mod does not grant rights to it. Only import mods you may use; outputs contain the
original's assets and are for your own use unless its licence allows more. RustMod Forge does not
bundle or download anyone's mods.
