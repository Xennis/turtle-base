# @turtle-base/crdt-file-sync-transport

The `SyncTransport` and `FileTransport` interfaces: minimal flat file storage that turtle-base's CRDT file sync uses to exchange changesets and attachments between devices. Storage adapters (e.g. [crdt-file-sync-google-drive](../crdt-file-sync-google-drive)) implement them; the sync logic itself lives in the app.
