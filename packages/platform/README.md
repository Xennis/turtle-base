# @turtle-base/platform

What turtle-base needs from the platform it runs on, as one `Platform` interface: SQLite (`SqlDriver`), a directory for attachment files (`FileDirectory`), device-local settings, OS-encrypted secrets, a `fetch` outside the web view (no CORS limits), opening links and Google sign-in for Drive sync (`GoogleAuthenticator`). The app only talks to this interface; the Tauri shell (`apps/shell`, with `tauri-platform.ts` in the app) implements it.

`@turtle-base/platform/testing` has test doubles: `createNodeSqlDriver()` (in-memory SQLite on Node's built-in `node:sqlite`, no native module) and in-memory key-value stores, secret stores, file directories and a `FakeGoogleAuthenticator`.
