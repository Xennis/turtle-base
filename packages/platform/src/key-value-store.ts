/**
 * Small device-local values, never synced - settings like the theme, or what
 * sync remembers between runs.
 */
export interface KeyValueStore {
  get(key: string): string | undefined;
  set(key: string, value: string): Promise<void>;
  remove(key: string): Promise<void>;
}

/**
 * Like {@link KeyValueStore}, but encrypted by the OS (libsecret, Keychain,
 * Keystore) - for API keys and OAuth tokens.
 */
export interface SecretStorage {
  get(key: string): Promise<string | undefined>;
  set(key: string, value: string): Promise<void>;
  remove(key: string): Promise<void>;
}
