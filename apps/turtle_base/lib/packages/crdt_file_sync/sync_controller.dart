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

  /// Downloads and merges the listed files of other devices not merged
  /// before. Changeset files never change and merging is order
  /// independent (last writer wins per row), so remembering the merged
  /// names is all it takes. A file that fails stays unmerged and is
  /// retried on the next sync, without holding up the others.
  Future<void> _pull(List<String> names) async {
    final nodeId = _crdt.nodeId;
    // Names no longer listed (deleted on the remote) are dropped, so the
    // set doesn't grow forever.
    final remembered = _state.mergedFiles(nodeId);
    final merged = remembered.intersection(names.toSet());
    if (merged.length != remembered.length) await _state.setMergedFiles(nodeId, merged);

    final pending = [
      for (final name in names)
        if (_nodeIdOf(name) case final owner? when owner != nodeId && !merged.contains(name)) name,
    ];
    final failures = <String, Object>{};
    for (final name in pending) {
      try {
        final bytes = await _transport.download(name);
        final wireFormat = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        await _crdt.merge(parseCrdtChangeset(wireFormat));
        merged.add(name);
        // After each merge - a crash later only means merging this one
        // again, which is harmless.
        await _state.setMergedFiles(nodeId, merged);
      } catch (e) {
        debugPrint('[sync] pull: $name failed: $e');
        failures[name] = e;
      }
    }
    debugPrint(
      '[sync] pull: ${names.length} file(s) listed, ${pending.length} new, '
      '${pending.length - failures.length} merged, ${failures.length} failed',
    );
    if (failures.isNotEmpty) throw ChangesetPullException(failures);
  }

  /// The device a `<nodeId>/<file>` name belongs to, null for other names.
  static String? _nodeIdOf(String name) {
    final slash = name.indexOf('/');
    return slash == -1 ? null : name.substring(0, slash);
  }

  /// Encodes [hlc] into a filename-safe, lexically sortable string - not
  /// `Hlc.toString()`, whose `:`-separated ISO date wouldn't be a safe
  /// file/object name on every transport.
  static String _fileNameFor(Hlc hlc) => '${hlc.dateTime.microsecondsSinceEpoch}-${hlc.counter}.json';
}

/// Some changesets couldn't be downloaded or merged - the others were,
/// and these are retried on the next sync.
class ChangesetPullException implements Exception {
  const ChangesetPullException(this.failures);

  /// The error per file name.
  final Map<String, Object> failures;

  @override
  String toString() {
    final count = failures.length == 1 ? '1 changeset' : '${failures.length} changesets';
    return '$count could not be merged, retried on the next sync (${failures.values.first})';
  }
}
