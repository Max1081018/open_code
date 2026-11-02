# Wingman

An offline-first wingman for keeping your Discord friendships organised. Native Kotlin, Jetpack Compose and Room. No account, no network, no data leaves the phone.

## What it does

- **Friend notebook** — name, Discord handle, vibe, interests, communication style and private notes
- **Consent tracking** — Not started / Agreed / Active / Paused, shown on every card and inside each chat
- **Two-sided chat log** — record what you said *and* what they said, per friend
- **Wingman profile** — a summary, vibe, interests, confidence score and suggested opener generated on-device from the notes and chat history you saved
- **Search, edit, undo delete** — including full restore of a friend's chat history and profile
- **Themes** — Auto / Light / Dark, remembered across launches

## Install

Grab the latest debug APK from the releases page:

```
https://github.com/Max1081018/open_code/releases/latest
```

Or build a release tag and use its asset:

```
https://github.com/Max1081018/open_code/releases/download/v1.2/app-debug.apk
```

## Build

CI builds and tests on every push to `main` (`.github/workflows/build-apk.yml`). Pushing a `v*` tag attaches the APK to a GitHub release.

```sh
git tag v1.2
git push origin v1.2
```

Locally, with a JDK 17 and Android SDK installed:

```sh
gradle testDebugUnitTest
gradle assembleDebug
```

## Privacy

Everything is stored in a local Room database (`wingman.db`). The profile generator is deterministic local logic in `WingmanBrain` — there is no API key, no analytics and no upload.

## Stack

- Kotlin 1.9.24, AGP 8.5.2, Gradle 8.7, JDK 17
- Jetpack Compose (BOM 2024.06.00), Material 3
- Room 2.6.1 with KSP
- minSdk 24, targetSdk 34
