import { MemoryFileDirectory } from '@turtle-base/platform/testing';
import { beforeEach, expect, test } from 'vite-plus/test';

import type { AppDatabase } from '../../../core/database/app-database.ts';
import { openTestDatabase } from '../../../core/database/test-database.ts';
import { FileStore } from '../../../packages/file-store/file-store.ts';
import { AttachmentsRepository } from '../../files/data/attachments-repository.ts';
import { decodePageProperties, PagesRepository } from '../../pages/data/pages-repository.ts';
import { FieldTypeRegistry } from '../../tables/data/field-type-registry.ts';
import { FieldsRepository } from '../../tables/data/fields-repository.ts';
import { demoPlugin } from './demo-plugin.test-support.ts';
import { EntryDraftWriter } from './entry-draft-writer.ts';
import { PluginInstancesRepository } from './plugin-instances-repository.ts';
import { pluginCollectionId, pluginFieldId, PluginRegistry } from './plugin-registry.ts';

const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0]);
const fieldTypes = new FieldTypeRegistry(new PluginRegistry([demoPlugin]).variants);

let database: AppDatabase;
let collectionId: string;
let downloaded: string[];
let writer: EntryDraftWriter;

beforeEach(async () => {
  database = await openTestDatabase();
  collectionId = pluginCollectionId(await new PluginInstancesRepository(database).add(demoPlugin), 'items');
  downloaded = [];
  const fetchFn = (input: RequestInfo | URL): Promise<Response> => {
    const url = new URL(input instanceof Request ? input.url : input);
    downloaded.push(url.pathname);
    if (url.pathname === '/cover.png') return Promise.resolve(new Response(png));
    if (url.pathname === '/notes.txt') return Promise.resolve(new Response('plain text'));
    return Promise.resolve(new Response('not found', { status: 404 }));
  };
  const files = new FileStore(new MemoryFileDirectory(), () =>
    Promise.resolve({ jpeg: new Uint8Array(), width: 2, height: 3 }),
  );
  writer = new EntryDraftWriter(database, { fieldTypes, files, fetch: fetchFn });
});

function fieldId(key: string) {
  return pluginFieldId(collectionId, key);
}

async function propertiesOf(pageId: string) {
  return decodePageProperties((await new PagesRepository(database).byId(pageId))?.properties ?? '{}');
}

test('stores the values that fit their field', async () => {
  const id = await writer.create(collectionId, {
    title: 'Dune',
    values: { status: 'open', code: 'ab-1', rating: 9, unknown: 'x' },
  });

  expect((await new PagesRepository(database).byId(id))?.title).toBe('Dune');
  expect(await propertiesOf(id)).toEqual({ [fieldId('status')]: 'open', [fieldId('code')]: 'AB-1' });
});

test('drops values of fields the user deleted', async () => {
  await new FieldsRepository(database).softDelete(fieldId('code'));

  const id = await writer.create(collectionId, { title: 'Dune', values: { code: 'ab-1' } });

  expect(await propertiesOf(id)).toEqual({});
});

test('finds an entry with the same unique value', async () => {
  const draft = { title: 'Dune', values: { code: 'ab-1' } };
  expect(await writer.findExisting(collectionId, draft, 'code')).toBeUndefined();

  const id = await writer.create(collectionId, draft);

  expect(await writer.findExisting(collectionId, draft, 'code')).toBe(id);
  expect(await writer.findExisting(collectionId, draft, undefined)).toBeUndefined();
  expect(await writer.findExisting(collectionId, { title: 'Dune', values: { code: 'ab-2' } }, 'code')).toBeUndefined();
});

test('attaches downloaded files the field takes, up to its maximum', async () => {
  const draft = {
    title: 'Dune',
    files: {
      cover: ['missing.png', 'notes.txt', 'cover.png', 'second.png'].map((name) => `https://example.com/${name}`),
    },
  };
  const id = await writer.create(collectionId, draft);

  await writer.attachFiles(collectionId, id, draft);

  const attachments = await new AttachmentsRepository(database).listInField(id, fieldId('cover'));
  expect(attachments).toMatchObject([{ name: 'cover.png', mime_type: 'image/png', width: 2, height: 3 }]);
  // Stops once the field is full.
  expect(downloaded).toEqual(['/missing.png', '/notes.txt', '/cover.png']);
});
