import { beforeEach, expect, test } from 'vite-plus/test';

import { openTestDatabase } from '../../../core/database/test-database.ts';
import { BlocksRepository } from './blocks-repository.ts';

let blocks: BlocksRepository;

beforeEach(async () => {
  blocks = new BlocksRepository(await openTestDatabase());
});

test('appends blocks per parent', async () => {
  const a = await blocks.create({ pageId: 'p', type: 'paragraph' });
  const b = await blocks.create({ pageId: 'p', type: 'bulletListItem' });
  const child = await blocks.create({ pageId: 'p', parentBlockId: b, type: 'paragraph', id: 'given' });

  expect(child).toBe('given');
  expect(
    (await blocks.listActiveInPage('p')).map((block) => [block.id, block.parent_block_id, block.position]),
  ).toEqual([
    [a, null, 0],
    [child, b, 0],
    [b, null, 1],
  ]);
});

test('updates content and type, moves and soft-deletes', async () => {
  const id = await blocks.create({ pageId: 'p', type: 'paragraph' });

  await blocks.updateContent(id, '{"text":"Hi"}');
  await blocks.changeType(id, 'heading');
  await blocks.move(id, 'parent', 3);

  expect((await blocks.listActiveInPage('p'))[0]).toMatchObject({
    content: '{"text":"Hi"}',
    type: 'heading',
    parent_block_id: 'parent',
    position: 3,
  });
  await blocks.softDelete(id);
  expect(await blocks.listActiveInPage('p')).toEqual([]);
});
