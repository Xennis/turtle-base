import { beforeEach, expect, test } from 'vite-plus/test';

import { openTestDatabase } from '../../../core/database/test-database.ts';
import { AttachmentsRepository } from '../../files/data/attachments-repository.ts';
import type { EditorBlock } from './block-document.ts';
import { syncAttachmentsFromDocument } from './block-sync.ts';

let attachments: AttachmentsRepository;

beforeEach(async () => {
  attachments = new AttachmentsRepository(await openTestDatabase());
});

const file = { file_hash: 'sha256-x', name: 'x.png', mime_type: 'image/png', size: 1, width: null, height: null };

function block(attachmentId: string): EditorBlock {
  return { id: `b-${attachmentId}`, type: 'attachment', props: { attachmentId }, children: [] };
}

function sync(pageId: string, document: EditorBlock[]) {
  return syncAttachmentsFromDocument({ attachments, pageId, document });
}

async function active(pageId: string) {
  return (await attachments.allInPageContent(pageId)).filter((a) => a.deleted_at === null).map((a) => a.id);
}

test('removing a block soft-deletes its attachment, undoing it restores it', async () => {
  const id = await attachments.create({ pageId: 'p', file });

  await sync('p', []);
  expect(await active('p')).toEqual([]);

  await sync('p', [block(id)]);
  expect(await active('p')).toEqual([id]);
});

test('a block pasted from another page gets an attachment of its own', async () => {
  const foreign = await attachments.create({ pageId: 'other', file });

  const replacements = await sync('p', [block(foreign)]);

  const copy = replacements.get(foreign);
  expect(copy).toBeDefined();
  expect(await active('p')).toEqual([copy]);
  expect(await active('other')).toEqual([foreign]);
});

test('leaves field attachments and unknown ids alone', async () => {
  const inField = await attachments.create({ pageId: 'p', fieldId: 'f', file });

  expect(await sync('p', [block('not-synced-yet')])).toEqual(new Map());
  expect((await attachments.listInField('p', 'f')).map((a) => a.id)).toEqual([inField]);
});
