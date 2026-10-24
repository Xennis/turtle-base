import type { FileDirectory } from './file-directory.ts';
import type { GoogleAuthenticator } from './google-authenticator.ts';
import type { KeyValueStore, SecretStorage } from './key-value-store.ts';
import type { SqlDriver } from './sql-driver.ts';

/**
 * Everything the app needs from the platform it runs on. The app only talks
 * to this interface; Electron and Capacitor each implement it. It grows with
 * the features ported from the Flutter app (files, Google sign-in, ...).
 */
export interface Platform {
  readonly kind: 'desktop' | 'android';
  readonly sql: SqlDriver;
  readonly prefs: KeyValueStore;
  readonly secrets: SecretStorage;

  /** Content-addressed attachment files, see the app's FileStore. */
  readonly files: FileDirectory;

  /**
   * Runs outside the web view, so requests aren't limited by CORS. Packages
   * that reach the network take it as a parameter.
   */
  readonly fetch: typeof fetch;
  openExternal(url: string): Promise<void>;

  /**
   * Undefined when no OAuth client was configured for this platform - the
   * app then hides Drive sync rather than offering a feature that can never
   * connect.
   */
  readonly googleAuth: GoogleAuthenticator | undefined;
}
