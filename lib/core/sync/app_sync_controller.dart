import 'package:flutter/foundation.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';
import 'package:turtle_base/packages/crdt_file_sync/google_drive/drive_authenticator.dart';
import 'package:turtle_base/packages/crdt_file_sync/google_drive/google_drive_transport.dart';
import 'package:turtle_base/packages/crdt_file_sync/sync_controller.dart';

/// Owns the connect/disconnect lifecycle for Google Drive sync and the
/// [SyncController] it produces once connected - the one place that wires
/// `lib/packages/crdt_file_sync/` (transport-agnostic) up with this app's
/// [DriveAuthenticator] and [SqliteCrdt] instance (see
/// ARCHITECTURE.md's "Sync zwischen Geräten").
class AppSyncController extends ChangeNotifier {
  AppSyncController({
    required this._crdt,
    required this._authenticator,
    this.appFolderName = 'turtle-base-sync',
  });

  final SqliteCrdt _crdt;
  final DriveAuthenticator? _authenticator;
  final String appFolderName;

  SyncController? _sync;

  /// Whether an OAuth client was configured for this platform (see
  /// `createDriveAuthenticator`) - false hides the Drive sync UI entirely
  /// rather than showing a feature that can never connect.
  bool get isAvailable => _authenticator != null;

  bool get isConnected => _sync != null;
  SyncStatus get status => _sync?.status ?? SyncStatus.idle;
  DateTime? get lastSyncedAt => _sync?.lastSyncedAt;
  Object? get lastError => _sync?.lastError;

  /// Restores a previous connection without prompting - call once at app
  /// start. A no-op (stays disconnected) if there's nothing to restore or
  /// if Drive sync isn't [isAvailable].
  Future<void> restoreConnection() async {
    final authenticator = _authenticator;
    if (authenticator == null) return;
    final client = await authenticator.signInSilently();
    if (client != null) {
      _attach(GoogleDriveTransport(authClient: client, appFolderName: appFolderName));
    }
  }

  /// Prompts the user through the OAuth consent flow. Only call when
  /// [isAvailable] - the Settings UI hides the "Connect" button otherwise.
  Future<void> connect() async {
    final client = await _authenticator!.signIn();
    _attach(GoogleDriveTransport(authClient: client, appFolderName: appFolderName));
  }

  Future<void> disconnect() async {
    await _authenticator?.signOut();
    _sync?.removeListener(notifyListeners);
    _sync = null;
    notifyListeners();
  }

  Future<void> syncNow() async {
    await _sync?.syncNow();
  }

  void _attach(GoogleDriveTransport transport) {
    _sync?.removeListener(notifyListeners);
    _sync = SyncController(_crdt, transport)..addListener(notifyListeners);
    notifyListeners();
  }
}
