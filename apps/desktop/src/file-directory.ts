import { randomUUID } from 'node:crypto';
import { mkdir, open, readdir, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const validName = /^[\w.-]+$/;

/**
 * The renderer's FileDirectory on disk: one flat folder, temporary files in
 * `tmp/` next to it. Names come from the renderer, so they're checked to
 * stay inside the folder.
 */
export class DiskFileDirectory {
  readonly path: string;
  readonly #tmp: string;

  constructor(path: string) {
    this.path = path;
    this.#tmp = join(path, 'tmp');
  }

  async list(): Promise<string[]> {
    await mkdir(this.path, { recursive: true });
    const entries = await readdir(this.path, { withFileTypes: true });
    return entries.filter((entry) => entry.isFile()).map((entry) => entry.name);
  }

  async exists(name: string): Promise<boolean> {
    try {
      return (await stat(this.fileOf(name))).isFile();
    } catch {
      return false;
    }
  }

  async size(name: string): Promise<number> {
    return (await stat(this.fileOf(name))).size;
  }

  read(name: string): Promise<Uint8Array> {
    return readFile(this.fileOf(name));
  }

  async readHead(name: string, length: number): Promise<Uint8Array> {
    const file = await open(this.fileOf(name));
    try {
      const { buffer, bytesRead } = await file.read(Buffer.alloc(length), 0, length, 0);
      return buffer.subarray(0, bytesRead);
    } finally {
      await file.close();
    }
  }

  async writeTemp(bytes: Uint8Array): Promise<string> {
    await mkdir(this.#tmp, { recursive: true });
    const handle = randomUUID();
    await writeFile(join(this.#tmp, handle), bytes);
    return handle;
  }

  commitTemp(handle: string, name: string): Promise<void> {
    return rename(this.#tempOf(handle), this.fileOf(name));
  }

  discardTemp(handle: string): Promise<void> {
    return rm(this.#tempOf(handle), { force: true });
  }

  /** The path of file `name` - throws for a name that could leave the folder. */
  fileOf(name: string): string {
    if (!validName.test(name) || name === '.' || name === '..') throw new RangeError(`Invalid file name: ${name}`);
    return join(this.path, name);
  }

  #tempOf(handle: string): string {
    if (!/^[0-9a-f-]{36}$/.test(handle)) throw new RangeError(`Invalid temporary file: ${handle}`);
    return join(this.#tmp, handle);
  }
}
