# crdt_file_sync_transport

The `SyncTransport` interface: a minimal flat file storage that turtle-base's CRDT file sync uses to exchange changesets between devices. Storage adapters (e.g. [crdt_file_sync_google_drive](../crdt_file_sync_google_drive)) implement it; the sync logic itself lives in the app.
