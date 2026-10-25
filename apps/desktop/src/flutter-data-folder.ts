import { existsSync, readdirSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

import type { SqlRow } from '@turtle-base/platform';

const databaseName = 'turtle_base.sqlite';

/** Only names of the Flutter app's file store - nothing else of the disk is handed out. */
const storeName = /^sha256-[0-9a-f]{64}(\.thumb\.jpg)?$/;

/**
 * Where the Flutter app keeps its data on this machine (path_provider's
 * application support directory): the XDG data folder on Linux; on macOS
 * its sandbox container, or Application Support where it ran unsandboxed.
 * `TURTLE_FLUTTER_DATA_DIR` points elsewhere, e.g. for tests.
 */
function candidates(): string[] {
  const override = process.env['TURTLE_FLUTTER_DATA_DIR'];
  if (override !== undefined) return [override];
  const home = homedir();
  if (process.platform === 'darwin') {
    const support = join('Library', 'Application Support', 'org.xennis.apps.turtleBase');
    return [join(home, 'Library', 'Containers', 'org.xennis.apps.turtleBase', 'Data', support), join(home, support)];
  }
  return [join(process.env['XDG_DATA_HOME'] ?? join(home, '.local', 'share'), 'org.xennis.apps.turtle_base')];
}

/** The Flutter app's database and files, opened read-only - for the one-time import. */
export class FlutterDataFolder {
  readonly location: string;
  #database: DatabaseSync | undefined;

  private constructor(location: string) {
    this.location = location;
  }

  static find(): FlutterDataFolder | undefined {
    const location = candidates().find((folder) => existsSync(join(folder, databaseName)));
    return location === undefined ? undefined : new FlutterDataFolder(location);
  }

  query(sql: string): SqlRow[] {
    if (!/^\s*select\b/i.test(sql)) throw new Error('Only SELECTs on the Flutter app database');
    this.#database ??= new DatabaseSync(join(this.location, databaseName), { readOnly: true });
    // oxlint-disable-next-line typescript/no-unsafe-type-assertion -- node:sqlite rows hold only SQLite values
    return this.#database.prepare(sql).all();
  }

  listFiles(): string[] {
    const folder = join(this.location, 'files');
    if (!existsSync(folder)) return [];
    return readdirSync(folder, { withFileTypes: true })
      .filter((entry) => entry.isFile() && storeName.test(entry.name))
      .map((entry) => entry.name);
  }

  async readFile(name: string): Promise<Uint8Array> {
    if (!storeName.test(name)) throw new Error(`Not a file of the Flutter app: ${name}`);
    return new Uint8Array(await readFile(join(this.location, 'files', name)));
  }
}
