import 'dart:io';

import 'package:googleapis/drive/v3.dart' show DriveApi;
import 'package:googleapis_auth/googleapis_auth.dart';

import 'android_drive_authenticator.dart';
import 'desktop_drive_authenticator.dart';

/// Produces the authenticated [AuthClient] [GoogleDriveTransport] needs,
/// hiding the platform-specific OAuth flow behind one interface (see
/// `.local/GOOGLE_DRIVE_SETUP.md` for why there are two flows at all).
abstract class DriveAuthenticator {
  /// Restores a previous [signIn] without prompting - e.g. on app start.
  /// Returns null if there's nothing to restore.
  Future<AuthClient?> signInSilently();

  /// Prompts the user through the OAuth consent flow.
  Future<AuthClient> signIn();

  /// Forgets the stored session (if any).
  Future<void> signOut();
}

/// Picks the [DriveAuthenticator] implementation for the current platform.
/// [desktopClientId] is only needed on Linux (see
/// `.local/GOOGLE_DRIVE_SETUP.md` step 3). [androidServerClientId] is only
/// needed on Android - it's a separate **Web application**-type OAuth
/// client id that `google_sign_in`'s Credential Manager-based flow always
/// requires, in addition to the Android-type client Google resolves
/// automatically from the app's package name + signing certificate (see
/// `.local/GOOGLE_DRIVE_SETUP.md` step 4).
DriveAuthenticator createDriveAuthenticator({
  required ClientId desktopClientId,
  required String androidServerClientId,
  List<String> scopes = const [DriveApi.driveFileScope],
}) {
  if (Platform.isAndroid) {
    return AndroidDriveAuthenticator(serverClientId: androidServerClientId, scopes: scopes);
  }
  if (Platform.isLinux) {
    return DesktopDriveAuthenticator(clientId: desktopClientId, scopes: scopes);
  }
  throw UnsupportedError('No DriveAuthenticator for this platform - see AGENTS.md\'s supported platforms.');
}
