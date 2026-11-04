# Open Code apps

Two native Kotlin apps with Jetpack Compose in one Gradle project. No accounts,
no analytics, no tracking. **Wingman** stays entirely on the device except for the
one screen you deliberately send to a model you configured; **Halo Camera** never
touches the network at all.

| App | Module | What it is |
| --- | --- | --- |
| **Wingman** | `:app` | A private notebook for keeping Discord friendships organised, plus an optional reply coach. |
| **Halo Camera** | `:camera` | A native camera app with on-device AI, video recording and a full editor. |

---

## Wingman

A wingman for keeping your Discord friendships organised. Native Kotlin, Jetpack
Compose and Room. No account, no analytics. The notebook is offline; the optional
reply coach talks to a model provider **you** configure, and only when you press
the button.

### What it does

- **Friend notebook** — name, Discord handle, vibe, interests, communication style and private notes
- **Consent tracking** — Not started / Agreed / Active / Paused, shown on every card and inside each chat
- **Two-sided chat log** — record what you said *and* what they said, per friend
- **Wingman profile** — a summary, vibe, interests, confidence score and suggested opener generated on-device from the notes and chat history you saved
- **Reply coach** — paste or edit the last few messages, and get an honest read of where the conversation is, the signals behind it, and three replies in your own voice with the reasoning for each
- **Search, edit, undo delete** — including full restore of a friend's chat history and profile
- **Themes** — Auto / Light / Dark, remembered across launches

### The reply coach

Press **Coach** inside any chat. The transcript is pre-filled from the messages
you logged and is fully editable. Lines beginning `Me:` are yours; everything
else counts as theirs.

You get back:

- **Where this is at** — what they actually seem to want from the conversation, including when the honest answer is "she's being polite"
- **Signals** — the specific things in the chat that led to that read
- **Three options** — `curious`, `playful` and `direct`, each with a one-line reason, each tappable into your message box
- **Worth knowing** — a warning when the right move is to not send anything

The coach will not write compliments about appearance, pet names, invented shared
history, stacked questions, or paragraphs when they wrote one line. If the chat is
one-sided it says so instead of manufacturing cleverness.

It works with any OpenAI-compatible `/chat/completions` endpoint (OpenAI,
OpenRouter, Groq, your own server), so you bring your own key and model.

### What the coach sends, exactly

Only three things leave the phone, and only when you press **Read the room**:

1. the transcript in the box,
2. your "how you text" note,
3. their communication-style note from their profile.

Names, Discord handles and your private notes about them are **not** in the
request. The API key is stored with `EncryptedSharedPreferences` (Android
keystore) and is not written to Room or to logs. There is no other network call
in the app.


---

## Halo Camera

A real camera app: CameraX capture, video recording with audio, a 5-pass
computational-photography pipeline, ML Kit scene understanding and subject
segmentation — all on device. Aimed at the Redmi Note 9 Pro (Android 12) and
designed to look and feel like a flagship camera.

### Capture

- CameraX 1.4.2 image capture at sensor quality (maximize-quality mode, JPEG q100),
  tap to focus, double-tap to flip lenses, pinch to zoom with 0.5x–max presets
- **Video recording** — HD/FHD/4K selector with 12/22/45 Mbps bitrates, 24/30/60 fps,
  pause & resume mid-clip, live mute toggle, live recording pill with elapsed
  time, audio when the mic permission is granted
- Front / back lens switch, flash off / on / auto, torch (gated on real flash units)
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
- **24 looks** with live-filter thumbnails and an intensity slider
- Exposure, contrast, highlights, shadows, fade, saturation, warmth, tint,
  clarity, sharpen, denoise, grain, vignette
- Rotating 90°, horizontal flip, aspect-ratio crop (full / 1:1 / 4:5 / 3:2 / 16:9)
  — the crop respects rotation, so a 3:2 pick stays 3:2 after a 90° turn
- RGB histogram overlay, before/after wipe slider, hold-to-compare original
- AI relight — lift the subject and dim the background using the portrait mask
- Full-resolution render on save with JPEG q100, EXIF camera/date stamps and an
  OOM fallback path

### Library

- Photo + video grid with video duration badges
- Long-press multi-select, select-all, batch export to the system gallery,
  batch share (mixed photos and videos in one chooser), delete
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
https://github.com/Max1081018/open_code/releases/download/v2.4.0/Wingman.apk
https://github.com/Max1081018/open_code/releases/download/v2.4.0/HaloCamera.apk
```

Debug builds are signed with the debug keystore, so they install directly.

## Build

CI builds and tests both modules on every push to `main`
(`.github/workflows/build-apk.yml`). Pushing a `v*` tag attaches both APKs to a
GitHub release.

```sh
git tag v2.4.0
git push origin v2.4.0
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
- androidx.security-crypto 1.1.0 for keystore-backed key storage (`:app`)
- CameraX 1.3.4 with ExifInterface (`:camera`)
- minSdk 24, targetSdk 34
