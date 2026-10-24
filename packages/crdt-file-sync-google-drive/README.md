# @turtle-base/crdt-file-sync-google-drive

Google Drive storage adapter for turtle-base's CRDT file sync. Implements the `SyncTransport` (changesets) and `FileTransport` (attachment files) interfaces from [crdt-file-sync-transport](../crdt-file-sync-transport) on top of a Google Drive folder, using only the `drive.file` scope.

It talks to the Drive REST API through plain `fetch` - the official client library is far too big for a web view - and takes the access token from outside: the OAuth flows are platform-specific and live in the shells (a loopback consent flow in Electron, native Google Sign-In in Capacitor), behind the app's `Platform` interface. The token function is called for every request, so the shell can refresh it. For how to obtain the OAuth client IDs, see [ops/infra/README.md](../../ops/infra/README.md).

## Layout in Drive

```
turtle-base-sync/
  format.json     {"version": <n>} - the layout version, see GoogleDriveSyncFolder.readFormatVersion
  changesets/     one folder per device (CRDT node id), holding that device's changeset files
  files/          content-addressed files, flat
```

Only folders the app created itself are visible to it (`drive.file`), so the subfolders must not be created by hand in the Drive web UI - moving folders the app created is fine.

Uploads go as one multipart request below 5 MB and through Drive's resumable protocol from there on. A file is read into a Blob before uploading, since not every platform's `fetch` takes a stream as request body.

## Usage

```ts
const folder = new GoogleDriveSyncFolder({ fetch: platform.fetch, accessToken: () => auth.accessToken() });
// folder.changesets, folder.files, folder.readFormatVersion()
```

`@turtle-base/crdt-file-sync-google-drive/testing` has `FakeDrive`, an in-memory stand-in for the Drive REST API - pass its `fetch` to test code syncing through Drive without a network.
