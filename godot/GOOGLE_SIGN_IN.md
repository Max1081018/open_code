# Google sign-in: why it is unavailable, and what it needs

## What the game does today

`Account.provider_sign_in("google")` (scripts/autoload/account.gd) signs in
only when **both** are present:

1. `res://auth_config.json` with `{"google": {"client_id": "..."}}`, and
2. an Android plugin singleton named `GodotGoogleSignIn` whose `sign_in()`
   returns `{ok, user_id, name, email}` after Google has verified the user.

Neither exists in this build, so the button explains that Google sign-in is
not available and suggests playing as a guest. It never fakes a sign-in.

(The crash on tapping that button in build 3 was a separate bug: every button
vibrates and the VIBRATE permission was missing. Fixed in build 4.)

## Findings

| Check | State |
|---|---|
| Google Sign-In implementation | None: no native plugin, no Credential Manager code |
| Firebase | Not used (no `google-services.json`) |
| Android OAuth client | None configured |
| Package ID | `com.lanternbound.game` (kept through the Ethereal Tales rebrand so updates and saves carry over) |
| Release signing certificate (CI key) | SHA-1 `6b92daf8d77a77fcea723ad0347a0cd347ef7af5`, SHA-256 `ef2f8545be600dc04fc56b846edd9a8c8fc00861d7bc65cc58c6823f23f1fd3b` |
| Signing key storage | GitHub Actions cache only: **evicted after 7 days unused**, then a new key (new fingerprint) would be made. Store it as the `ANDROID_KEYSTORE_B64` repository secret (the workflow uses it when present). Its password is in the workflow file, so for a real release make your own key. |
| INTERNET permission | Not requested (the game is offline); Google sign-in needs it |
| Export type | Plain template export; a native plugin needs a **Gradle build** export (`gradle_build/use_gradle_build=true`) |
| Redirect URIs | Not applicable to the native Android flow (Credential Manager); only a web/browser flow uses them |
| Backend | None. A token checked only on the phone proves nothing to a server; cross-device accounts need a backend that verifies Google ID tokens |

## What you need to provide

1. A **Google Cloud project** with the OAuth consent screen configured
   (app name "Ethereal Tales", support email, privacy policy URL).
2. An **OAuth client of type Android**: package `com.lanternbound.game`, SHA-1
   of the key that signs the APK you install (the CI key above, or your own
   key's SHA-1 if you put your own keystore in the secret).
3. An **OAuth client of type Web application**: its client ID is the
   "server client ID" the Android Credential Manager asks for to get an ID
   token. Put it in `godot/auth_config.json`:
   `{"google": {"client_id": "<web client id>.apps.googleusercontent.com"}}`
4. Optional but needed for real cross-device accounts: a **backend** (or
   Firebase Auth) that verifies the ID token and issues the game's own
   session.

## The remaining implementation (next task once credentials exist)

Candidate plugin found (not installed yet): **NiqueWrld/GodotGoogleSignIn**
(github.com/NiqueWrld/GodotGoogleSignIn, MIT, "Native Android Google Sign-In
plugin for Godot 4.2+ using Credential Manager API", last updated
2026-01-19, small project: review its code and pin a release before use).
Its API would be wrapped to the `GodotGoogleSignIn.sign_in()` contract above.
Writing our own (below) is the fallback.

- A small Godot Android plugin (Kotlin, Godot v2 plugin AAR) named
  `GodotGoogleSignIn` using `androidx.credentials` +
  `com.google.android.libraries.identity.googleid` (`GetGoogleIdOption` with
  the server client ID), exposing `sign_in()` → `{ok, user_id, name, email,
  id_token}`.
- Switch the export to a Gradle build, add the INTERNET permission, and have
  the CI workflow install the Android build template and build the plugin.
- Without the client IDs it cannot be tested end to end, so it was not built
  blind in this pass.
