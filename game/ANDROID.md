# Building Deepdelve for Android

## Status: scaffolded, not yet built end to end

**This has never produced an APK.** The game was developed in a cloud
container whose network policy refuses `dl.google.com`, so the Android NDK
cannot be installed there. Everything up to the NDK is verified; the NDK
step and everything after it is not.

What *is* verified in the dev container:

- the game builds and runs on desktop, rendering through Bevy on llvmpipe
- `cargo-ndk` 4.1.2 installs and runs
- the Rust Android targets (`aarch64-linux-android`, `armv7-linux-androideabi`)
  install cleanly
- `build-apk.sh` runs its full preflight and stops at the NDK check with a
  clear message

What is **not** verified:

- cross-compiling Bevy to ARM
- Gradle packaging the `.so` files
- GameActivity actually finding `android_main`
- the game running on a physical device

Treat the first run as a debugging session. The notes at the bottom cover the
failures most likely to come up.

## One-off setup

1. **Android Studio**, then SDK Manager → SDK Tools → install **NDK
   (Side by side)** and **Android SDK Platform 35**.
2. Point the tooling at the NDK:
   ```bash
   export ANDROID_HOME="$HOME/Android/Sdk"
   export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/<version>"
   ```
3. Rust targets and the cargo-ndk helper:
   ```bash
   rustup target add aarch64-linux-android armv7-linux-androideabi
   cargo install cargo-ndk
   ```
4. **Gradle 8.5+**, or run `gradle wrapper` once inside `game/android` so
   `./gradlew` exists.

## Building

```bash
cd game
./build-apk.sh release      # or: ./build-apk.sh debug
```

The script compiles the Rust for both ABIs, drops the `.so` files into
`android/app/src/main/jniLibs/<abi>/`, then runs Gradle. It prints the APK
path when it finishes.

Install it:

```bash
adb install -r android/app/build/outputs/apk/release/app-release.apk
```

Use **release**. A debug build of a Bevy game is enormous and painfully slow
on a phone.

## How the pieces fit

The app crate builds as both a `lib` (for the desktop binary) and a `cdylib`
(for Android), declared in `app/Cargo.toml`.

`#[bevy_main]` on `main()` in `app/src/lib.rs` generates an `android_main`
symbol. `GameActivity` — supplied by the `androidx.games:games-activity`
dependency — loads `libdeepdelve_app.so` and calls into it. The link between
them is the manifest's `android.app.lib_name`, which **must** stay equal to
the `[lib] name` in `app/Cargo.toml`:

```
app/Cargo.toml   [lib] name = "deepdelve_app"
AndroidManifest  android.app.lib_name = "deepdelve_app"
→ loads           libdeepdelve_app.so
```

Rename one without the other and the app installs, launches, and immediately
dies with `UnsatisfiedLinkError`.

The APK is signed with the **debug key** so it sideloads without setup.
Replace that signing config before distributing anything.

## Likely first-run problems

**`UnsatisfiedLinkError: couldn't find "libdeepdelve_app.so"`**
The `.so` did not get packaged, or the names drifted apart. Check
`unzip -l app-release.apk | grep '\.so'` and compare against the manifest's
`android.app.lib_name`.

**App launches to a black screen, then exits**
Usually wgpu failing to get a surface. Get the real error with
`adb logcat | grep -iE 'wgpu|bevy|RustStdoutStderr'`.

**`minSdk` or Vulkan complaints on an older phone**
`minSdk` is 28. Very old or unusual GPUs may lack a working Vulkan driver;
wgpu should fall back to GLES 3, but that path is untested here.

**Gradle cannot resolve `androidx.games:games-activity`**
That artifact comes from Google's Maven. Check network access and that
`google()` is in the repository list in `settings.gradle`.

**Out of memory during the Rust build**
Bevy is a heavy compile. `export CARGO_BUILD_JOBS=2` if the machine is small.

## Performance expectations

Untested on hardware. The design is built around the constraint: chunks are
composited once into a single texture each and drawn as one quad rather than
one sprite per tile, and only chunks near the player stay resident. The
likeliest bottleneck is chunk re-compositing on the CPU when a lot of tiles
change at once, which would show as a hitch while digging quickly.
