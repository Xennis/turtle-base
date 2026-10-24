import type { FileTransport } from './file-transport.ts';
import type { SyncTransport } from './sync-transport.ts';

/** In-memory {@link SyncTransport} for tests - no network, no disk. */
export class FakeSyncTransport implements SyncTransport {
  readonly #files = new Map<string, Uint8Array>();

  /** Names whose download fails, to simulate failures. */
  readonly failingDownloads = new Set<string>();

  /** Every download in order, also failed ones. */
  readonly downloads: string[] = [];

  upload(name: string, bytes: Uint8Array): Promise<void> {
    this.#files.set(name, bytes);
    return Promise.resolve();
  }

  list(): Promise<string[]> {
    return Promise.resolve([...this.#files.keys()]);
  }

  download(name: string): Promise<Uint8Array> {
    this.downloads.push(name);
    const bytes = this.#files.get(name);
    if (bytes === undefined || this.failingDownloads.has(name)) {
      return Promise.reject(new Error(`FakeSyncTransport: no file named "${name}"`));
    }
    return Promise.resolve(bytes);
  }
}

/** In-memory {@link FileTransport} for tests - no network, no disk. */
export class FakeFileTransport implements FileTransport {
  readonly files = new Map<string, Uint8Array>();

  /** Names whose upload or download fails, to simulate failures. */
  readonly failing = new Set<string>();

  async upload(name: string, bytes: ReadableStream<Uint8Array>): Promise<void> {
    const content = new Uint8Array(await new Response(bytes).arrayBuffer());
    if (this.failing.has(name)) throw new Error(`FakeFileTransport: upload of "${name}" failed`);
    this.files.set(name, content);
  }

  list(): Promise<Set<string>> {
    return Promise.resolve(new Set(this.files.keys()));
  }

  download(name: string): Promise<ReadableStream<Uint8Array>> {
    const content = this.files.get(name);
    if (content === undefined || this.failing.has(name)) {
      return Promise.reject(new Error(`FakeFileTransport: no file named "${name}"`));
    }
    return Promise.resolve(
      new ReadableStream({
        start(controller) {
          controller.enqueue(content);
          controller.close();
        },
      }),
    );
  }
}
