# turtle-base

Monorepo (pnpm workspace, TypeScript) with the turtle-base app, its Tauri shell for the desktop and Android, and the packages it is built from. Tool versions come from [mise](https://mise.jdx.dev/) (see `mise.toml`).

| Path                                                                       | What                                                                                  |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| [apps/turtle-base](apps/turtle-base)                                       | The app - React UI and app logic, shown by the shell                                  |
| [apps/shell](apps/shell)                                                   | The Tauri 2 shell for Linux, macOS and Android                                        |
| [packages/platform](packages/platform)                                     | The `Platform` interface the shell implements                                         |
| [packages/sql-crdt](packages/sql-crdt)                                     | Last-writer-wins CRDT on SQLite (Kysely), the base of the sync                        |
| [packages/crdt-file-sync-transport](packages/crdt-file-sync-transport)     | `SyncTransport` interface that storage adapters implement                             |
| [packages/crdt-file-sync-google-drive](packages/crdt-file-sync-google-drive) | Google Drive storage adapter (optional) - incl. its sign-in and OAuth configuration |
| [packages/field-types](packages/field-types), [packages/plugin-api](packages/plugin-api) | Field variants and the API plugins are written against                |
| [packages/books](packages/books)                                           | The Books plugin (reading list, Open Library lookup)                                  |
| [ops/infra](ops/infra)                                                     | Google Cloud setup (OpenTofu + manual checklist)                                      |

Run `mise run install` in the repo root, then e.g. `mise run run-desktop` (`mise tasks` lists the others). Google Drive sync is optional and configured via env vars - see [its README](packages/crdt-file-sync-google-drive/README.md#configuration).

New storage backends (e.g. another cloud) go into their own `packages/crdt-file-sync-<storage>` package that depends on `crdt-file-sync-transport`.

## From the Flutter app

turtle-base was a Flutter app before. Its data is taken over once, on the desktop: Settings → "Flutter app" imports its database and files (read-only - the Flutter app's data stays as it is). Other devices then get it through sync, which uses a Drive folder of its own (`turtle-base-sync-v3`), apart from the Flutter app's.

## Releases

Pushing a tag `vX.Y.Z+N` runs [.github/workflows/release.yml](.github/workflows/release.yml): a Linux AppImage and an unsigned macOS `.dmg`, and an Android APK (all built by Tauri) with `versionName` `X.Y.Z` and `versionCode` `N`. `mise run package-desktop` packages the desktop app locally.

## Android release signing

Google Sign-In in Android release builds requires the release APK to be signed with a key whose SHA-1 fingerprint is registered on the Android OAuth client - see [ops/infra/README.md](ops/infra/README.md#4-oauth-client---android). Locally this is configured via a gitignored `apps/shell/src-tauri/gen/android/key.properties` (see `app/build.gradle.kts` there; falls back to debug signing if absent). In CI, the release workflow builds that file from the `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEY_PASSWORD` repo secrets plus the `ANDROID_KEY_ALIAS` repo variable.

## System dependencies (Linux)

Building the Tauri shell needs WebKitGTK and its companions: `libwebkit2gtk-4.1-dev libsoup-3.0-dev librsvg2-dev build-essential`, and `webkit2gtk-driver` for `mise run desktop-smoke`. Rust itself comes from mise.

The desktop app keeps secrets (AI API keys, the Drive sign-in) in the freedesktop.org Secret Service on Linux: a keyring service (e.g. GNOME Keyring or KWallet) must be running, or saving a key fails.
