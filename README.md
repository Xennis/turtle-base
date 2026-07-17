# turtle-base

## Google Drive sync configuration

Google Drive sync needs OAuth client IDs, supplied at build time via `--dart-define` rather than a committed/copied file - see `lib/packages/crdt_file_sync/google_drive/client_config.dart`. For how to obtain the values, see [ops/infra/README.md](ops/infra/README.md).

| Variable                        | Needed on |
| -------------------------------- | --------- |
| `DRIVE_DESKTOP_CLIENT_ID`        | Linux     |
| `DRIVE_DESKTOP_CLIENT_SECRET`    | Linux     |
| `DRIVE_ANDROID_SERVER_CLIENT_ID` | Android   |

None of these are required to build or run the app - if unset, Drive sync is silently disabled (a warning is logged) and its UI stays hidden in Settings.

For local development, copy [.mise.local.toml.example](.mise.local.toml.example) to `.mise.local.toml` (gitignored) and fill in the values, then use `mise run run-linux` / `mise run run-android` (see `mise.toml`), which forward them as `--dart-define` automatically. The release pipeline ([.github/workflows/release.yml](.github/workflows/release.yml)) reads the same variable names from repo secrets.

## System dependencies (Linux)

`flutter_secure_storage` stores AI API keys via the freedesktop.org Secret Service (libsecret) on Linux. Install the packages listed under "Linux" on <https://pub.dev/packages/flutter_secure_storage#linux> (dev + runtime libsecret packages) and make sure a keyring service (e.g. GNOME Keyring) is running, or reading/writing a key will fail.
