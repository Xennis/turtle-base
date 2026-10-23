import 'dart:convert';

import 'package:crdt_file_sync_transport/crdt_file_sync_transport.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';
import 'package:turtle_base/packages/crdt_file_sync/sync_state_store.dart';

enum SyncStatus { idle, syncing, error }

/// Push/pull/merge engine that keeps a local [SqliteCrdt] in sync with
/// others through an opaque [SyncTransport].
///
/// Every device pushes its own changesets under a folder-like prefix
/// named after `crdt.nodeId` (stable per database, see
/// `SqlCrdt.init`/`resetNodeId`), and pulls+merges every other device's
/// prefix. Merging is idempotent (`sql_crdt`'s `merge()` only applies a
/// record if its hlc is newer than what's stored), so re-downloading a
/// file that was already merged is wasted bandwidth but never wrong.
/// What was pushed survives restarts through [SyncStateStore], see
/// `.local/SYNC_COMPACTION.md`.
///
/// `syncNow()` is the only entry point, so a future background trigger
/// (timer, app lifecycle hook) can call the exact same method a manual
/// "sync now" button uses today.
class SyncController extends ChangeNotifier {
  SyncController(this._crdt, this._transport, {SyncStateStore? state}) : _state = state ?? InMemorySyncStateStore();

  final SqliteCrdt _crdt;
  final SyncTransport _transport;
  final SyncStateStore _state;

  SyncStatus status = SyncStatus.idle;
  DateTime? lastSyncedAt;
  Object? lastError;

  Future<void> syncNow() async {
    status = SyncStatus.syncing;
    lastError = null;
    notifyListeners();

    debugPrint('[sync] syncNow() starting - own nodeId=${_crdt.nodeId}');
    try {
      // Listed once, before pushing - the pull skips own files anyway.
      final names = await _transport.list();
      await _push(names);
      await _pull(names);
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

  /// Uploads own changes since the last push - or everything, when
  /// [listed] has no own file (first sync, or the own folder was removed
  /// or moved), since then nothing pushed before is still there.
  Future<void> _push(List<String> listed) async {
    final nodeId = _crdt.nodeId;
    final hasOwnFile = listed.any((name) => name.startsWith('$nodeId/'));
    final since = hasOwnFile ? _state.lastPushedAt(nodeId) : null;

    // `onlyNodeId` is essential here, not just an optimization: merging a
    // remote changeset stamps `modified` with *our own* node id (see
    // sql_crdt's `Hlc.merge`), so a plain `modifiedAfter` filter would
    // pick up records we just pulled from someone else and re-upload
    // them under our own file - not wrong on its own, but combined with
    // the push state below (also scoped to our own node id, so it
    // wouldn't advance) it would keep re-generating the *same* filename
    // and silently overwrite our own previous upload with a payload
    // that's missing our own data.
    final changeset = await _crdt.getChangeset(onlyNodeId: nodeId, modifiedAfter: since);
    if (changeset.recordCount == 0) {
      debugPrint('[sync] push: nothing new since $since');
      return;
    }

    final pushedAt = await _crdt.getLastModified(onlyNodeId: nodeId);
    final name = '$nodeId/${_fileNameFor(pushedAt)}';
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(changeset)));
    debugPrint('[sync] push: uploading $name (${changeset.recordCount} records)');
    await _transport.upload(name, bytes);
    // Only after the upload - a failure in between means uploading
    // again, never losing a change.
    await _state.setLastPushedAt(nodeId, pushedAt);
  }

  Future<void> _pull(List<String> names) async {
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
  static String _fileNameFor(Hlc hlc) => '${hlc.dateTime.microsecondsSinceEpoch}-${hlc.counter}.json';
}
