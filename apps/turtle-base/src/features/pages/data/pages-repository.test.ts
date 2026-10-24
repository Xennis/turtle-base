import { beforeEach, expect, test } from 'vite-plus/test';

import { openTestDatabase } from '../../../core/database/test-database.ts';
import { decodePageProperties, PagesRepository } from './pages-repository.ts';

let pages: PagesRepository;

beforeEach(async () => {
  pages = new PagesRepository(await openTestDatabase());
});

test('numbers entries per collection and pages per space level', async () => {
  const e1 = await pages.create({ spaceId: 's', collectionId: 'c', title: 'Entry 1' });
  const e2 = await pages.create({ spaceId: 's', collectionId: 'c', title: 'Entry 2' });
  const p1 = await pages.create({ spaceId: 's', title: 'Page 1' });
  await pages.create({ spaceId: 's', parentPageId: p1, title: 'Child' });

  expect((await pages.listActiveInCollection('c')).map((page) => [page.id, page.position])).toEqual([
    [e1, 0],
    [e2, 1],
  ]);
  expect((await pages.listTopLevelInSpace('s')).map((page) => [page.id, page.position])).toEqual([[p1, 0]]);
});

test('sets one property value, keeping the others', async () => {
  const id = await pages.create({ spaceId: 's', collectionId: 'c', properties: { a: 1, b: 'two' } });

  await pages.setPropertyValue(id, 'a', 3);
  await pages.setPropertyValue(id, 'c', null);

  expect(decodePageProperties((await pages.byId(id))?.properties ?? '')).toEqual({ a: 3, b: 'two', c: null });
});

test('soft-deletes and restores', async () => {
  const id = await pages.create({ spaceId: 's', title: 'Page' });

  await pages.softDelete(id);
  expect(await pages.listTopLevelInSpace('s')).toEqual([]);

  await pages.restore(id);
  expect(await pages.listTopLevelInSpace('s')).toHaveLength(1);
});

test('reads broken properties as empty', () => {
  expect(decodePageProperties('[1]')).toEqual({});
  expect(decodePageProperties('not json')).toEqual({});
});
