import 'package:googleapis_auth/googleapis_auth.dart';

import 'src/drive_authenticator.dart';

/// A [DriveAuthenticator] that never actually reaches Google - stands in
/// for widget tests that need *a* controller wired up (so SyncScope has
/// something to provide) without exercising real OAuth.
class FakeDriveAuthenticator implements DriveAuthenticator {
  @override
  Future<AuthClient?> signInSilently() async => null;

  @override
  Future<AuthClient> signIn() {
    throw UnimplementedError('FakeDriveAuthenticator does not support signIn()');
  }

  @override
  Future<void> signOut() async {}
}
