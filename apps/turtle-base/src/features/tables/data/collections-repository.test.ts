import { beforeEach, expect, test } from 'vite-plus/test';

import { openTestDatabase } from '../../../core/database/test-database.ts';
import { CollectionsRepository } from './collections-repository.ts';

let collections: CollectionsRepository;

beforeEach(async () => {
  collections = new CollectionsRepository(await openTestDatabase());
});

test('lists the active collections of a space in creation order', async () => {
  const a = await collections.create({ spaceId: 's1', name: 'A', id: 'a' });
  const b = await collections.create({ spaceId: 's1', name: 'B', id: 'b' });
  await collections.create({ spaceId: 's2', name: 'Elsewhere' });
  const c = await collections.create({ spaceId: 's1', name: 'C', id: 'c' });
  await collections.softDelete(b);

  expect((await collections.listActiveInSpace('s1')).map((collection) => collection.id)).toEqual([a, c]);
});

test('moves a collection to another space', async () => {
  const id = await collections.create({ spaceId: 's1', name: 'A' });

  await collections.move(id, 's2');

  expect(await collections.listActiveInSpace('s1')).toEqual([]);
  expect((await collections.byId(id))?.space_id).toBe('s2');
});

test('changes name, icon and title label', async () => {
  const id = await collections.create({ spaceId: 's1', name: 'A' });

  await collections.rename(id, 'Books');
  await collections.setIcon(id, '📚');
  await collections.setTitleFieldLabel(id, 'Title');

  expect(await collections.byId(id)).toMatchObject({ name: 'Books', icon: '📚', title_field_label: 'Title' });
});

test('restores a deleted collection', async () => {
  const id = await collections.create({ spaceId: 's1', name: 'A' });
  await collections.softDelete(id);

  await collections.restore(id);

  expect((await collections.byId(id))?.deleted_at).toBeNull();
});
