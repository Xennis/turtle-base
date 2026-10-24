import type { SyncTransport } from '@turtle-base/crdt-file-sync-transport';
import { FakeSyncTransport } from '@turtle-base/crdt-file-sync-transport/testing';
import { expect, test } from 'vite-plus/test';

import type { AppDatabase } from '../../core/database/app-database.ts';
import { openTestDatabase } from '../../core/database/test-database.ts';
import { SpacesRepository } from '../../features/spaces/data/spaces-repository.ts';
import { ChangesetPullError, SyncController } from './sync-controller.ts';
import { InMemorySyncStateStore } from './sync-state-store.ts';

async function spaceIds(database: AppDatabase) {
  return (await new SpacesRepository(database).listActive()).map((space) => space.id).toSorted();
}

test('syncNow() with nothing to pull ends idle', async () => {
  const controller = new SyncController((await openTestDatabase()).crdt, new FakeSyncTransport());
  let notified = 0;
  controller.subscribe(() => notified++);

  await controller.syncNow();

  expect(controller.status).toBe('idle');
  expect(controller.lastError).toBeUndefined();
  expect(controller.lastSyncedAt).toBeDefined();
  expect(notified).toBe(2);
});

test('two devices converge through a shared transport', async () => {
  const a = await openTestDatabase();
  const b = await openTestDatabase();
  const spaceA = await new SpacesRepository(a).create({ name: 'On A' });
  const spaceB = await new SpacesRepository(b).create({ name: 'On B' });
  const transport = new FakeSyncTransport();
  const controllerA = new SyncController(a.crdt, transport);
  const controllerB = new SyncController(b.crdt, transport);
  await new SpacesRepository(a).rename(spaceA, 'Renamed on A');

  await controllerA.syncNow();
  await controllerB.syncNow();

  const onB = await new SpacesRepository(b).listActive();
  expect(onB.map((space) => space.id).toSorted()).toEqual([spaceA, spaceB].toSorted());
  expect(onB.find((space) => space.id === spaceA)?.name).toBe('Renamed on A');

  await controllerB.syncNow();
  await controllerA.syncNow();

  expect(await spaceIds(a)).toEqual([spaceA, spaceB].toSorted());
});

test('a second sync does not re-upload an already-pushed changeset', async () => {
  const transport = new FakeSyncTransport();
  const controller = new SyncController((await openTestDatabase()).crdt, transport);

  await controller.syncNow();
  const namesAfterFirstSync = await transport.list();
  // The seeded local user.
  expect(namesAfterFirstSync).toHaveLength(1);

  await controller.syncNow();
  expect(await transport.list()).toEqual(namesAfterFirstSync);
});

test('after a restart, only changes since the last push are uploaded', async () => {
  const database = await openTestDatabase();
  const spaces = new SpacesRepository(database);
  await spaces.create({ name: 'Before' });
  const transport = new FakeSyncTransport();
  const state = new InMemorySyncStateStore();
  await new SyncController(database.crdt, transport, state).syncNow();

  // A new controller, as after an app restart - the state store is what survives.
  const restarted = new SyncController(database.crdt, transport, state);
  await restarted.syncNow();
  expect(await transport.list()).toHaveLength(1);

  await spaces.create({ name: 'After' });
  await restarted.syncNow();
  const names = await transport.list();
  expect(names).toHaveLength(2);
  const latest: unknown = JSON.parse(new TextDecoder().decode(await transport.download(names.at(-1) ?? '')));
  expect(latest).toMatchObject({ spaces: [{ name: 'After' }] });
});

test('pushes everything again when the remote has no own file', async () => {
  const database = await openTestDatabase();
  await new SpacesRepository(database).create({ name: 'Space' });
  const state = new InMemorySyncStateStore();
  await new SyncController(database.crdt, new FakeSyncTransport(), state).syncNow();

  // E.g. the device folder was moved or deleted in Drive.
  const emptied = new FakeSyncTransport();
  await new SyncController(database.crdt, emptied, state).syncNow();

  expect(await emptied.list()).toHaveLength(1);
});

test('a second sync without new files downloads nothing', async () => {
  const a = await openTestDatabase();
  const b = await openTestDatabase();
  await new SpacesRepository(a).create({ name: 'On A' });
  const transport = new FakeSyncTransport();
  await new SyncController(a.crdt, transport).syncNow();
  const controllerB = new SyncController(b.crdt, transport);

  await controllerB.syncNow();
  expect(transport.downloads).toHaveLength(1);

  await controllerB.syncNow();
  expect(transport.downloads).toHaveLength(1);
});

test("a failing file doesn't block the others and is retried next sync", async () => {
  const a = await openTestDatabase();
  const b = await openTestDatabase();
  const spacesA = new SpacesRepository(a);
  const transport = new FakeSyncTransport();
  const controllerA = new SyncController(a.crdt, transport);
  const first = await spacesA.create({ name: 'First' });
  await controllerA.syncNow();
  const [firstFile] = await transport.list();
  const second = await spacesA.create({ name: 'Second' });
  await controllerA.syncNow();
  if (firstFile === undefined) throw new Error('Nothing pushed');

  transport.failingDownloads.add(firstFile);
  const controllerB = new SyncController(b.crdt, transport);
  await controllerB.syncNow();

  expect(controllerB.status).toBe('error');
  expect(controllerB.lastError).toBeInstanceOf(ChangesetPullError);
  expect(await spaceIds(b)).toEqual([second]);

  transport.failingDownloads.clear();
  transport.downloads.length = 0;
  await controllerB.syncNow();

  expect(controllerB.status).toBe('idle');
  expect(transport.downloads).toEqual([firstFile]);
  expect(await spaceIds(b)).toEqual([first, second].toSorted());
});

test('merged names no longer listed are forgotten', async () => {
  const a = await openTestDatabase();
  const b = await openTestDatabase();
  await new SpacesRepository(a).create({ name: 'On A' });
  const transport = new FakeSyncTransport();
  await new SyncController(a.crdt, transport).syncNow();
  const state = new InMemorySyncStateStore();
  await new SyncController(b.crdt, transport, state).syncNow();
  expect(state.mergedFiles(b.crdt.nodeId).size).toBe(1);

  await new SyncController(b.crdt, new FakeSyncTransport(), state).syncNow();

  expect(state.mergedFiles(b.crdt.nodeId).size).toBe(0);
});

test('a transport failure surfaces as an error status without throwing', async () => {
  const failing: SyncTransport = {
    upload: () => Promise.reject(new Error('upload failed')),
    list: () => Promise.resolve([]),
    download: () => Promise.reject(new Error('download failed')),
  };
  const controller = new SyncController((await openTestDatabase()).crdt, failing);

  await controller.syncNow();

  expect(controller.status).toBe('error');
  expect(controller.lastError).toBeInstanceOf(Error);
});
