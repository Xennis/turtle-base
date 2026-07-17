/// OAuth client identifiers for Google Drive sync, injected at build time
/// via `--dart-define` - see README.md's "Google Drive sync configuration"
/// section for the variable names and `ops/infra/README.md` for how to
/// obtain the values. Left blank (empty string) when not supplied, in
/// which case `createDriveAuthenticator` disables the feature - see
/// `drive_authenticator.dart`.
class DriveClientConfig {
  const DriveClientConfig._();

  /// "Desktop app" OAuth client, used by [DesktopDriveAuthenticator]'s
  /// loopback consent flow. Not confidential for installed apps (see
  /// RFC 8252) - safe to ship in the app binary, but still kept out of
  /// version control since it's specific to whoever registered it.
  static const desktopClientId = String.fromEnvironment('DRIVE_DESKTOP_CLIENT_ID');
  static const desktopClientSecret = String.fromEnvironment('DRIVE_DESKTOP_CLIENT_SECRET');

  /// "Web application" OAuth client, passed as `serverClientId` to
  /// `GoogleSignIn.instance.initialize()`. `google_sign_in`'s Credential
  /// Manager-based Android flow requires this unconditionally, even though
  /// this app never uses server-side/offline access - see
  /// AndroidDriveAuthenticator's doc comment.
  ///
  /// The Android-type client (package name + signing certificate
  /// fingerprint) has no counterpart here - `google_sign_in` resolves it
  /// automatically, nothing to reference at runtime.
  static const androidServerClientId = String.fromEnvironment('DRIVE_ANDROID_SERVER_CLIENT_ID');
}
