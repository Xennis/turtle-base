import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';

import 'sync_transport.dart';

enum SyncStatus { idle, syncing, error }

/// Push/pull/merge engine that keeps a local [SqliteCrdt] in sync with
/// others through an opaque [SyncTransport].
///
/// Every device pushes its own changesets under a folder-like prefix
/// named after `crdt.nodeId` (stable per database, see
/// `SqlCrdt.init`/`resetNodeId`), and pulls+merges every other device's
/// prefix. Merging is idempotent (`sql_crdt`'s `merge()` only applies a
/// record if its hlc is newer than what's stored), so re-downloading a
/// file that was already merged is wasted bandwidth but never wrong -
/// v1 intentionally keeps this simple and doesn't track per-file pull
/// watermarks (see `.local/ARCHITECTURE.md`'s open questions on
/// changeset retention/cleanup).
///
/// `syncNow()` is the only entry point, so a future background trigger
/// (timer, app lifecycle hook) can call the exact same method a manual
/// "sync now" button uses today.
class SyncController extends ChangeNotifier {
  SyncController(this._crdt, this._transport);

  final SqliteCrdt _crdt;
  final SyncTransport _transport;

  SyncStatus status = SyncStatus.idle;
  DateTime? lastSyncedAt;
  Object? lastError;

  Hlc? _lastPushedAt;

  Future<void> syncNow() async {
    status = SyncStatus.syncing;
    lastError = null;
    notifyListeners();

    debugPrint('[sync] syncNow() starting - own nodeId=${_crdt.nodeId}');
    try {
      await _push();
      await _pull();
      status = SyncStatus.idle;
      lastSyncedAt = DateTime.now();
      debugPrint('[sync] syncNow() done');
    } catch (e) {
      status = SyncStatus.error;
      lastError = e;
      debugPrint('[sync] syncNow() failed: $e');
    }
    notifyListeners();
  }

  Future<void> _push() async {
    // `onlyNodeId` is essential here, not just an optimization: merging a
    // remote changeset stamps `modified` with *our own* node id (see
    // sql_crdt's `Hlc.merge`), so a plain `modifiedAfter` filter would
    // pick up records we just pulled from someone else and re-upload
    // them under our own file - not wrong on its own, but combined with
    // `_lastPushedAt` below (also scoped to our own node id, so it
    // wouldn't advance) it would keep re-generating the *same* filename
    // and silently overwrite our own previous upload with a payload
    // that's missing our own data.
    final changeset = await _crdt.getChangeset(
      onlyNodeId: _crdt.nodeId,
      modifiedAfter: _lastPushedAt,
    );
    if (changeset.recordCount == 0) {
      debugPrint('[sync] push: nothing new since $_lastPushedAt');
      return;
    }

    final pushedAt = await _crdt.getLastModified(onlyNodeId: _crdt.nodeId);
    final name = '${_crdt.nodeId}/${_fileNameFor(pushedAt)}';
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(changeset)));
    debugPrint('[sync] push: uploading $name (${changeset.recordCount} records)');
    await _transport.upload(name, bytes);
    _lastPushedAt = pushedAt;
  }

  Future<void> _pull() async {
    final names = await _transport.list();
    debugPrint('[sync] pull: transport.list() -> $names');
    for (final name in names) {
      final slash = name.indexOf('/');
      if (slash == -1) continue;
      final nodeId = name.substring(0, slash);
      if (nodeId == _crdt.nodeId) {
        debugPrint('[sync] pull: skipping own file $name');
        continue;
      }

      debugPrint('[sync] pull: downloading+merging $name');
      final bytes = await _transport.download(name);
      final wireFormat = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      await _crdt.merge(parseCrdtChangeset(wireFormat));
      debugPrint('[sync] pull: merged $name');
    }
  }

  /// Encodes [hlc] into a filename-safe, lexically sortable string - not
  /// `Hlc.toString()`, whose `:`-separated ISO date wouldn't be a safe
  /// file/object name on every transport.
  static String _fileNameFor(Hlc hlc) =>
      '${hlc.dateTime.microsecondsSinceEpoch}-${hlc.counter}.json';
}
