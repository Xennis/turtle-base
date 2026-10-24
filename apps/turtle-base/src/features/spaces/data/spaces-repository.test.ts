import { beforeEach, expect, test } from 'vite-plus/test';

import type { AppDatabase } from '../../../core/database/app-database.ts';
import { openTestDatabase } from '../../../core/database/test-database.ts';
import { SpacesRepository } from './spaces-repository.ts';

let database: AppDatabase;
let spaces: SpacesRepository;

beforeEach(async () => {
  database = await openTestDatabase();
  spaces = new SpacesRepository(database);
});

test('lists active spaces in position order', async () => {
  const a = await spaces.create({ name: 'A' });
  const b = await spaces.create({ name: 'B', icon: '🐢' });
  await spaces.reorder(a, 5);

  const listed = await spaces.listActive();

  expect(listed.map((space) => [space.id, space.name, space.icon])).toEqual([
    [b, 'B', '🐢'],
    [a, 'A', null],
  ]);
});

test('keeps a given id', async () => {
  expect(await spaces.create({ name: 'Books', id: 'books.1' })).toBe('books.1');
});

test('soft-deletes and restores', async () => {
  const id = await spaces.create({ name: 'A' });

  await spaces.softDelete(id);
  expect(await spaces.listActive()).toEqual([]);

  await spaces.restore(id);
  expect((await spaces.listActive()).map((space) => space.id)).toEqual([id]);
});

test('records who changed a space and when', async () => {
  const id = await spaces.create({ name: 'A' });
  const userId = await database.currentUserId();

  await spaces.rename(id, 'Renamed');

  const [space] = await spaces.listActive();
  expect(space).toMatchObject({ name: 'Renamed', created_by: userId, updated_by: userId });
  expect(space?.updated_at).toBeGreaterThanOrEqual(space?.created_at ?? Infinity);
});
