import 'dart:typed_data';

import 'package:turtle_base/packages/crdt_file_sync/sync_transport.dart';

/// In-memory [SyncTransport] for tests - no network, no disk.
class FakeSyncTransport implements SyncTransport {
  final Map<String, Uint8List> _files = {};

  @override
  Future<void> upload(String name, Uint8List bytes) async {
    _files[name] = bytes;
  }

  @override
  Future<List<String>> list() async => _files.keys.toList();

  @override
  Future<Uint8List> download(String name) async {
    final bytes = _files[name];
    if (bytes == null) {
      throw StateError('FakeSyncTransport: no file named "$name"');
    }
    return bytes;
  }
}
