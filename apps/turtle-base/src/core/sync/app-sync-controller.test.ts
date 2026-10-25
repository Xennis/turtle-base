import { GoogleDriveSyncFolder } from '@turtle-base/crdt-file-sync-google-drive';
import { FakeDrive } from '@turtle-base/crdt-file-sync-google-drive/testing';
import {
  FakeGoogleAuthenticator,
  MemoryFileDirectory,
  MemoryKeyValueStore,
  streamOf,
} from '@turtle-base/platform/testing';
import { expect, test } from 'vite-plus/test';

import { AttachmentsRepository } from '../../features/files/data/attachments-repository.ts';
import { PagesRepository } from '../../features/pages/data/pages-repository.ts';
import { SpacesRepository } from '../../features/spaces/data/spaces-repository.ts';
import { FileStore } from '../../packages/file-store/file-store.ts';
import type { AppDatabase } from '../database/app-database.ts';
import { openTestDatabase } from '../database/test-database.ts';
import { AppSyncController, syncFolderName } from './app-sync-controller.ts';
import { SyncFormatTooNewError } from './sync-format.ts';

interface Device {
  database: AppDatabase;
  files: FileStore;
  sync: AppSyncController;
}

async function device(drive: FakeDrive, options: { auth?: FakeGoogleAuthenticator; isMobile?: boolean } = {}) {
  const database = await openTestDatabase();
  const files = new FileStore(new MemoryFileDirectory(), () => Promise.resolve(undefined));
  const sync = new AppSyncController({
    crdt: database.crdt,
    auth: options.auth ?? new FakeGoogleAuthenticator(),
    fetch: drive.fetch,
    files,
    attachments: new AttachmentsRepository(database),
    prefs: new MemoryKeyValueStore(),
    isMobile: options.isMobile ?? false,
  });
  return { database, files, sync } satisfies Device;
}

async function attachFile(target: Device, bytes: number[]) {
  const stored = await target.files.import({ name: 'notes.txt', bytes: streamOf(new Uint8Array(bytes)) });
  const spaceId = await new SpacesRepository(target.database).create({ name: 'Space' });
  const pageId = await new PagesRepository(target.database).create({ spaceId });
  await new AttachmentsRepository(target.database).create({
    pageId,
    file: {
      file_hash: stored.hash,
      name: 'notes.txt',
      mime_type: stored.mimeType,
      size: stored.size,
      width: null,
      height: null,
    },
  });
  return stored.hash;
}

test('is unavailable without a sign-in for the platform', async () => {
  const database = await openTestDatabase();
  const sync = new AppSyncController({
    crdt: database.crdt,
    auth: undefined,
    fetch: new FakeDrive().fetch,
    files: new FileStore(new MemoryFileDirectory(), () => Promise.resolve(undefined)),
    attachments: new AttachmentsRepository(database),
    prefs: new MemoryKeyValueStore(),
    isMobile: false,
  });

  expect(sync.isAvailable).toBe(false);
  await sync.restoreConnection();
  expect(sync.isConnected).toBe(false);
});

test('restores an earlier sign-in, but does not prompt for one', async () => {
  const drive = new FakeDrive();
  const restored = await device(drive, { auth: new FakeGoogleAuthenticator(true) });
  const fresh = await device(drive);

  await restored.sync.restoreConnection();
  await fresh.sync.restoreConnection();

  expect(restored.sync.isConnected).toBe(true);
  expect(fresh.sync.isConnected).toBe(false);
});

test('syncs rows and files between two devices', async () => {
  const drive = new FakeDrive();
  const a = await device(drive);
  const b = await device(drive);
  const hash = await attachFile(a, [1, 2, 3]);
  await a.sync.connect();
  await b.sync.connect();

  await a.sync.syncNow();
  await b.sync.syncNow();

  expect(a.sync.status).toBe('idle');
  expect(b.sync.status).toBe('idle');
  expect((await new SpacesRepository(b.database).listActive()).map((space) => space.name)).toEqual(['Space']);
  // Desktop keeps all originals offline by default.
  expect(await b.files.has(hash)).toBe(true);
  expect(b.sync.failedFileCount).toBe(0);
});

test('leaves originals for later on mobile, and fetches one on demand', async () => {
  const drive = new FakeDrive();
  const a = await device(drive);
  const phone = await device(drive, { isMobile: true });
  const hash = await attachFile(a, [4, 5, 6]);
  await a.sync.connect();
  await phone.sync.connect();
  await a.sync.syncNow();

  await phone.sync.syncNow();

  expect(phone.sync.keepAllFilesOffline).toBe(false);
  expect(await phone.files.has(hash)).toBe(false);
  expect(await phone.sync.fetchFile(hash)).toBe(true);
  expect(await phone.files.has(hash)).toBe(true);
});

test('refuses sync data of a newer app version', async () => {
  const drive = new FakeDrive();
  const a = await device(drive);
  await a.sync.connect();
  await a.sync.syncNow();
  await new GoogleDriveSyncFolder({
    fetch: drive.fetch,
    accessToken: () => Promise.resolve('token'),
    name: syncFolderName,
  }).writeFormatVersion(99);

  await a.sync.syncNow();

  expect(a.sync.status).toBe('error');
  expect(a.sync.lastError).toBeInstanceOf(SyncFormatTooNewError);
});

test('disconnects', async () => {
  const a = await device(new FakeDrive());
  await a.sync.connect();
  let notified = 0;
  a.sync.subscribe(() => notified++);

  await a.sync.disconnect();

  expect(a.sync.isConnected).toBe(false);
  expect(notified).toBe(1);
  await a.sync.syncNow();
  expect(a.sync.status).toBe('idle');
});
