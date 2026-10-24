# @turtle-base/desktop

The Electron shell of turtle-base (Linux, macOS): the main process and the preload. The app itself - UI and logic - is the renderer from [apps/turtle-base](../turtle-base); this package only implements its `Platform` on the desktop.

- **SQLite** runs in the main process on Node's built-in `node:sqlite` - no native module, nothing to rebuild for Electron's ABI. The renderer reaches it through IPC.
- **IPC** carries exactly the calls typed in `IpcContract` (`@turtle-base/platform`): the preload exposes only those channels as `window.turtleDesktop`, and the main process only answers frames of the app itself.
- **Prefs** are one JSON file, **secrets** are encrypted by the OS keyring (`safeStorage`), **attachment files** live flat in `files/` - all in Electron's `userData` folder (`~/.config/turtle-base` on Linux).
- **`fetch`** for the renderer runs in the main process (`net.fetch`), so requests to Drive, Open Library or AI providers aren't limited by CORS.
- The renderer is served from `app://turtle/` (built files of apps/turtle-base, with a strict Content-Security-Policy), attachment files from `turtle-file://files/<name>`. The window runs with `contextIsolation`, `sandbox` and without Node integration; links open in the system browser.

`vp pack` builds `dist/main.mjs` (ESM) and `dist/preload.cjs` (CommonJS - a sandboxed preload can't be an ES module). Electron's binary is downloaded by this package's `postinstall`, since pnpm doesn't run dependencies' build scripts.
