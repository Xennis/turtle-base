import type { FileTransport, SyncTransport } from '@turtle-base/crdt-file-sync-transport';
import * as v from 'valibot';

import { DriveClient } from './drive-client.ts';
import { DriveFolders } from './drive-folders.ts';
import { GoogleDriveFileTransport } from './google-drive-file-transport.ts';
import { blobOf, GoogleDriveTransport } from './google-drive-transport.ts';

export const formatFileName = 'format.json';

const formatSchema = v.object({ version: v.number() });

/**
 * The app's sync data in Google Drive, using only `drive.file`-scoped calls
 * (files the app itself created) - see the README.
 *
 * Layout: one folder `name` at the Drive root, holding
 *
 * ```
 * format.json     {"version": <n>}, see readFormatVersion
 * changesets/     <nodeId>/<file>, see changesets
 * files/          flat, see files
 * ```
 */
export class GoogleDriveSyncFolder {
  readonly name: string;
  readonly changesets: SyncTransport;
  readonly files: FileTransport;
  readonly #folders: DriveFolders;

  constructor(options: { fetch: typeof fetch; accessToken: () => Promise<string>; name?: string }) {
    this.name = options.name ?? 'turtle-base-sync';
    this.#folders = new DriveFolders(new DriveClient(options));
    this.changesets = new GoogleDriveTransport(this.#folders, [this.name, 'changesets']);
    this.files = new GoogleDriveFileTransport(this.#folders, [this.name, 'files']);
  }

  /**
   * The layout version stored in {@link formatFileName}, undefined if there is
   * none yet. The app compares it against its own to refuse syncing data a
   * newer app version wrote.
   */
  async readFormatVersion(): Promise<number | undefined> {
    const file = await this.#formatFile();
    if (file === undefined) return undefined;
    const json: unknown = await new Response(await this.#folders.client.download(file.id)).json();
    const parsed = v.safeParse(formatSchema, json);
    return parsed.success ? parsed.output.version : undefined;
  }

  async writeFormatVersion(version: number): Promise<void> {
    const content = blobOf(new TextEncoder().encode(JSON.stringify({ version })));
    const existing = await this.#formatFile();
    if (existing !== undefined) {
      await this.#folders.client.updateFile(existing.id, content);
      return;
    }
    await this.#folders.client.createFile(formatFileName, await this.#folders.resolve([this.name]), content);
  }

  async #formatFile() {
    const rootId = await this.#folders.resolve([this.name]);
    const [file] = await this.#folders.childFiles(rootId, formatFileName);
    return file;
  }
}
