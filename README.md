# Taskly

Offline-first tasks and notes app for Android. Native Kotlin + Jetpack Compose + Room.

## Features

- Create, edit and delete tasks with title, notes, priority and due date
- Pin important tasks to the top
- Complete tasks with a checkbox and progress bar
- Search, filter (All / Active / Done) and sort (Smart / Due / Priority / Newest)
- Undo delete via snackbar
- Light / dark / system theme, remembered across launches
- Fully offline, data stored locally with Room

## Build

CI builds a debug APK on every push to `main` (`.github/workflows/build-apk.yml`). Pushing a `v*` tag attaches the APK to a GitHub release.

```sh
git tag v1.1
git push origin v1.1
```

## Stack

- Kotlin 1.9.24, AGP 8.5.2, Gradle 8.7, JDK 17
- Jetpack Compose (BOM 2024.06.00), Material 3
- Room 2.6.1 with KSP
- minSdk 24, targetSdk 34
