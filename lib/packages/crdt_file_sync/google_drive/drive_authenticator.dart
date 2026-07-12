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
/// `.local/GOOGLE_DRIVE_SETUP.md` step 3) - Android resolves its OAuth
/// client automatically from the app's package name + signing certificate.
DriveAuthenticator createDriveAuthenticator({
  required ClientId desktopClientId,
  List<String> scopes = const [DriveApi.driveFileScope],
}) {
  if (Platform.isAndroid) {
    return AndroidDriveAuthenticator(scopes: scopes);
  }
  if (Platform.isLinux) {
    return DesktopDriveAuthenticator(clientId: desktopClientId, scopes: scopes);
  }
  throw UnsupportedError('No DriveAuthenticator for this platform - see AGENTS.md\'s supported platforms.');
}
