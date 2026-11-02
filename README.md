# Open Code apps

Two small, offline-first Android apps in one Gradle project. Both are native
Kotlin with Jetpack Compose. No accounts, no analytics, no network permission.

| App | Module | What it is |
| --- | --- | --- |
| **Wingman** | `:app` | A private notebook for keeping Discord friendships organised. |
| **Halo** | `:camera` | A native camera with on-device AI enhance, editing and filters. |

---

## Wingman

An offline-first wingman for keeping your Discord friendships organised. Native
Kotlin, Jetpack Compose and Room. No account, no network, no data leaves the phone.

### What it does

- **Friend notebook** — name, Discord handle, vibe, interests, communication style and private notes
- **Consent tracking** — Not started / Agreed / Active / Paused, shown on every card and inside each chat
- **Two-sided chat log** — record what you said *and* what they said, per friend
- **Wingman profile** — a summary, vibe, interests, confidence score and suggested opener generated on-device from the notes and chat history you saved
- **Search, edit, undo delete** — including full restore of a friend's chat history and profile
- **Themes** — Auto / Light / Dark, remembered across launches

---

## Halo (the camera)

A real camera app built on CameraX, with a deterministic on-device enhancement
pipeline. Aimed at the Redmi Note 9 Pro (Android 12) and tuned to look like a
flagship camera rather than a web wrapper.

### Capture

- CameraX image capture at maximum quality, auto focus + tap to focus
- Front / back lens switch
- Flash off / on / auto
- 3 s and 10 s self-timer with a big countdown
- Rule-of-thirds grid
- Pinch to zoom with a zoom readout
- Shutter flash animation

### Edit (all on device, after capture)

- **Filters** — Original, Lark, Juno, Noir, Sunset, Dream, Vivid (starter set)
- **Adjust** — exposure, contrast, saturation, warmth, sharpen
- **AI** — Auto Enhance, Night, HDR, Retouch (edge-aware skin smoothing), Portrait (radial edge blur)
- Live preview, then a full-resolution save to the private library
- Share to any app through a `FileProvider` URI
- Delete, reset, and a library grid with an `AI` badge on edited copies

The AI passes are plain Kotlin pixel maths (`data/ImagePipeline.kt`): box-blur
based local contrast, gamma shadow lift, unsharp masking and an edge-aware
smoothing mask. Auto Enhance reads the photo histogram and picks exposure,
contrast, saturation and warmth (`data/AutoEnhance.kt`). The maths in
`ColorOps` and `AutoEnhance` is covered by JVM unit tests.

### Privacy

Photos live in app-private storage (`files/photos/`). Nothing is uploaded, and
the app declares only the `CAMERA` permission — no storage, no internet.

### Not in this build yet

- Video (4K) recording
- ML subject segmentation for a true portrait bokeh (Portrait is currently an
  honest radial blur, labelled as such)
- Cloud AI (by design, never)

See `docs/superpowers/specs/2026-11-02-ai-camera-design.md` for the design.

---

## Install

Latest debug builds are attached to releases:

```
https://github.com/Max1081018/open_code/releases/latest
```

Direct links for a given tag:

```
https://github.com/Max1081018/open_code/releases/download/v1.4/app-debug.apk
https://github.com/Max1081018/open_code/releases/download/v1.4/halo-debug.apk
```

Debug builds are signed with the debug keystore, so they install directly.

## Build

CI builds and tests both modules on every push to `main`
(`.github/workflows/build-apk.yml`). Pushing a `v*` tag attaches both APKs to a
GitHub release.

```sh
git tag v1.4
git push origin v1.4
```

Locally, with a JDK 17 and Android SDK installed:

```sh
gradle testDebugUnitTest
gradle assembleDebug
```

## Stack

- Kotlin 1.9.24, AGP 8.5.2, Gradle 8.7, JDK 17
- Jetpack Compose (BOM 2024.06.00), Material 3
- Room 2.6.1 with KSP (`:app`)
- CameraX 1.3.4 with ExifInterface (`:camera`)
- minSdk 24, targetSdk 34
