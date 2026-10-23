import 'package:crdt_file_sync_transport/crdt_file_sync_transport.dart';
import 'package:flutter/foundation.dart';
import 'package:turtle_base/packages/file_store/file_store.dart';

/// Shares a [FileStore]'s files between devices through a flat
/// [FileTransport] - the counterpart to [SyncController] for the bytes
/// the changesets only reference by hash.
///
/// Which files to share is the caller's call ([push]/[pull] take the
/// hashes), so this knows nothing of attachments. Every name is unique
/// per content, so there's nothing to merge: a file is either there or
/// not, and uploading or downloading it twice is only wasted bandwidth.
class FileSyncController {
  FileSyncController(this._store, this._transport);

  final FileStore _store;
  final FileTransport _transport;

  final _fetches = <String, Future<bool>>{};

  /// Uploads the originals and thumbnails of [hashes] that this device
  /// has and the transport doesn't. Returns how many failed - a failure
  /// doesn't stop the others, the next sync retries it.
  Future<int> push(Set<String> hashes) async {
    final remote = await _transport.list();
    final local = await _store.names();
    var failed = 0;
    for (final name in _namesOf(hashes)) {
      if (!local.contains(name) || remote.contains(name)) continue;
      try {
        final file = _store.fileOf(name);
        debugPrint('[sync] files: uploading $name');
        await _transport.upload(name, file.openRead(), await file.length());
      } catch (e) {
        debugPrint('[sync] files: upload of $name failed: $e');
        failed++;
      }
    }
    return failed;
  }

  /// Downloads the thumbnails of [hashes] - and with [originals] the
  /// files themselves - that the transport has and this device doesn't.
  /// Returns how many failed, like [push].
  Future<int> pull(Set<String> hashes, {required bool originals}) async {
    final remote = await _transport.list();
    final local = await _store.names();
    var failed = 0;
    for (final hash in hashes) {
      for (final name in [FileStore.thumbnailNameOf(hash), if (originals) hash]) {
        if (local.contains(name) || !remote.contains(name)) continue;
        if (!await _download(name)) failed++;
      }
    }
    return failed;
  }

  /// Downloads one file on demand, e.g. an original when it's opened.
  /// Concurrent calls for the same name share one download. True when
  /// the file is in the store afterwards.
  Future<bool> fetch(String name) {
    if (_store.fileOf(name).existsSync()) return Future.value(true);
    // A block body: returning the removed future from whenComplete
    // would make it wait for itself.
    return _fetches[name] ??= _download(name).whenComplete(() {
      _fetches.remove(name);
    });
  }

  Future<bool> _download(String name) async {
    try {
      debugPrint('[sync] files: downloading $name');
      await _store.put(name, _transport.download(name));
      return true;
    } catch (e) {
      debugPrint('[sync] files: download of $name failed: $e');
      return false;
    }
  }

  Iterable<String> _namesOf(Set<String> hashes) sync* {
    for (final hash in hashes) {
      yield hash;
      yield FileStore.thumbnailNameOf(hash);
    }
  }
}
