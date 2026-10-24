import type { SyncTransport } from '@turtle-base/crdt-file-sync-transport';

import type { DriveFolders } from './drive-folders.ts';

/**
 * {@link SyncTransport} for changesets: one subfolder per device (named after
 * its CRDT node id) below the folder at `path`, each holding that device's
 * changeset files - matching the `<nodeId>/<file>` names `SyncController`
 * uses.
 */
export class GoogleDriveTransport implements SyncTransport {
  readonly #folders: DriveFolders;
  readonly #path: readonly string[];
  readonly #fileIds = new Map<string, string>();

  constructor(folders: DriveFolders, path: readonly string[]) {
    this.#folders = folders;
    this.#path = path;
  }

  async upload(name: string, bytes: Uint8Array): Promise<void> {
    const [nodeId, fileName] = splitName(name);
    const folderId = await this.#folders.resolve([...this.#path, nodeId]);
    this.#fileIds.set(name, await this.#folders.client.createFile(fileName, folderId, blobOf(bytes)));
  }

  async list(): Promise<string[]> {
    const rootId = await this.#folders.resolve(this.#path);
    const names: string[] = [];
    for (const folder of await this.#folders.childFolders(rootId)) {
      for (const file of await this.#folders.childFiles(folder.id)) {
        const name = `${folder.name}/${file.name}`;
        this.#fileIds.set(name, file.id);
        names.push(name);
      }
    }
    return names;
  }

  async download(name: string): Promise<Uint8Array> {
    const fileId = this.#fileIds.get(name) ?? (await this.#findFileId(name));
    return new Uint8Array(await new Response(await this.#folders.client.download(fileId)).arrayBuffer());
  }

  async #findFileId(name: string): Promise<string> {
    const [nodeId, fileName] = splitName(name);
    const folderId = await this.#folders.resolve([...this.#path, nodeId]);
    const [file] = await this.#folders.childFiles(folderId, fileName);
    if (file === undefined) throw new Error(`GoogleDriveTransport: no file named "${name}"`);
    this.#fileIds.set(name, file.id);
    return file.id;
  }
}

function splitName(name: string): [string, string] {
  const slash = name.indexOf('/');
  if (slash === -1) throw new RangeError(`Expected "<nodeId>/<file>", got "${name}"`);
  return [name.slice(0, slash), name.slice(slash + 1)];
}

/** A Blob of `bytes` - copied, since a Blob can't take a view on a shared buffer. */
export function blobOf(bytes: Uint8Array): Blob {
  return new Blob([new Uint8Array(bytes)]);
}
