import type { FileDirectory } from './file-directory.ts';
import type { GoogleAuthenticator } from './google-authenticator.ts';
import type { KeyValueStore, SecretStorage } from './key-value-store.ts';

export { createNodeSqlDriver } from './node-sql-driver.ts';

export class MemoryKeyValueStore implements KeyValueStore {
  readonly #values = new Map<string, string>();

  get(key: string): string | undefined {
    return this.#values.get(key);
  }

  set(key: string, value: string): Promise<void> {
    this.#values.set(key, value);
    return Promise.resolve();
  }

  remove(key: string): Promise<void> {
    this.#values.delete(key);
    return Promise.resolve();
  }
}

export class MemorySecretStorage implements SecretStorage {
  readonly #values = new Map<string, string>();

  get(key: string): Promise<string | undefined> {
    return Promise.resolve(this.#values.get(key));
  }

  set(key: string, value: string): Promise<void> {
    this.#values.set(key, value);
    return Promise.resolve();
  }

  remove(key: string): Promise<void> {
    this.#values.delete(key);
    return Promise.resolve();
  }
}

/** A {@link FileDirectory} in memory. */
export class MemoryFileDirectory implements FileDirectory {
  readonly #files = new Map<string, Uint8Array>();
  readonly #temps = new Map<string, Uint8Array>();

  list(): Promise<string[]> {
    return Promise.resolve([...this.#files.keys()]);
  }

  exists(name: string): Promise<boolean> {
    return Promise.resolve(this.#files.has(name));
  }

  async size(name: string): Promise<number> {
    return (await this.#bytes(name)).length;
  }

  async read(name: string): Promise<ReadableStream<Uint8Array>> {
    return streamOf(await this.#bytes(name));
  }

  async readHead(name: string, length: number): Promise<Uint8Array> {
    return (await this.#bytes(name)).slice(0, length);
  }

  async writeTemp(bytes: ReadableStream<Uint8Array>): Promise<string> {
    const handle = crypto.randomUUID();
    this.#temps.set(handle, await bytesOf(bytes));
    return handle;
  }

  commitTemp(handle: string, name: string): Promise<void> {
    const bytes = this.#temps.get(handle);
    if (bytes === undefined) return Promise.reject(new Error(`No temporary file ${handle}`));
    this.#temps.delete(handle);
    this.#files.set(name, bytes);
    return Promise.resolve();
  }

  discardTemp(handle: string): Promise<void> {
    this.#temps.delete(handle);
    return Promise.resolve();
  }

  remove(name: string): Promise<void> {
    this.#files.delete(name);
    return Promise.resolve();
  }

  urlOf(name: string): string {
    return `memory://${name}`;
  }

  /** Temporary files not committed or discarded yet - for tests checking cleanup. */
  get pendingTemps(): number {
    return this.#temps.size;
  }

  #bytes(name: string): Promise<Uint8Array> {
    const bytes = this.#files.get(name);
    return bytes === undefined ? Promise.reject(new Error(`No file ${name}`)) : Promise.resolve(bytes);
  }
}

/** A stream of `bytes` in one chunk. */
export function streamOf(bytes: Uint8Array): ReadableStream<Uint8Array> {
  return new ReadableStream({
    start(controller) {
      controller.enqueue(bytes);
      controller.close();
    },
  });
}

/** All of a stream, in one array. */
export async function bytesOf(stream: ReadableStream<Uint8Array>): Promise<Uint8Array> {
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/** A {@link GoogleAuthenticator} that never reaches Google - signing in always succeeds, with token `token`. */
export class FakeGoogleAuthenticator implements GoogleAuthenticator {
  signedIn: boolean;

  /** `signedIn` is what a silent sign-in finds, e.g. after an earlier session. */
  constructor(signedIn = false) {
    this.signedIn = signedIn;
  }

  signInSilently(): Promise<boolean> {
    return Promise.resolve(this.signedIn);
  }

  signIn(): Promise<void> {
    this.signedIn = true;
    return Promise.resolve();
  }

  signOut(): Promise<void> {
    this.signedIn = false;
    return Promise.resolve();
  }

  accessToken(): Promise<string> {
    return this.signedIn ? Promise.resolve('token') : Promise.reject(new Error('Not signed in'));
  }
}
