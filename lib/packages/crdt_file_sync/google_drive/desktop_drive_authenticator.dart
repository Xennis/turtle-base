import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/drive/v3.dart' show DriveApi;
import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart';

import 'drive_authenticator.dart';

/// Desktop (Linux) OAuth flow: the "installed app" loopback pattern - a
/// local `127.0.0.1` server on an arbitrary free port catches the redirect
/// after the user approves access in their normal browser. There is no
/// platform-native `google_sign_in` support for Linux (see
/// `.local/GOOGLE_DRIVE_SETUP.md`), so `googleapis_auth`'s
/// `clientViaUserConsent` drives the whole flow directly.
///
/// The resulting refresh token is the only thing persisted (in the
/// platform keyring via [FlutterSecureStorage], not plain prefs) - it's
/// enough to silently mint new access tokens on the next app start via
/// `clientViaRefreshToken`, without repeating the browser consent step.
class DesktopDriveAuthenticator implements DriveAuthenticator {
  DesktopDriveAuthenticator({
    required this.clientId,
    this.scopes = const [DriveApi.driveFileScope],
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  static const _refreshTokenKey = 'crdt_file_sync.google_drive.refresh_token';

  final ClientId clientId;
  final List<String> scopes;
  final FlutterSecureStorage _storage;

  @override
  Future<AuthClient?> signInSilently() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) return null;
    return clientViaRefreshToken(clientId, refreshToken, scopes);
  }

  @override
  Future<AuthClient> signIn() async {
    final client = await clientViaUserConsent(clientId, scopes, _promptUser);
    final refreshToken = client.credentials.refreshToken;
    if (refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
    return client;
  }

  @override
  Future<void> signOut() => _storage.delete(key: _refreshTokenKey);

  void _promptUser(String url) {
    launchUrl(Uri.parse(url));
  }
}
