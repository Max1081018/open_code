#!/usr/bin/env bash
#
# Build an installable Deepdelve APK.
#
# Run this on a machine with the Android SDK and NDK. The cloud container the
# game was developed in cannot reach Google's download servers, so the NDK is
# not available there and this script has never been executed end to end.
# Treat the first run as something to debug, not as a guaranteed one-shot.
#
# Usage:  ./build-apk.sh [debug|release]       (default: release)

set -euo pipefail

PROFILE="${1:-release}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JNI_LIBS="$HERE/android/app/src/main/jniLibs"

if [[ "$PROFILE" != "debug" && "$PROFILE" != "release" ]]; then
    echo "error: profile must be 'debug' or 'release', got '$PROFILE'" >&2
    exit 1
fi

fail() {
    echo "error: $1" >&2
    [[ $# -gt 1 ]] && echo "       $2" >&2
    exit 1
}

# ---------------------------------------------------------------- checks ---

command -v cargo >/dev/null \
    || fail "cargo not found" "Install Rust from https://rustup.rs"

command -v cargo-ndk >/dev/null \
    || fail "cargo-ndk not found" "Install it with: cargo install cargo-ndk"

for target in aarch64-linux-android armv7-linux-androideabi; do
    rustup target list --installed | grep -qx "$target" \
        || fail "Rust target $target is missing" \
                "Add it with: rustup target add $target"
done

NDK_PATH="${ANDROID_NDK_HOME:-${NDK_HOME:-}}"
if [[ -z "$NDK_PATH" ]]; then
    # Fall back to the newest NDK inside a standard SDK install.
    SDK_PATH="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
    if [[ -d "$SDK_PATH/ndk" ]]; then
        NDK_PATH="$(find "$SDK_PATH/ndk" -maxdepth 1 -mindepth 1 -type d | sort -V | tail -1)"
    fi
fi

[[ -n "$NDK_PATH" && -d "$NDK_PATH" ]] \
    || fail "Android NDK not found" \
            "Install it via Android Studio (SDK Manager > SDK Tools > NDK) and set ANDROID_NDK_HOME"

export ANDROID_NDK_HOME="$NDK_PATH"
echo "==> NDK: $ANDROID_NDK_HOME"

# ------------------------------------------------- native libraries (Rust) ---

echo "==> Compiling Rust for arm64-v8a and armeabi-v7a ($PROFILE)"
rm -rf "$JNI_LIBS"
mkdir -p "$JNI_LIBS"

CARGO_ARGS=(build -p deepdelve-app)
[[ "$PROFILE" == "release" ]] && CARGO_ARGS+=(--release)

( cd "$HERE" && cargo ndk \
    -t arm64-v8a \
    -t armeabi-v7a \
    -o "$JNI_LIBS" \
    "${CARGO_ARGS[@]}" )

# cargo-ndk emits libdeepdelve_app.so per ABI; GameActivity loads it by the
# android.app.lib_name in the manifest.
for abi in arm64-v8a armeabi-v7a; do
    [[ -f "$JNI_LIBS/$abi/libdeepdelve_app.so" ]] \
        || fail "libdeepdelve_app.so missing for $abi" \
                "Check that app/Cargo.toml still declares crate-type = [\"lib\", \"cdylib\"]"
done

echo "==> Native libraries:"
find "$JNI_LIBS" -name '*.so' -exec ls -lh {} \; | awk '{print "    " $9 " (" $5 ")"}'

# ----------------------------------------------------------------- gradle ---

cd "$HERE/android"

if [[ -x ./gradlew ]]; then
    GRADLE=./gradlew
elif command -v gradle >/dev/null; then
    GRADLE=gradle
else
    fail "neither ./gradlew nor gradle found" \
         "Install Gradle 8.5+ or run 'gradle wrapper' once in game/android"
fi

TASK="assembleRelease"
[[ "$PROFILE" == "debug" ]] && TASK="assembleDebug"

echo "==> $GRADLE $TASK"
"$GRADLE" "$TASK"

APK="$(find "$HERE/android/app/build/outputs/apk/$PROFILE" -name '*.apk' | head -1)"
[[ -n "$APK" ]] || fail "Gradle finished but produced no APK"

echo
echo "==> APK ready: $APK"
echo "    Install with: adb install -r \"$APK\""
