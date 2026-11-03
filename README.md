# Open Code apps

Two offline-first Android apps in one Gradle project. Both are native Kotlin
with Jetpack Compose. No accounts, no analytics, no network permission.

| App | Module | What it is |
| --- | --- | --- |
| **Wingman** | `:app` | A private notebook for keeping Discord friendships organised. |
| **Halo Camera** | `:camera` | A native camera app with on-device AI, video recording and a full editor. |

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

## Halo Camera

A real camera app: CameraX capture, video recording with audio, a 5-pass
computational-photography pipeline, ML Kit scene understanding and subject
segmentation — all on device. Aimed at the Redmi Note 9 Pro (Android 12) and
designed to look and feel like a flagship camera.

### Capture

- CameraX 1.4.2 image capture at sensor quality, tap to focus, pinch to zoom
- **Video recording** — HD/FHD/4K selector, a 60 fps option on Preview, live
  recording pill with elapsed time, audio when the mic permission is granted
- Front / back lens switch, flash off / on / auto, torch
- 3 s and 10 s self-timer, rule-of-thirds grid, manual exposure (EV) control
- Capture modes: Photo, Portrait, Night and Pro
- Sora + Inter type, dark halo design language, haptic feedback

### AI (all on device, always offline)

- **Auto AI** — ML Kit image labelling + histogram stats classify the scene
  (night, low light, portrait, landscape, food, document, backlit, golden hour)
  and apply a matching recipe immediately after capture
- **AI vision pass** — a multi-pass detail/contrast/colour lift in
  `data/ImagePipeline.kt`
- **Night boost** — gamma shadow lifting + temporal-ish denoise
- **Smart HDR** — highlight shoulder + shadow lift to rescue skies
- **Detail boost** — edge-aware unsharp masking that survives zooming
- **Portrait bokeh** — ML Kit *selfie segmentation* produces a real subject
  mask (bundled model, no download); the backdrop is blurred around it, with a
  graceful radial fallback when no subject is found
- **Beautify** — edge-aware skin smoothing that keeps texture

### Editor

- Tabbed panel: Looks / Light / Color / Detail / AI / Crop
- **20 looks** with live-filter thumbnails and an intensity slider
- Exposure, contrast, highlights, shadows, fade, saturation, warmth, tint,
  clarity, sharpen, denoise, grain, vignette
- Rotating 90°, horizontal flip, aspect-ratio crop (full / 1:1 / 4:5 / 3:2 / 16:9)
- RGB histogram overlay, hold-to-compare original
- Full-resolution render on save (with an OOM fallback path)

### Library

- Photo + video grid with video duration badges
- Long-press multi-select, batch export to the system gallery, delete
- In-app video player (Media3 / ExoPlayer) with controls and export

The enhancement pipeline is plain Kotlin pixel maths (`data/ImagePipeline.kt`);
`AutoEnhance`, `ColorOps` and image statistics are covered by JVM unit tests.

### Privacy

Photos live in app-private storage (`files/photos/`), videos in
(`files/videos/`). ML Kit models are bundled. Nothing is uploaded; the app
declares only `CAMERA`, `RECORD_AUDIO` and legacy-storage `WRITE_EXTERNAL_STORAGE`
(maxSdk 28) — no internet permission.

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
