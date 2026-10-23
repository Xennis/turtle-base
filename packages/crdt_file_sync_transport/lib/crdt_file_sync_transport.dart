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
