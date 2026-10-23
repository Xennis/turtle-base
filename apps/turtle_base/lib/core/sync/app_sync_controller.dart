import 'package:crdt_file_sync_google_drive/crdt_file_sync_google_drive.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';
import 'package:turtle_base/core/sync/shared_preferences_sync_state_store.dart';
import 'package:turtle_base/core/sync/sync_format.dart';
import 'package:turtle_base/features/files/data/attachments_repository.dart';
import 'package:turtle_base/packages/crdt_file_sync/file_sync_controller.dart';
import 'package:turtle_base/packages/crdt_file_sync/sync_controller.dart';
import 'package:turtle_base/packages/file_store/file_store.dart';

/// Owns the connect/disconnect lifecycle for Google Drive sync and the
/// [SyncController] and [FileSyncController] it produces once connected -
/// the one place that wires `lib/packages/crdt_file_sync/`
/// (transport-agnostic) up with this app's [DriveAuthenticator],
/// [SqliteCrdt] instance and attachments (see ARCHITECTURE.md's "Sync
/// zwischen Geräten" and `.local/FILES.md`).
class AppSyncController extends ChangeNotifier {
  AppSyncController({
    required this._crdt,
    required this._authenticator,
    required this._files,
    required this._attachments,
    required this._prefs,
    this.appFolderName = 'turtle-base-sync',
  });

  static const _keepAllFilesOfflineKey = 'keep_all_files_offline';

  final SqliteCrdt _crdt;
  final DriveAuthenticator? _authenticator;
  final FileStore _files;
  final AttachmentsRepository _attachments;
  final SharedPreferences _prefs;
  final String appFolderName;

  GoogleDriveSyncFolder? _folder;
  SyncController? _sync;
  FileSyncController? _fileSync;

  /// Set when the last sync failed outside [SyncController] - e.g. on a
  /// [SyncFormatTooNewException], or listing the files folder.
  Object? _error;

  /// While files are uploaded or downloaded around [SyncController]'s
  /// own run.
  bool _syncingFiles = false;

  /// Whether an OAuth client was configured for this platform (see
  /// `createDriveAuthenticator`) - false hides the Drive sync UI entirely
  /// rather than showing a feature that can never connect.
  bool get isAvailable => _authenticator != null;

  bool get isConnected => _sync != null;
  SyncStatus get status {
    if (_error != null) return SyncStatus.error;
    if (_syncingFiles) return SyncStatus.syncing;
    return _sync?.status ?? SyncStatus.idle;
  }

  DateTime? get lastSyncedAt => _sync?.lastSyncedAt;
  Object? get lastError => _error ?? _sync?.lastError;

  /// Files the last sync couldn't upload or download - retried next time.
  int get failedFileCount => _failedFileCount;
  int _failedFileCount = 0;

  /// Per device, not synced: download every file's original on sync
  /// rather than only when it's opened. On by default on desktop, where
  /// storage is rarely the constraint, off on mobile.
  bool get keepAllFilesOffline =>
      _prefs.getBool(_keepAllFilesOfflineKey) ?? defaultTargetPlatform != TargetPlatform.android;

  Future<void> setKeepAllFilesOffline(bool value) async {
    await _prefs.setBool(_keepAllFilesOfflineKey, value);
    notifyListeners();
  }

  /// Restores a previous connection without prompting - call once at app
  /// start. A no-op (stays disconnected) if there's nothing to restore or
  /// if Drive sync isn't [isAvailable].
  Future<void> restoreConnection() async {
    final authenticator = _authenticator;
    if (authenticator == null) return;
    final client = await authenticator.signInSilently();
    if (client != null) {
      _attach(GoogleDriveSyncFolder(authClient: client, name: appFolderName));
    }
  }

  /// Prompts the user through the OAuth consent flow. Only call when
  /// [isAvailable] - the Settings UI hides the "Connect" button otherwise.
  Future<void> connect() async {
    final client = await _authenticator!.signIn();
    _attach(GoogleDriveSyncFolder(authClient: client, name: appFolderName));
  }

  Future<void> disconnect() async {
    await _authenticator?.signOut();
    _sync?.removeListener(notifyListeners);
    _sync = null;
    _fileSync = null;
    _folder = null;
    _error = null;
    notifyListeners();
  }

  /// Format check, then files up, changesets, files down - uploading
  /// files before the changesets referencing them, so another device
  /// rarely sees an attachment whose file isn't there yet.
  ///
  /// The format is checked on every sync rather than once per
  /// connection - another device may have bumped it since.
  Future<void> syncNow() async {
    final folder = _folder;
    final sync = _sync;
    final fileSync = _fileSync;
    if (folder == null || sync == null || fileSync == null) return;
    _error = null;
    _syncingFiles = true;
    notifyListeners();
    try {
      await ensureSyncFormat(read: folder.readFormatVersion, write: folder.writeFormatVersion);
      // Deleted attachments too - they can be restored.
      var failed = await fileSync.push(await _attachments.fileHashes(activeOnly: false));
      await sync.syncNow();
      if (sync.status != SyncStatus.error) {
        failed += await fileSync.pull(await _attachments.fileHashes(activeOnly: true), originals: keepAllFilesOffline);
      }
      _failedFileCount = failed;
    } catch (e) {
      debugPrint('[sync] syncNow() failed: $e');
      _error = e;
    } finally {
      _syncingFiles = false;
      notifyListeners();
    }
  }

  /// Downloads a file the store doesn't have yet, e.g. an original when
  /// it's opened. False when not connected or the download failed.
  Future<bool> fetchFile(String name) async {
    if (_files.fileOf(name).existsSync()) return true;
    return await _fileSync?.fetch(name) ?? false;
  }

  void _attach(GoogleDriveSyncFolder folder) {
    _sync?.removeListener(notifyListeners);
    _folder = folder;
    _error = null;
    _sync = SyncController(_crdt, folder.changesets, state: SharedPreferencesSyncStateStore(_prefs))
      ..addListener(notifyListeners);
    _fileSync = FileSyncController(_files, folder.files);
    notifyListeners();
  }
}
