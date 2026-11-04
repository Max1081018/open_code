# AI Camera — Design Doc

Date: 2026-11-02
Status: Milestone 1 built (`:camera` module, shipped as **Halo**). Video, ML
segmentation and the remaining edit ops are milestone 2.

## Intent and why

The user (Max1081018) wants a true native Android AI camera for their
Redmi Note 9 Pro (Android 12) that produces stunning photos with AI,
styled after a flagship "iPhone 17 class" camera, with on-device AI
editing and trendy teen filters.

## Goals

- Native camera capture (photo + 4K video) with best-possible quality on
  the Note 9 Pro's hardware.
- On-device AI enhancement after capture (night mode, HDR, scene-aware
  auto-enhance, beauty) producing visibly stunning photos.
- In-app AI editing, user-initiated only: crop/rotate, relight, exposure,
  contrast, color grade, sharpen, retouch, background blur, filters.

## Non-goals

- Literally matching iPhone 17 output (physically unrealistic on a
  Snapdragon 720G-class mid-ranger; goal is "visually flagship-stunning").
- Cloud AI / server-side processing.

## Anti-goals

- Scope creep beyond capture + AI edit + filters.
- Claiming verification we cannot perform locally.

## Constraints

- Device: Redmi Note 9 Pro, Android 12, mid-range SoC (720G series) —
  AI inference must use NNAPI / GPU delegate via TFLite for smooth latency.
- Project: minSdk 24, targetSdk 34 (existing Wingman app config).
- No local JDK/Android SDK in this environment — build/verify via the
  existing GitHub Actions workflow (`.github/workflows/build-apk.yml`) and
  release APK.
- Offline-first; no new permissions beyond CAMERA (+ app-scoped storage).

## Approaches considered

1. **Standalone new camera app** (CameraX + ML Kit + TFLite) — **CHOSEN**.
   Camera is its own product; avoids polluting the Wingman friendship app.
2. New module inside the existing Wingman app — rejected (wrong product
   surface, shared UI would distort both).
3. Web / PWA camera — rejected (not a true camera app).

## Parts of the how (decided)

- Capture: CameraX (Preview + ImageCapture), main + ultrawide, 4K video,
  shutter, gallery, flip camera, timer, grid.
- Enhancement: on-device post-capture AI, user toggles: Night, HDR,
  Scene Enhance, Beauty.
- Editing: user opens an edit sheet after capture; AI ops: Auto Enhance,
  Relight, Exposure, Contrast, Color Grade, Sharpen, Retouch, Background
  Blur; plus filters.
- Filters: starter teen-trendy preset set (Lark, Juno, Noir, Sunset Glow,
  Dream, Vivid) — final list pending user input.

## Left to the builder

- Exact file structure, screens, state flow, TFLite model wiring.

## Open questions

1. Final teen-filter list the user wants (exact names/styles), or approve
   the starter set.
2. Which AI edit op matters most to the user.

## Milestone 1 — what actually shipped

Module `:camera`, applicationId `com.example.camera`, branded **Halo**.

- CameraX `Preview` + `ImageCapture` (max quality), back/front, flash
  off/on/auto, 3 s / 10 s timer, rule-of-thirds grid, pinch zoom, tap to
  focus, shutter flash animation.
- App-private library (`files/photos`), 3-column grid, EXIF-correct
  decoding, per-photo editor, delete.
- Editor with seven looks (Original, Lark, Juno, Noir, Sunset, Dream,
  Vivid), five adjustments, and four AI toggles (Night, HDR, Retouch,
  Portrait) plus histogram-driven Auto Enhance.
- All processing is plain Kotlin pixel maths in `data/ImagePipeline.kt`,
  `data/ColorOps.kt` and `data/AutoEnhance.kt`; the pure parts are unit
  tested (`src/test/...`). No model download, no network, `CAMERA` is the
  only permission.
- Save writes a full-resolution copy (`_edit.jpg`), previews render at
  1440 px, exports cap at 4096 px. Sharing goes through a `FileProvider`.

Deliberate deviation: **Portrait** is a radial edge blur, not subject
segmentation, because a real mask needs an ML model that is not bundled
yet. It is labelled "Edge blur" in the UI so the claim matches reality.

Milestone 2 backlog: 4K video (`camera-video`), ML Kit / TFLite subject
segmentation, crop/rotate, before/after compare, and MediaStore export so
photos appear in the system gallery.


## Milestone 2 — "Halo Camera 2.0" (what shipped, 2026-11-03)

The whole `:camera` module was rewritten. applicationId unchanged so it
updates in place; versionCode 24, versionName 2.1.0, label **Halo Camera**.

- **Video** — CameraX `camera-video` 1.4.2 Recorder: SD/FHD/4K selector,
  30/60 fps target on the preview stream, audio when the mic permission is
  granted, live red-pill timer while recording, in-app Media3/ExoPlayer
  playback with export.
- **Real portrait bokeh** — ML Kit `segmentation-selfie` (bundled model) in
  `data/SceneAnalyzer.kt` produces a confidence mask; `ImagePipeline.render`
  blurs the backdrop around it and falls back to radial blur when no subject
  is found.
- **Scene understanding** — ML Kit `image-labeling` (bundled) feeds the
  classifier in `AutoEnhance.classify` (food, document, night, portrait,
  landscape, golden hour, backlit).
- **AI vision pass** — a multi-pass detail/micro-contrast/colour lift behind
  a toggle, plus detail boost (edge-aware unsharp), night boost, smart HDR
  and beautify in `data/ImagePipeline.kt`.
- **20 looks** with rendered filter thumbnails and intensity slider; editor
  tabs Looks / Light / Color / Detail / AI / Crop; rotate + flip + aspect
  crop; RGB histogram overlay; hold-to-compare; full-res save with an OOM
  fallback; MediaStore export to the system gallery.
- **Capture modes** Photo / Portrait / Night / Pro with a manual EV slider,
  flash, torch, timer, grid, zoom presets, haptics.
- **Design** — Sora + Inter variable fonts, dark "halo" palette, adaptive
  vector icon, glass surfaces, no debug branding; APK artefact renamed to
  `HaloCamera.apk`.
- Permissions stay `CAMERA` + `RECORD_AUDIO` (+ legacy storage maxSdk 28);
  no INTERNET permission; everything computes on device.
