# turtle-base

Monorepo (Dart pub workspace) with the turtle-base Flutter app and the packages it is built from. Tool versions come from [mise](https://mise.jdx.dev/) (see `mise.toml`).

| Path                                                                       | What                                                                                             |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| [apps/turtle_base](apps/turtle_base)                                        | The Flutter app (Linux, macOS, Android)                                                          |
| [packages/crdt_file_sync_transport](packages/crdt_file_sync_transport)      | `SyncTransport` interface that storage adapters implement                                        |
| [packages/crdt_file_sync_google_drive](packages/crdt_file_sync_google_drive) | Google Drive storage adapter (optional) - incl. its OAuth configuration                          |
| [ops/infra](ops/infra)                                                      | Google Cloud setup (OpenTofu + manual checklist)                                                 |

Run `flutter pub get` in the repo root (one shared `pubspec.lock`), then e.g. `mise run run-linux`. Google Drive sync is optional and configured via env vars - see [its README](packages/crdt_file_sync_google_drive/README.md#configuration).

New storage backends (e.g. another cloud) go into their own `packages/crdt_file_sync_<storage>` package that depends on `crdt_file_sync_transport`.

## Android release signing

Google Sign-In in Android release builds requires the release APK to be signed with a key whose SHA-1 fingerprint is registered on the Android OAuth client - see [ops/infra/README.md](ops/infra/README.md#4-oauth-client---android). Locally this is configured via a gitignored `apps/turtle_base/android/key.properties` (see `apps/turtle_base/android/app/build.gradle.kts`; falls back to debug signing if absent). In CI, [.github/workflows/release.yml](.github/workflows/release.yml) builds that file from the `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEY_PASSWORD` repo secrets plus the `ANDROID_KEY_ALIAS` repo variable.

## System dependencies (Linux)

`flutter_secure_storage` stores AI API keys via the freedesktop.org Secret Service (libsecret) on Linux. Install the packages listed under "Linux" on <https://pub.dev/packages/flutter_secure_storage#linux> (dev + runtime libsecret packages) and make sure a keyring service (e.g. GNOME Keyring) is running, or reading/writing a key will fail.
