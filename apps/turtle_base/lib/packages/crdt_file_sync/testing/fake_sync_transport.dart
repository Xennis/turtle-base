import 'dart:typed_data';

import 'package:crdt_file_sync_transport/crdt_file_sync_transport.dart';

/// In-memory [SyncTransport] for tests - no network, no disk.
class FakeSyncTransport implements SyncTransport {
  final Map<String, Uint8List> _files = {};

  /// Names whose download throws, to simulate failures.
  final Set<String> failingDownloads = {};

  /// Every download in order, also failed ones.
  final List<String> downloads = [];

  @override
  Future<void> upload(String name, Uint8List bytes) async {
    _files[name] = bytes;
  }

  @override
  Future<List<String>> list() async => _files.keys.toList();

  @override
  Future<Uint8List> download(String name) async {
    downloads.add(name);
    final bytes = _files[name];
    if (bytes == null || failingDownloads.contains(name)) {
      throw StateError('FakeSyncTransport: no file named "$name"');
    }
    return bytes;
  }
}
