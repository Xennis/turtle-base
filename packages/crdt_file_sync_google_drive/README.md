# crdt_file_sync_google_drive

Google Drive storage adapter for turtle-base's CRDT file sync. Implements the `SyncTransport` (changesets) and `FileTransport` (attachment files) interfaces from [crdt_file_sync_transport](../crdt_file_sync_transport) on top of a Google Drive app folder (`drive.file` scope only) and ships the platform-specific OAuth flows (`google_sign_in` on Android, a loopback consent flow on Linux/macOS).

Optional: the app builds and runs without any configuration, Drive sync is simply disabled and its UI stays hidden in Settings.

## Configuration

Drive sync needs OAuth client IDs, supplied at build time via `--dart-define` rather than a committed/copied file - see [`lib/src/client_config.dart`](lib/src/client_config.dart). For how to obtain the values, see [ops/infra/README.md](../../ops/infra/README.md).

| Variable                        | Needed on      |
| -------------------------------- | -------------- |
| `DRIVE_DESKTOP_CLIENT_ID`        | Linux, macOS   |
| `DRIVE_DESKTOP_CLIENT_SECRET`    | Linux, macOS   |
| `DRIVE_ANDROID_SERVER_CLIENT_ID` | Android        |

If a platform's variables are unset, `createDriveAuthenticator` returns `null` (a warning is logged) and the app hides the Drive sync UI.

For local development, copy [.mise.local.toml.example](../../.mise.local.toml.example) to `.mise.local.toml` in the repo root (gitignored) and fill in the values, then use `mise run run-linux` / `mise run run-android` / `mise run run-macos` (see [mise.toml](../../mise.toml)), which forward them as `--dart-define` automatically. The release pipeline ([.github/workflows/release.yml](../../.github/workflows/release.yml)) reads the same variable names from repo secrets.

## Layout in Drive

```
turtle-base-sync/
  format.json     {"version": <n>} - the layout version, see GoogleDriveSyncFolder.readFormatVersion
  changesets/     one folder per device (CRDT node id), holding that device's changeset files
  files/          content-addressed files, flat
```

Only folders the app created itself are visible to it (`drive.file`), so the subfolders must not be created by hand in the Drive web UI - moving folders the app created is fine.

## Usage

```dart
import 'package:crdt_file_sync_google_drive/crdt_file_sync_google_drive.dart';

final authenticator = createDriveAuthenticator(
  desktopClientId: DriveClientConfig.desktopClientId,
  desktopClientSecret: DriveClientConfig.desktopClientSecret,
  androidServerClientId: DriveClientConfig.androidServerClientId,
);
final client = await authenticator?.signIn();
final folder = GoogleDriveSyncFolder(authClient: client!);
// folder.changesets, folder.files, folder.readFormatVersion()
```

Widget tests that need an authenticator without reaching Google can use `FakeDriveAuthenticator` from `package:crdt_file_sync_google_drive/testing.dart`.
