import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';
import 'package:turtle_base/packages/crdt_file_sync/sync_state_store.dart';

/// Persists [SyncStateStore] across app restarts - per device, like the
/// theme mode (see ThemeController).
class SharedPreferencesSyncStateStore implements SyncStateStore {
  SharedPreferencesSyncStateStore(this._prefs);

  final SharedPreferences _prefs;

  static String _lastPushedAtKey(String nodeId) => 'sync.$nodeId.last_pushed_at';
  static String _mergedFilesKey(String nodeId) => 'sync.$nodeId.merged_files';

  @override
  Hlc? lastPushedAt(String nodeId) => _prefs.getString(_lastPushedAtKey(nodeId))?.toHlc;

  @override
  Future<void> setLastPushedAt(String nodeId, Hlc hlc) => _prefs.setString(_lastPushedAtKey(nodeId), hlc.toString());

  @override
  Set<String> mergedFiles(String nodeId) => {...?_prefs.getStringList(_mergedFilesKey(nodeId))};

  @override
  Future<void> setMergedFiles(String nodeId, Set<String> names) =>
      _prefs.setStringList(_mergedFilesKey(nodeId), names.toList());
}
