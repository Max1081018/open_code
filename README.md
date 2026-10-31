# App

Android app/game template that builds a signed (debug) APK in the cloud. No local SDK required.

## How it works

- `app/src/main/assets/index.html` — the app/game itself (HTML5 canvas).
- `app/src/main/java/com/example/app/MainActivity.java` — fullscreen WebView shell.
- `.github/workflows/build-apk.yml` — builds the APK on every push and offers it as an artifact.

## First-time setup

1. Create a new **empty** repo on GitHub (e.g. `app`).
2. From this folder:
   ```sh
   git init
   git add .
   git commit -m "Initial app"
   git branch -M main
   git remote add origin https://github.com/<you>/<repo>.git
   git push -u origin main
   ```
3. Open the repo's **Actions** tab, wait for "Build APK" to finish.
4. Download the `app-debug-apk` artifact and install `app-debug.apk` on the phone.

## Later builds

- Push any change → new APK artifact.
- Tag a release (`git tag v1.0 && git push --tags`) → APK attached to the GitHub release for easy phone download.

## Renaming

Change `com.example.app` in `app/build.gradle` and `namespace`, plus the `package` in `MainActivity.java`, and the app name in `res/values/strings.xml`.
