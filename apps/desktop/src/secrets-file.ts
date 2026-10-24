import { renameSync, writeFileSync } from 'node:fs';

import { safeStorage } from 'electron';

import { readJsonObject } from './prefs-file.ts';

/**
 * Secrets encrypted by the OS keyring through Electron's `safeStorage`
 * (libsecret on Linux, Keychain on macOS), kept as base64 in one file.
 */
export class SecretsFile {
  readonly #path: string;

  constructor(path: string) {
    this.#path = path;
  }

  get(key: string): string | undefined {
    const encrypted = readJsonObject(this.#path)[key];
    return encrypted === undefined ? undefined : safeStorage.decryptString(Buffer.from(encrypted, 'base64'));
  }

  set(key: string, value: string): void {
    if (!safeStorage.isEncryptionAvailable()) throw new Error('No OS keyring to encrypt secrets with');
    this.#write({ ...readJsonObject(this.#path), [key]: safeStorage.encryptString(value).toString('base64') });
  }

  remove(key: string): void {
    const values = readJsonObject(this.#path);
    delete values[key];
    this.#write(values);
  }

  #write(values: Record<string, string>): void {
    writeFileSync(`${this.#path}.tmp`, JSON.stringify(values));
    renameSync(`${this.#path}.tmp`, this.#path);
  }
}
