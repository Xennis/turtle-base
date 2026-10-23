import 'package:sqlite_crdt/sqlite_crdt.dart';

/// What [SyncController] remembers between syncs - device-local, never
/// synced itself. Not a table: every table behind the CRDT database
/// would be part of the changesets.
///
/// Keyed by the CRDT node id, so a reset database (new node id) starts
/// from scratch instead of trusting another database's state.
abstract class SyncStateStore {
  /// The newest own change already uploaded.
  Hlc? lastPushedAt(String nodeId);

  Future<void> setLastPushedAt(String nodeId, Hlc hlc);
}

/// Forgets everything on restart - for tests, and as the default when
/// nothing persists the state.
class InMemorySyncStateStore implements SyncStateStore {
  final _lastPushedAt = <String, Hlc>{};

  @override
  Hlc? lastPushedAt(String nodeId) => _lastPushedAt[nodeId];

  @override
  Future<void> setLastPushedAt(String nodeId, Hlc hlc) async => _lastPushedAt[nodeId] = hlc;
}
