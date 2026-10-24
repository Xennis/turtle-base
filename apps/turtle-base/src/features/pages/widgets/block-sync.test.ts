import { beforeEach, expect, test } from 'vite-plus/test';

import { openTestDatabase } from '../../../core/database/test-database.ts';
import { BlocksRepository } from '../data/blocks-repository.ts';
import { buildDocument, encodeBlockContent, hiddenBlockIds, type EditorBlock } from './block-document.ts';
import { syncBlocksFromDocument } from './block-sync.ts';

const known = new Set(['paragraph', 'heading', 'bulletListItem']);
let blocks: BlocksRepository;

beforeEach(async () => {
  blocks = new BlocksRepository(await openTestDatabase());
});

function paragraph(id: string, text: string, children: EditorBlock[] = []): EditorBlock {
  return { id, type: 'paragraph', props: {}, content: [{ type: 'text', text, styles: {} }], children };
}

async function sync(document: EditorBlock[]) {
  await syncBlocksFromDocument({ blocks, pageId: 'p', document, currentBlocks: await blocks.listActiveInPage('p') });
}

async function stored() {
  return buildDocument(await blocks.listActiveInPage('p'), known);
}

test('a document survives a round trip through the block rows', async () => {
  const document = [
    {
      id: 'h',
      type: 'heading',
      props: { level: 2 },
      content: [{ type: 'text', text: 'Title', styles: {} }],
      children: [],
    },
    paragraph('a', 'First', [paragraph('a1', 'Nested')]),
    paragraph('b', 'Second'),
  ];

  await sync(document);

  expect(await stored()).toEqual(document);
});

test('changes, moves, re-types and removes blocks by id', async () => {
  await sync([paragraph('a', 'A'), paragraph('b', 'B'), paragraph('c', 'C')]);
  const [a, b] = await blocks.listActiveInPage('p');

  const next = [
    { ...paragraph('c', 'C changed'), type: 'heading', props: { level: 1 } },
    paragraph('a', 'A', [paragraph('new', 'New')]),
  ];
  await sync(next);

  expect(await stored()).toEqual(next);
  // Existing rows keep their ids - nothing was recreated.
  expect((await blocks.listActiveInPage('p')).map((block) => block.id)).toContain(a?.id);
  expect((await blocks.listActiveInPage('p')).map((block) => block.id)).not.toContain(b?.id);
});

test('writes nothing when nothing changed', async () => {
  await sync([paragraph('a', 'A')]);
  const before = await blocks.listActiveInPage('p');

  await sync([paragraph('a', 'A')]);

  expect(await blocks.listActiveInPage('p')).toEqual(before);
});

test('leaves blocks of unknown types, and their children, alone', async () => {
  await blocks.create({ id: 'x', pageId: 'p', type: 'hologram', content: '{}' });
  await blocks.create({
    id: 'x1',
    pageId: 'p',
    parentBlockId: 'x',
    type: 'paragraph',
    content: encodeBlockContent(paragraph('x1', 'in x')),
  });
  await blocks.create({ id: 'a', pageId: 'p', type: 'paragraph', content: encodeBlockContent(paragraph('a', 'A')) });
  const rows = await blocks.listActiveInPage('p');
  const untouched = hiddenBlockIds(rows, known);

  expect(buildDocument(rows, known).map((block) => block.id)).toEqual(['a']);
  await syncBlocksFromDocument({ blocks, pageId: 'p', document: [], currentBlocks: rows, untouched });

  expect((await blocks.listActiveInPage('p')).map((block) => block.id).toSorted()).toEqual(['x', 'x1']);
});

test('reads broken content as empty props', async () => {
  await blocks.create({ id: 'a', pageId: 'p', type: 'paragraph', content: 'not json' });

  expect(await stored()).toEqual([{ id: 'a', type: 'paragraph', props: {}, children: [] }]);
});
