/**
 * Google sign-in for Drive sync (`drive.file` scope), behind one interface
 * for the platform-specific flows: a loopback consent flow on the desktop,
 * native Google Sign-In on Android.
 */
export interface GoogleAuthenticator {
  /** Restores a previous sign-in without prompting, e.g. on app start. False if there's none. */
  signInSilently(): Promise<boolean>;

  /** Prompts the user through the consent flow. */
  signIn(): Promise<void>;

  /** Forgets the stored session (if any). */
  signOut(): Promise<void>;

  /** A valid access token, refreshed when needed. Rejects when not signed in. */
  accessToken(): Promise<string>;
}
