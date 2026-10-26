# @turtle-base/shell

The Tauri 2 shell of turtle-base - one for Linux, macOS and Android. The app itself - UI and logic - is the page from [apps/turtle-base](../turtle-base); this package is the native side of its `Platform` (see `tauri-platform.ts` there).

Most of it comes from Tauri's official plugins - store (prefs), fs (attachment files, served to the page through the asset protocol), http (`fetch` outside the web view, no CORS), dialog, opener, os. The shell's own code covers the rest:

- **`src-tauri/src/sql.rs`**: the app's one SQLite connection (`rusqlite`, SQLite bundled). One connection, not a pool, since transactions are plain `BEGIN`/`COMMIT` statements.
- **`secrets.rs`**: secrets in the OS keyring (keyring-core) - the Secret Service on Linux, the Keychain on macOS, the Keystore on Android.
- **`loopback.rs`**: the server on 127.0.0.1 that catches the redirect of the desktop's Google sign-in.
- **`flutter.rs`**: the Flutter app's data, read-only, for the one-time import on the desktop.
- **`android.rs`** with **`AndroidPlatformPlugin.kt`** (in `src-tauri/gen/android`): what Tauri doesn't cover on Android - Google sign-in through Play services, the system bars' style, opening a file with another app, the name of a picked file.

`capabilities/default.json` lists what the page may use: of the disk only its `files/` folder (and copies for opening in `open/` of the cache), of the network only https. Data lives in Tauri's app data folder (`~/.local/share/org.xennis.apps.turtlebase` on Linux). On Linux the system draws the title bar; on macOS the traffic lights lie over the page (`tauri.macos.conf.json`).

`src-tauri/gen/android` is the Android project as `tauri android init` generated it, adapted: release signing from a gitignored `key.properties` there, the version from the Gradle properties `versionCode`/`versionName` (see the release workflow), the Kotlin plugin.

## Smoke tests

- **`e2e/desktop-smoke.e2e.ts`** (`mise run desktop-smoke`, Linux): drives the debug build over WebDriver (`tauri-driver`, WebKitWebDriver) on a fresh profile. The page is built with `TURTLE_E2E=1`, which puts `e2e-hooks.ts` of the app in front of the network, the file dialog and the browser, and keeps secrets in a file - the test answers them through `window.turtleE2e`.
- **`e2e/android-smoke.e2e.ts`** (`mise run mobile-smoke`): the debug build on an emulator through Playwright, with the real network and the system's file picker.
