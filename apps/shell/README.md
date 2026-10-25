# @turtle-base/shell

The Tauri 2 shell of turtle-base - one for Linux, macOS and Android. The app itself - UI and logic - is the page from [apps/turtle-base](../turtle-base); this package is the native side of its `Platform` (see `tauri-platform.ts` there).

Most of it comes from Tauri's official plugins - store (prefs), fs (attachment files), http (`fetch` outside the web view, no CORS), dialog, opener, os. The shell's own commands (`src-tauri/src`) cover the rest:

- **`sql.rs`**: the app's one SQLite connection (`rusqlite`, SQLite bundled). One connection, not a pool, since transactions are plain `BEGIN`/`COMMIT` statements.
- **`secrets.rs`**: secrets in the OS keyring - the Secret Service on Linux, the Keychain on macOS, the Keystore on Android.

`capabilities/default.json` lists what the page may use: of the disk only its `files/` folder (and copies for opening in `open/` of the cache), of the network only https. Data lives in Tauri's app data folder (`~/.local/share/org.xennis.apps.turtlebase` on Linux).
