import type { FileTransport } from '@turtle-base/crdt-file-sync-transport';

import type { DriveFolders } from './drive-folders.ts';

/** {@link FileTransport} backed by one flat Drive folder at `path`. */
export class GoogleDriveFileTransport implements FileTransport {
  readonly #folders: DriveFolders;
  readonly #path: readonly string[];
  readonly #fileIds = new Map<string, string>();

  constructor(folders: DriveFolders, path: readonly string[]) {
    this.#folders = folders;
    this.#path = path;
  }

  /**
   * Read into memory first: a fetch body from a stream isn't supported by
   * every platform's fetch, a Blob is.
   */
  async upload(name: string, bytes: ReadableStream<Uint8Array>): Promise<void> {
    const folderId = await this.#folders.resolve(this.#path);
    const content = await new Response(bytes).blob();
    this.#fileIds.set(name, await this.#folders.client.createFile(name, folderId, content));
  }

  async list(): Promise<Set<string>> {
    const folderId = await this.#folders.resolve(this.#path);
    const names = new Set<string>();
    for (const file of await this.#folders.childFiles(folderId)) {
      this.#fileIds.set(file.name, file.id);
      names.add(file.name);
    }
    return names;
  }

  async download(name: string): Promise<ReadableStream<Uint8Array>> {
    const fileId = this.#fileIds.get(name) ?? (await this.#findFileId(name));
    return this.#folders.client.download(fileId);
  }

  async #findFileId(name: string): Promise<string> {
    const folderId = await this.#folders.resolve(this.#path);
    const [file] = await this.#folders.childFiles(folderId, name);
    if (file === undefined) throw new Error(`GoogleDriveFileTransport: no file named "${name}"`);
    this.#fileIds.set(name, file.id);
    return file.id;
  }
}
