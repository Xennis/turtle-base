import type { FileTransport } from '@turtle-base/crdt-file-sync-transport';

import { FileStore } from '../file-store/file-store.ts';

/**
 * Shares a {@link FileStore}'s files between devices through a flat
 * {@link FileTransport} - the counterpart to `SyncController` for the bytes
 * the changesets only reference by hash.
 *
 * Which files to share is the caller's call (`push`/`pull` take the hashes),
 * so this knows nothing of attachments. Every name is unique per content, so
 * there's nothing to merge: a file is either there or not, and uploading or
 * downloading it twice is only wasted bandwidth.
 */
export class FileSyncController {
  readonly #store: FileStore;
  readonly #transport: FileTransport;
  readonly #fetches = new Map<string, Promise<boolean>>();

  constructor(store: FileStore, transport: FileTransport) {
    this.#store = store;
    this.#transport = transport;
  }

  /**
   * Uploads the originals and thumbnails of `hashes` that this device has and
   * the transport doesn't. Returns how many failed - a failure doesn't stop
   * the others, the next sync retries it.
   */
  async push(hashes: Iterable<string>): Promise<number> {
    const remote = await this.#transport.list();
    const local = await this.#store.names();
    let failed = 0;
    for (const hash of hashes) {
      for (const name of [hash, FileStore.thumbnailNameOf(hash)]) {
        if (!local.has(name) || remote.has(name)) continue;
        try {
          await this.#transport.upload(name, await this.#store.read(name), await this.#store.size(name));
        } catch (error) {
          console.warn(`[sync] files: upload of ${name} failed:`, error);
          failed++;
        }
      }
    }
    return failed;
  }

  /**
   * Downloads the thumbnails of `hashes` - and with `originals` the files
   * themselves - that the transport has and this device doesn't. Returns how
   * many failed, like {@link push}.
   */
  async pull(hashes: Iterable<string>, originals: boolean): Promise<number> {
    const remote = await this.#transport.list();
    const local = await this.#store.names();
    let failed = 0;
    for (const hash of hashes) {
      for (const name of originals ? [FileStore.thumbnailNameOf(hash), hash] : [FileStore.thumbnailNameOf(hash)]) {
        if (local.has(name) || !remote.has(name)) continue;
        if (!(await this.#download(name))) failed++;
      }
    }
    return failed;
  }

  /**
   * Downloads one file on demand, e.g. an original when it's opened.
   * Concurrent calls for the same name share one download. True when the file
   * is in the store afterwards.
   */
  async fetch(name: string): Promise<boolean> {
    if (await this.#store.has(name)) return true;
    const running = this.#fetches.get(name);
    if (running !== undefined) return running;
    const download = this.#download(name).finally(() => this.#fetches.delete(name));
    this.#fetches.set(name, download);
    return download;
  }

  async #download(name: string): Promise<boolean> {
    try {
      await this.#store.put(name, await this.#transport.download(name));
      return true;
    } catch (error) {
      console.warn(`[sync] files: download of ${name} failed:`, error);
      return false;
    }
  }
}
