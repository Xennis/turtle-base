import { sha256 } from '@noble/hashes/sha2.js';
import { bytesToHex } from '@noble/hashes/utils.js';
import type { FileDirectory } from '@turtle-base/platform';
import mime from 'mime';

import { sniffLength, sniffMimeType } from './sniff-mime-type.ts';
import { thumbnailMaxSourceBytes, type ThumbnailMaker } from './thumbnails.ts';

const hashPrefix = 'sha256-';
const thumbnailSuffix = '.thumb.jpg';
const validHash = /^sha256-[0-9a-f]{64}$/;

/** What {@link FileStore.import} found out about a file. */
export interface StoredFile {
  /** The file's name in the store, `sha256-<hex>` of its content. */
  readonly hash: string;
  readonly mimeType: string;
  readonly size: number;
  readonly width: number | null;
  readonly height: number | null;
}

/** `sha256-<hex>` of `bytes` - for tests and callers that already hold the content. */
export function fileHashOf(bytes: Uint8Array): string {
  return hashPrefix + bytesToHex(sha256(bytes));
}

/**
 * Content-addressed files, flat in one directory: each named by the hash of
 * its content, plus an optional JPEG thumbnail next to it. Knows nothing of
 * attachments or sync - see `.local/FILES.md`.
 */
export class FileStore {
  readonly #directory: FileDirectory;
  readonly #thumbnails: ThumbnailMaker;
  readonly #listeners = new Set<(name: string) => void>();

  constructor(directory: FileDirectory, thumbnails: ThumbnailMaker) {
    this.#directory = directory;
    this.#thumbnails = thumbnails;
  }

  static thumbnailNameOf(hash: string): string {
    return hash + thumbnailSuffix;
  }

  static isThumbnailName(name: string): boolean {
    return name.endsWith(thumbnailSuffix);
  }

  /** Whether `name` can be a file of this store - guards against names from elsewhere (e.g. a sync folder). */
  static isValidName(name: string): boolean {
    return validHash.test(FileStore.isThumbnailName(name) ? name.slice(0, -thumbnailSuffix.length) : name);
  }

  /** Hears the names of files as they land, e.g. after a download - for views waiting on one. */
  onStored(listener: (name: string) => void): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  has(name: string): Promise<boolean> {
    return this.#directory.exists(name);
  }

  /** Where the web view loads the file from, e.g. for an `<img>`. */
  urlOf(name: string): string {
    return this.#directory.urlOf(name);
  }

  read(name: string): Promise<ReadableStream<Uint8Array>> {
    return this.#directory.read(name);
  }

  /** The names of all files (originals and thumbnails) present. */
  async names(): Promise<Set<string>> {
    return new Set((await this.#directory.list()).filter((name) => FileStore.isValidName(name)));
  }

  /**
   * Copies `bytes` into the store, hashing them on the way, and writes a
   * thumbnail if it's an image. Importing the same content twice is harmless,
   * it's stored once. `name` only hints the type when the content doesn't.
   */
  async import(source: { name: string; bytes: ReadableStream<Uint8Array> }): Promise<StoredFile> {
    const { handle, hash } = await this.#writeHashing(source.bytes);
    if (await this.#directory.exists(hash)) await this.#directory.discardTemp(handle);
    else await this.#directory.commitTemp(handle, hash);

    const size = await this.#directory.size(hash);
    const mimeType =
      sniffMimeType(await this.#directory.readHead(hash, sniffLength)) ??
      mime.getType(source.name) ??
      'application/octet-stream';
    let image: { width: number; height: number } | undefined;
    if (mimeType.startsWith('image/') && size <= thumbnailMaxSourceBytes) {
      const blob = await new Response(await this.#directory.read(hash)).blob();
      // A corrupt image is still a file worth keeping, just without a thumbnail.
      const thumbnail = await this.#thumbnails(new Blob([blob], { type: mimeType })).catch(() => undefined);
      if (thumbnail !== undefined) {
        await this.#storeAs(FileStore.thumbnailNameOf(hash), thumbnail.jpeg);
        image = { width: thumbnail.width, height: thumbnail.height };
      }
    }
    this.#notify(hash);
    return { hash, mimeType, size, width: image?.width ?? null, height: image?.height ?? null };
  }

  /**
   * Stores downloaded bytes under `name`. An original is checked against its
   * hash and rejected when it doesn't match; a thumbnail is derived, so it
   * can't be checked.
   */
  async put(name: string, bytes: ReadableStream<Uint8Array>): Promise<void> {
    if (!FileStore.isValidName(name)) throw new RangeError(`Not a file store name: ${name}`);
    const { handle, hash } = await this.#writeHashing(bytes);
    if (!FileStore.isThumbnailName(name) && hash !== name) {
      await this.#directory.discardTemp(handle);
      throw new Error(`Downloaded content does not match its hash: ${name}`);
    }
    await this.#directory.commitTemp(handle, name);
    this.#notify(name);
  }

  async #writeHashing(bytes: ReadableStream<Uint8Array>): Promise<{ handle: string; hash: string }> {
    const hasher = sha256.create();
    const hashing = bytes.pipeThrough(
      new TransformStream<Uint8Array, Uint8Array>({
        transform(chunk, controller) {
          hasher.update(chunk);
          controller.enqueue(chunk);
        },
      }),
    );
    const handle = await this.#directory.writeTemp(hashing);
    return { handle, hash: hashPrefix + bytesToHex(hasher.digest()) };
  }

  async #storeAs(name: string, bytes: Uint8Array): Promise<void> {
    const handle = await this.#directory.writeTemp(
      new ReadableStream({
        start(controller) {
          controller.enqueue(bytes);
          controller.close();
        },
      }),
    );
    await this.#directory.commitTemp(handle, name);
  }

  #notify(name: string): void {
    for (const listener of this.#listeners) listener(name);
  }
}
