import { MemoryFileDirectory, streamOf } from '@turtle-base/platform/testing';
import { beforeEach, expect, test } from 'vite-plus/test';

import { openTestDatabase } from '../../../core/database/test-database.ts';
import { FileStore } from '../../../packages/file-store/file-store.ts';
import { attachPickedFiles } from './attach-files.ts';
import { AttachmentsRepository } from './attachments-repository.ts';
import { FileAccept } from './file-accept.ts';

const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1]);
let files: FileStore;
let attachments: AttachmentsRepository;

beforeEach(async () => {
  files = new FileStore(new MemoryFileDirectory(), () =>
    Promise.resolve({ jpeg: new Uint8Array(), width: 4, height: 3 }),
  );
  attachments = new AttachmentsRepository(await openTestDatabase());
});

function picked(name: string, bytes: Uint8Array) {
  return { name, bytes: streamOf(bytes) };
}

test('attaches what the field takes, in the order picked', async () => {
  const result = await attachPickedFiles({
    files,
    attachments,
    picked: [
      picked('a.png', png),
      picked('notes.txt', new TextEncoder().encode('text')),
      picked('b.png', new Uint8Array([...png, 2])),
    ],
    pageId: 'p',
    fieldId: 'f',
    accept: FileAccept.images,
  });

  expect(result.rejected).toEqual(['notes.txt']);
  expect(await attachments.listInField('p', 'f')).toMatchObject([
    { name: 'a.png', mime_type: 'image/png', width: 4, height: 3 },
    { name: 'b.png' },
  ]);
});

test('stops at the maximum count', async () => {
  const result = await attachPickedFiles({
    files,
    attachments,
    picked: [picked('a.png', png), picked('b.png', new Uint8Array([...png, 2]))],
    pageId: 'p',
    accept: FileAccept.any,
    maxCount: 1,
  });

  expect(result.ids).toHaveLength(1);
  expect(result.rejected).toEqual(['b.png']);
  expect(await attachments.allInPageContent('p')).toMatchObject([{ name: 'a.png', field_id: null }]);
});
