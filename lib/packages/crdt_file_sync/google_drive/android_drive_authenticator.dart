import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' show DriveApi;
import 'package:googleapis_auth/googleapis_auth.dart';

import 'drive_authenticator.dart';

/// Android OAuth flow via the platform-native `google_sign_in` plugin -
/// its own OAuth client is resolved automatically from the app's package
/// name + signing certificate fingerprint (see
/// `.local/GOOGLE_DRIVE_SETUP.md` step 4), no client id/secret needed here.
///
/// `google_sign_in` (not `googleapis_auth`) owns session persistence and
/// token refresh on this platform - nothing extra to store.
class AndroidDriveAuthenticator implements DriveAuthenticator {
  AndroidDriveAuthenticator({this.scopes = const [DriveApi.driveFileScope]});

  final List<String> scopes;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize();
    _initialized = true;
  }

  @override
  Future<AuthClient?> signInSilently() async {
    await _ensureInitialized();
    final future = GoogleSignIn.instance.attemptLightweightAuthentication();
    final account = future == null ? null : await future;
    if (account == null) return null;

    final authorization = await account.authorizationClient.authorizationForScopes(scopes);
    if (authorization == null) return null;
    return authorization.authClient(scopes: scopes);
  }

  @override
  Future<AuthClient> signIn() async {
    await _ensureInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    final authorization = await account.authorizationClient.authorizeScopes(scopes);
    return authorization.authClient(scopes: scopes);
  }

  @override
  Future<void> signOut() async {
    await _ensureInitialized();
    await GoogleSignIn.instance.disconnect();
  }
}
