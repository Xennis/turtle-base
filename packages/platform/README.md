# @turtle-base/platform

What turtle-base needs from the platform it runs on, as one `Platform` interface: SQLite (`SqlDriver`), a directory for attachment files (`FileDirectory`), device-local settings, OS-encrypted secrets, a `fetch` outside the web view (no CORS limits) and opening links. The app only talks to this interface; the Electron shell (`apps/desktop`) and the Capacitor shell (`apps/mobile`) implement it. It grows with the features ported from the Flutter app.

`@turtle-base/platform/testing` has test doubles: `createNodeSqlDriver()` (in-memory SQLite on Node's built-in `node:sqlite`, no native module) and in-memory key-value stores, secret stores and file directories.
