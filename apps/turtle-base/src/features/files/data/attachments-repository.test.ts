import { beforeEach, expect, test } from 'vite-plus/test';

import type { AppDatabase } from '../../../core/database/app-database.ts';
import { openTestDatabase } from '../../../core/database/test-database.ts';
import { PagesRepository } from '../../pages/data/pages-repository.ts';
import { SpacesRepository } from '../../spaces/data/spaces-repository.ts';
import { textFieldType } from '../../tables/data/base-field-type.ts';
import { CollectionsRepository } from '../../tables/data/collections-repository.ts';
import { FieldsRepository } from '../../tables/data/fields-repository.ts';
import { AttachmentsRepository, isImage, type AttachmentFile } from './attachments-repository.ts';

let database: AppDatabase;
let attachments: AttachmentsRepository;
let spaceId: string;
let collectionId: string;
let fieldId: string;
let pageId: string;

beforeEach(async () => {
  database = await openTestDatabase();
  spaceId = await new SpacesRepository(database).create({ name: 'Space' });
  collectionId = await new CollectionsRepository(database).create({ spaceId, name: 'Books' });
  fieldId = await new FieldsRepository(database).create({ collectionId, name: 'Cover', type: textFieldType });
  pageId = await new PagesRepository(database).create({ spaceId, collectionId });
  attachments = new AttachmentsRepository(database);
});

function file(hash: string): AttachmentFile {
  return { file_hash: hash, name: `${hash}.png`, mime_type: 'image/png', size: 1, width: 1, height: 1 };
}

async function idsInField() {
  return (await attachments.listInField(pageId, fieldId)).map((attachment) => attachment.id);
}

test("lists a field's attachments in order, without deleted ones", async () => {
  const a = await attachments.create({ pageId, fieldId, file: file('a') });
  const b = await attachments.create({ pageId, fieldId, file: file('b') });
  const c = await attachments.create({ pageId, fieldId, file: file('c') });
  await attachments.create({ pageId, file: file('in-content') });
  await attachments.softDelete(b);

  expect(await idsInField()).toEqual([a, c]);
});

test('reorderAll() changes the order', async () => {
  const a = await attachments.create({ pageId, fieldId, file: file('a') });
  const b = await attachments.create({ pageId, fieldId, file: file('b') });

  await attachments.reorderAll([b, a]);

  expect(await idsInField()).toEqual([b, a]);
});

test('restore() brings a deleted attachment back', async () => {
  const a = await attachments.create({ pageId, fieldId, file: file('a') });
  await attachments.softDelete(a);

  await attachments.restore(a);

  expect(await idsInField()).toEqual([a]);
});

test('fileHashes() includes deleted attachments only when asked to', async () => {
  await attachments.create({ pageId, fieldId, file: file('a') });
  const b = await attachments.create({ pageId, fieldId, file: file('b') });
  await attachments.create({ pageId, file: file('a') });
  await attachments.softDelete(b);

  expect(await attachments.fileHashes(true)).toEqual(new Set(['a']));
  expect(await attachments.fileHashes(false)).toEqual(new Set(['a', 'b']));
});

test('listInFieldOfCollection() groups by page', async () => {
  const a = await attachments.create({ pageId, fieldId, file: file('a') });

  const byPage = await attachments.listInFieldOfCollection(collectionId, fieldId);

  expect([...byPage.keys()]).toEqual([pageId]);
  expect(byPage.get(pageId)?.map((attachment) => attachment.id)).toEqual([a]);
});

test('copyTo() makes a new attachment of the same file', async () => {
  const source = await attachments.byId(await attachments.create({ pageId, file: file('a') }));
  const otherPage = await new PagesRepository(database).create({ spaceId });
  if (source === undefined) throw new Error('Source not found');

  const copy = await attachments.byId(await attachments.copyTo(source, otherPage));

  expect(copy).toMatchObject({ page_id: otherPage, file_hash: 'a' });
  expect(copy !== undefined && isImage(copy)).toBe(true);
});
