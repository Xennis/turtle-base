import { bytesOf, MemoryFileDirectory, streamOf } from '@turtle-base/platform/testing';
import { beforeEach, expect, test } from 'vite-plus/test';

import { FileStore, fileHashOf } from './file-store.ts';
import type { ThumbnailMaker } from './thumbnails.ts';

const pngHeader = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

/** Decodes "images" whose first byte after the PNG header is 1 as 1200×600. */
const fakeThumbnails: ThumbnailMaker = async (image) => {
  const bytes = new Uint8Array(await image.arrayBuffer());
  return bytes[pngHeader.length] === 1 ? { jpeg: new Uint8Array([0xff, 0xd8]), width: 1200, height: 600 } : undefined;
};

let directory: MemoryFileDirectory;
let store: FileStore;

beforeEach(() => {
  directory = new MemoryFileDirectory();
  store = new FileStore(directory, fakeThumbnails);
});

function importBytes(name: string, bytes: number[]) {
  return store.import({ name, bytes: streamOf(new Uint8Array(bytes)) });
}

test('import() names the file by its content hash', async () => {
  const bytes = new TextEncoder().encode('hello');

  const stored = await store.import({ name: 'a.txt', bytes: streamOf(bytes) });

  expect(stored).toEqual({ hash: fileHashOf(bytes), mimeType: 'text/plain', size: 5, width: null, height: null });
  expect(stored.hash).toBe('sha256-2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824');
  expect(new TextDecoder().decode(await bytesOf(await store.read(stored.hash)))).toBe('hello');
  expect(await store.has(FileStore.thumbnailNameOf(stored.hash))).toBe(false);
});

test('import() stores the same content once', async () => {
  const first = await importBytes('a.txt', [1, 2, 3]);
  const second = await importBytes('b.bin', [1, 2, 3]);

  expect(second.hash).toBe(first.hash);
  expect(await store.names()).toEqual(new Set([first.hash]));
  expect(directory.pendingTemps).toBe(0);
});

test('import() detects the type from the content, not the extension', async () => {
  expect((await importBytes('looks-like.xml', [...pngHeader, 0])).mimeType).toBe('image/png');
  expect((await importBytes('unknown', [0, 1, 2])).mimeType).toBe('application/octet-stream');
});

test('import() writes a thumbnail for an image, with its size', async () => {
  const stored = await importBytes('photo.png', [...pngHeader, 1]);

  expect([stored.width, stored.height]).toEqual([1200, 600]);
  expect(await store.names()).toEqual(new Set([stored.hash, FileStore.thumbnailNameOf(stored.hash)]));
});

test("import() skips the thumbnail for content it can't decode", async () => {
  const stored = await importBytes('broken.png', [...pngHeader, 0]);

  expect(stored.mimeType).toBe('image/png');
  expect(stored.width).toBeNull();
  expect(await store.has(FileStore.thumbnailNameOf(stored.hash))).toBe(false);
});

test('put() stores a download that matches its hash', async () => {
  const bytes = new Uint8Array([7, 8, 9]);
  const hash = fileHashOf(bytes);
  const stored: string[] = [];
  store.onStored((name) => stored.push(name));

  await store.put(hash, streamOf(bytes));

  expect(await bytesOf(await store.read(hash))).toEqual(bytes);
  expect(stored).toEqual([hash]);
});

test("put() rejects a download that doesn't match its hash", async () => {
  const hash = fileHashOf(new Uint8Array([1]));

  await expect(store.put(hash, streamOf(new Uint8Array([2])))).rejects.toThrow(/does not match/);
  expect(await store.has(hash)).toBe(false);
  expect(directory.pendingTemps).toBe(0);
});

test('put() stores a thumbnail without a hash check', async () => {
  const name = FileStore.thumbnailNameOf(fileHashOf(new Uint8Array([1])));

  await store.put(name, streamOf(new Uint8Array([2])));

  expect(await bytesOf(await store.read(name))).toEqual(new Uint8Array([2]));
});

test('put() refuses names that are no store names', async () => {
  await expect(store.put('../escape', streamOf(new Uint8Array([1])))).rejects.toThrow(RangeError);
});
