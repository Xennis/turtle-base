import 'dart:typed_data';

/// A minimal file-storage abstraction that `SyncController` uses to
/// exchange CRDT changesets between devices.
///
/// Implementations are expected to be dumb, flat file storage - no
/// merge logic, no knowledge of CRDTs. `name` is an opaque identifier
/// chosen by the caller (`SyncController` encodes a `<nodeId>/<file>`
/// path convention into it); implementations only need to round-trip
/// whatever string they're given.
abstract class SyncTransport {
  /// Uploads [bytes] under [name], creating it if it doesn't exist yet.
  Future<void> upload(String name, Uint8List bytes);

  /// Lists the names of all files currently stored, from every device.
  Future<List<String>> list();

  /// Downloads the file previously uploaded as [name].
  Future<Uint8List> download(String name);
}

/// Flat storage for content-addressed files (images, attachments) that
/// `FileSyncController` shares between devices.
///
/// Streamed rather than [Uint8List]-based like [SyncTransport], since
/// files can be far larger than a changeset. Names are chosen by the
/// caller and unique per content, so uploading a name that already
/// exists is harmless.
abstract class FileTransport {
  /// Uploads [length] bytes from [bytes] under [name].
  Future<void> upload(String name, Stream<List<int>> bytes, int length);

  /// The names of all files currently stored.
  Future<Set<String>> list();

  /// Streams the file previously uploaded as [name].
  Stream<List<int>> download(String name);
}
