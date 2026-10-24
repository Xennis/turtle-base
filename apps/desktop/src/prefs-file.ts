import { readFileSync, renameSync, writeFileSync } from 'node:fs';

/** Device-local settings as one JSON file, written whole through a temporary file. */
export class PrefsFile {
  readonly #path: string;
  readonly #values: Record<string, string>;

  constructor(path: string) {
    this.#path = path;
    this.#values = readJsonObject(path);
  }

  all(): Record<string, string> {
    return { ...this.#values };
  }

  set(key: string, value: string): void {
    this.#values[key] = value;
    this.#write();
  }

  remove(key: string): void {
    delete this.#values[key];
    this.#write();
  }

  #write(): void {
    writeFileSync(`${this.#path}.tmp`, JSON.stringify(this.#values, null, 2));
    renameSync(`${this.#path}.tmp`, this.#path);
  }
}

/** The string entries of the JSON object in `path` - empty when there is none (yet). */
export function readJsonObject(path: string): Record<string, string> {
  try {
    const json: unknown = JSON.parse(readFileSync(path, 'utf8'));
    if (typeof json !== 'object' || json === null) return {};
    return Object.fromEntries(
      Object.entries(json).filter((entry): entry is [string, string] => typeof entry[1] === 'string'),
    );
  } catch {
    return {};
  }
}
