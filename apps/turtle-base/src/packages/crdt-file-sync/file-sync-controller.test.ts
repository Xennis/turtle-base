import { FakeFileTransport } from '@turtle-base/crdt-file-sync-transport/testing';
import { bytesOf, MemoryFileDirectory, streamOf } from '@turtle-base/platform/testing';
import { beforeEach, expect, test } from 'vite-plus/test';

import { FileStore, fileHashOf } from '../file-store/file-store.ts';
import type { ThumbnailMaker } from '../file-store/thumbnails.ts';
import { FileSyncController } from './file-sync-controller.ts';

const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 8, 8]);
const thumbnails: ThumbnailMaker = () => Promise.resolve({ jpeg: new Uint8Array([0xff, 0xd8]), width: 8, height: 8 });

let transport: FakeFileTransport;
let storeA: FileStore;
let storeB: FileStore;
let deviceA: FileSyncController;
let deviceB: FileSyncController;

beforeEach(() => {
  transport = new FakeFileTransport();
  storeA = new FileStore(new MemoryFileDirectory(), thumbnails);
  storeB = new FileStore(new MemoryFileDirectory(), thumbnails);
  deviceA = new FileSyncController(storeA, transport);
  deviceB = new FileSyncController(storeB, transport);
});

async function importImage(store: FileStore) {
  return (await store.import({ name: 'photo.png', bytes: streamOf(png) })).hash;
}

test('push() uploads original and thumbnail, once', async () => {
  const hash = await importImage(storeA);

  expect(await deviceA.push([hash])).toBe(0);
  expect([...transport.files.keys()].toSorted()).toEqual([hash, FileStore.thumbnailNameOf(hash)].toSorted());

  transport.failing.add(hash);
  // Already uploaded, so not tried again.
  expect(await deviceA.push([hash])).toBe(0);
});

test('push() skips hashes the device has no file for', async () => {
  expect(await deviceA.push([fileHashOf(new Uint8Array([1]))])).toBe(0);
  expect(transport.files.size).toBe(0);
});

test('pull() fetches thumbnails, originals only when asked', async () => {
  const hash = await importImage(storeA);
  await deviceA.push([hash]);

  await deviceB.pull([hash], false);
  expect(await storeB.has(FileStore.thumbnailNameOf(hash))).toBe(true);
  expect(await storeB.has(hash)).toBe(false);

  await deviceB.pull([hash], true);
  expect(await bytesOf(await storeB.read(hash))).toEqual(png);
});

test('failures are counted, not thrown', async () => {
  const hash = await importImage(storeA);
  transport.failing.add(hash);

  expect(await deviceA.push([hash])).toBe(1);

  transport.failing.clear();
  await deviceA.push([hash]);
  transport.failing.add(hash);
  expect(await deviceB.pull([hash], true)).toBe(1);
});

test('fetch() downloads one file on demand', async () => {
  const hash = await importImage(storeA);
  await deviceA.push([hash]);

  expect(await Promise.all([deviceB.fetch(hash), deviceB.fetch(hash)])).toEqual([true, true]);
  expect(await storeB.has(hash)).toBe(true);
  expect(await deviceB.fetch(fileHashOf(new Uint8Array([1])))).toBe(false);
});
