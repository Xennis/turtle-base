import { convertFileSrc } from '@tauri-apps/api/core';
import { exists, open, readDir, readFile, remove, rename, stat, writeFile } from '@tauri-apps/plugin-fs';
import type { FileDirectory } from '@turtle-base/platform';

const validName = /^[\w.-]+$/;

/**
 * The files in `folder` - attachments or plugin bundles, the folders the
 * shell's capabilities let the page at - with temporary files in its `tmp/`
 * (the shell creates both). The page loads attachments through Tauri's
 * asset protocol.
 */
export function filesIn(folder: string): FileDirectory {
  function pathOf(name: string): string {
    if (!validName.test(name) || name === '.' || name === '..') throw new RangeError(`Invalid file name: ${name}`);
    return `${folder}/${name}`;
  }

  function tempOf(handle: string): string {
    if (!/^[0-9a-f-]{36}$/.test(handle)) throw new RangeError(`Invalid temporary file: ${handle}`);
    return `${folder}/tmp/${handle}`;
  }

  return {
    list: async () => (await readDir(folder)).filter((entry) => entry.isFile).map((entry) => entry.name),
    exists: async (name) => exists(pathOf(name)),
    size: async (name) => (await stat(pathOf(name))).size,
    read: async (name) => new Blob([await readFile(pathOf(name))]).stream(),
    readHead: async (name, length) => {
      const file = await open(pathOf(name), { read: true });
      try {
        const head = new Uint8Array(length);
        let filled = 0;
        while (filled < length) {
          const read = await file.read(head.subarray(filled));
          if (read === null || read === 0) break;
          filled += read;
        }
        return head.slice(0, filled);
      } finally {
        await file.close();
      }
    },
    writeTemp: async (bytes) => {
      const handle = crypto.randomUUID();
      await writeFile(tempOf(handle), bytes);
      return handle;
    },
    commitTemp: async (handle, name) => rename(tempOf(handle), pathOf(name)),
    discardTemp: async (handle) => {
      const path = tempOf(handle);
      if (await exists(path)) await remove(path);
    },
    urlOf: (name) => convertFileSrc(pathOf(name)),
  };
}
