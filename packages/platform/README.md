# @turtle-base/platform

What turtle-base needs from the platform it runs on, as one `Platform` interface: SQLite (`SqlDriver`), a directory for attachment files (`FileDirectory`), device-local settings, OS-encrypted secrets, a `fetch` outside the web view (no CORS limits), opening links and Google sign-in for Drive sync (`GoogleAuthenticator`). The app only talks to this interface; the Electron shell (`apps/desktop`) and the Capacitor shell (`apps/mobile`) implement it. It grows with the features ported from the Flutter app.

`@turtle-base/platform/testing` has test doubles: `createNodeSqlDriver()` (in-memory SQLite on Node's built-in `node:sqlite`, no native module) and in-memory key-value stores, secret stores, file directories and a `FakeGoogleAuthenticator`.

`@turtle-base/platform/node` has `createNodeSqlDriver()` on Node's built-in `node:sqlite` - used by the tests and by Electron's main process alike.

The desktop shell's renderer reaches the main process only through the calls typed in `IpcContract` (`ipc-contract.ts`): the main process handles exactly these channels, the preload exposes exactly these, and the renderer's client is typed by them.
