import type { FileDirectory } from './file-directory.ts';
import type { FlutterAppData } from './flutter-app-data.ts';
import type { GoogleAuthenticator } from './google-authenticator.ts';
import type { KeyValueStore, SecretStorage } from './key-value-store.ts';
import type { SqlDriver } from './sql-driver.ts';

/**
 * Everything the app needs from the platform it runs on. The app only talks
 * to this interface; Electron and Capacitor each implement it.
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
   * Lets the user pick files, e.g. to attach. Empty when cancelled. `accept`
   * lists extensions (without dot) the dialog filters by, undefined for any;
   * `imagesOnly` lets a phone offer its gallery.
   */
  pickFiles(options: PickFilesOptions): Promise<PickedFile[]>;

  /**
   * Opens a file of {@link files} with the system's app for it, under
   * `displayName` (the store names files by hash). Rejects when there's no
   * app for it.
   */
  openFile(name: string, displayName: string): Promise<void>;

  /**
   * The Flutter app's data on this device, for the one-time import - only
   * on the desktop, and only where the Flutter app was used. Undefined
   * otherwise.
   */
  findFlutterAppData(): Promise<FlutterAppData | undefined>;

  /**
   * Matches what the system draws around the page to the app's theme: the
   * desktop window's buttons (the page draws the title bar itself) and
   * Android's status and navigation bars (the page lies behind them).
   */
  matchWindowChrome(colors: WindowChromeColors): Promise<void>;

  /**
   * Undefined when no OAuth client was configured for this platform - the
   * app then hides Drive sync rather than offering a feature that can never
   * connect.
   */
  readonly googleAuth: GoogleAuthenticator | undefined;
}

export interface WindowChromeColors {
  readonly dark: boolean;
  /** As `#rrggbb`. */
  readonly background: string;
  readonly foreground: string;
}

export interface PickFilesOptions {
  readonly multiple: boolean;
  readonly extensions?: readonly string[] | undefined;
  readonly imagesOnly?: boolean;
}

export interface PickedFile {
  readonly name: string;
  readonly bytes: ReadableStream<Uint8Array>;
}
