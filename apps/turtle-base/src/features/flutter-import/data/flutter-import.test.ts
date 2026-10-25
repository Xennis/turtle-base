import type { FlutterAppData, SqlRow } from '@turtle-base/platform';
import { MemoryFileDirectory, streamOf } from '@turtle-base/platform/testing';
import { DatabaseSync } from 'node:sqlite';
import { beforeEach, expect, test } from 'vite-plus/test';

import type { AppDatabase } from '../../../core/database/app-database.ts';
import { openTestDatabase } from '../../../core/database/test-database.ts';
import { FileStore, fileHashOf } from '../../../packages/file-store/file-store.ts';
import { importFlutterData } from './flutter-import.ts';

/** The Flutter app's schema (drift's, with the CRDT columns sql_crdt added), as found in its databases. */
const flutterSchema = `
  CREATE TABLE users(id TEXT NOT NULL, name TEXT NOT NULL, created_at INTEGER NOT NULL, is_deleted INTEGER DEFAULT 0, hlc TEXT NOT NULL, node_id TEXT NOT NULL, modified TEXT NOT NULL, PRIMARY KEY(id));
  CREATE TABLE spaces(created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, created_by TEXT NOT NULL, updated_by TEXT NOT NULL, deleted_at INTEGER NULL, id TEXT NOT NULL, name TEXT NOT NULL, icon TEXT NULL, position INTEGER NOT NULL, is_deleted INTEGER DEFAULT 0, hlc TEXT NOT NULL, node_id TEXT NOT NULL, modified TEXT NOT NULL, PRIMARY KEY(id));
  CREATE TABLE collections(created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, created_by TEXT NOT NULL, updated_by TEXT NOT NULL, deleted_at INTEGER NULL, id TEXT NOT NULL, space_id TEXT NOT NULL REFERENCES spaces(id), name TEXT NOT NULL, icon TEXT NULL, title_field_label TEXT NULL, is_deleted INTEGER DEFAULT 0, hlc TEXT NOT NULL, node_id TEXT NOT NULL, modified TEXT NOT NULL, PRIMARY KEY(id));
  CREATE TABLE fields(created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, created_by TEXT NOT NULL, updated_by TEXT NOT NULL, deleted_at INTEGER NULL, id TEXT NOT NULL, collection_id TEXT NOT NULL REFERENCES collections(id), name TEXT NOT NULL, type TEXT NOT NULL, position INTEGER NOT NULL, config TEXT NULL, is_deleted INTEGER DEFAULT 0, hlc TEXT NOT NULL, node_id TEXT NOT NULL, modified TEXT NOT NULL, PRIMARY KEY(id));
  CREATE TABLE pages(created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, created_by TEXT NOT NULL, updated_by TEXT NOT NULL, deleted_at INTEGER NULL, id TEXT NOT NULL, space_id TEXT NOT NULL REFERENCES spaces(id), collection_id TEXT NULL REFERENCES collections(id), parent_page_id TEXT NULL REFERENCES pages(id), title TEXT NOT NULL, icon TEXT NULL, properties TEXT NOT NULL DEFAULT '{}', position INTEGER NOT NULL, is_deleted INTEGER DEFAULT 0, hlc TEXT NOT NULL, node_id TEXT NOT NULL, modified TEXT NOT NULL, PRIMARY KEY(id));
  CREATE TABLE blocks(created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, created_by TEXT NOT NULL, updated_by TEXT NOT NULL, deleted_at INTEGER NULL, id TEXT NOT NULL, page_id TEXT NOT NULL REFERENCES pages(id), parent_block_id TEXT NULL REFERENCES blocks(id), type TEXT NOT NULL, position INTEGER NOT NULL, content TEXT NOT NULL, is_deleted INTEGER DEFAULT 0, hlc TEXT NOT NULL, node_id TEXT NOT NULL, modified TEXT NOT NULL, PRIMARY KEY(id));
  CREATE TABLE attachments(created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, created_by TEXT NOT NULL, updated_by TEXT NOT NULL, deleted_at INTEGER NULL, id TEXT NOT NULL, page_id TEXT NOT NULL REFERENCES pages(id), field_id TEXT NULL REFERENCES fields(id), file_hash TEXT NOT NULL, name TEXT NOT NULL, mime_type TEXT NOT NULL, size INTEGER NOT NULL, width INTEGER NULL, height INTEGER NULL, position INTEGER NOT NULL, is_deleted INTEGER DEFAULT 0, hlc TEXT NOT NULL, node_id TEXT NOT NULL, modified TEXT NOT NULL, PRIMARY KEY(id));
`;

const crdt =
  "'2026-07-18T10:00:00.000000Z-0000-flutter-node', 'flutter-node', '2026-07-18T10:00:00.000000Z-0000-flutter-node'";
const audit = "1784321678, 1784321706, 'flutter-user', 'flutter-user'";
const picture = new Uint8Array([1, 2, 3]);
const pictureHash = fileHashOf(picture);

/** A Flutter app's data: one space with a collection, an entry with text and a picture, a page in the bin. */
class FlutterFixture implements FlutterAppData {
  readonly location = '/home/someone/.local/share/org.xennis.apps.turtle_base';
  readonly #database = new DatabaseSync(':memory:');
  readonly files = new Map<string, Uint8Array>([
    [pictureHash, picture],
    [`${pictureHash}.thumb.jpg`, new Uint8Array([9])],
    // Content that doesn't match its name - e.g. a download cut short.
    [fileHashOf(new Uint8Array([7])), new Uint8Array([8])],
  ]);

  constructor() {
    this.#database.exec(flutterSchema);
    this.#database.exec(`
      INSERT INTO users VALUES ('flutter-user', 'You', 1784321600, 0, ${crdt});
      INSERT INTO spaces VALUES (${audit}, NULL, 'space-1', 'Fitness', '💪', 0, 0, ${crdt});
      INSERT INTO collections VALUES (${audit}, NULL, 'collection-1', 'space-1', 'Workouts', NULL, NULL, 0, ${crdt});
      INSERT INTO fields VALUES (${audit}, NULL, 'field-reps', 'collection-1', 'Reps', 'number', 0, NULL, 0, ${crdt});
      INSERT INTO pages VALUES (${audit}, NULL, 'page-1', 'space-1', 'collection-1', NULL, 'Squats', NULL, '{"field-reps":"12"}', 0, 0, ${crdt});
      INSERT INTO pages VALUES (${audit}, 1784400000, 'page-binned', 'space-1', NULL, NULL, 'Old notes', NULL, '{}', 1, 0, ${crdt});
      INSERT INTO pages VALUES (${audit}, NULL, 'page-gone', 'space-1', NULL, NULL, 'Purged', NULL, '{}', 2, 1, ${crdt});
      INSERT INTO blocks VALUES (${audit}, NULL, 'block-1', 'page-1', NULL, 'heading', 0, '{"delta":[{"insert":"Form"}],"level":2}', 0, ${crdt});
      INSERT INTO blocks VALUES (${audit}, NULL, 'block-2', 'page-1', 'block-1', 'todo_list', 0, '{"delta":[{"insert":"slow"}],"checked":true}', 0, ${crdt});
      INSERT INTO blocks VALUES (${audit}, NULL, 'block-3', 'page-1', NULL, 'attachment', 1, '{"attachmentId":"attachment-1"}', 0, ${crdt});
      INSERT INTO attachments VALUES (${audit}, NULL, 'attachment-1', 'page-1', NULL, '${pictureHash}', 'form.png', 'image/png', 3, 16, 16, 0, 0, ${crdt});
    `);
  }

  query(sql: string): Promise<readonly SqlRow[]> {
    // oxlint-disable-next-line typescript/no-unsafe-type-assertion -- node:sqlite rows hold only SQLite values
    return Promise.resolve(this.#database.prepare(sql).all() as SqlRow[]);
  }

  listFiles(): Promise<string[]> {
    return Promise.resolve([...this.files.keys()]);
  }

  readFile(name: string): Promise<ReadableStream<Uint8Array>> {
    const bytes = this.files.get(name);
    return bytes === undefined ? Promise.reject(new Error(`No ${name}`)) : Promise.resolve(streamOf(bytes));
  }
}

let database: AppDatabase;
let files: FileStore;

beforeEach(async () => {
  database = await openTestDatabase('ts-node');
  files = new FileStore(new MemoryFileDirectory(), () => Promise.resolve(undefined));
});

test('takes over the rows with their ids, times in milliseconds, as changes of this device', async () => {
  const summary = await importFlutterData({ source: new FlutterFixture(), database, files });

  // The database comes with its own local user.
  expect(summary.imported).toEqual({
    users: 1,
    spaces: 1,
    collections: 1,
    fields: 1,
    pages: 2,
    blocks: 3,
    attachments: 1,
  });
  const space = await database.db
    .selectFrom('spaces')
    .selectAll()
    .where('id', '=', 'space-1')
    .executeTakeFirstOrThrow();
  expect(space).toMatchObject({ name: 'Fitness', icon: '💪', created_at: 1784321678000, created_by: 'flutter-user' });
  expect(space.node_id).toBe('ts-node');
  const page = await database.db.selectFrom('pages').selectAll().where('id', '=', 'page-1').executeTakeFirstOrThrow();
  expect(JSON.parse(page.properties)).toEqual({ 'field-reps': '12' });
  // Binned pages come along (they can be restored), pages the Flutter sync deleted for good don't.
  const binned = await database.db.selectFrom('pages').selectAll().where('id', '=', 'page-binned').executeTakeFirst();
  expect(binned?.deleted_at).toBe(1784400000000);
  expect(await database.db.selectFrom('pages').where('id', '=', 'page-gone').selectAll().executeTakeFirst()).toBe(
    undefined,
  );
});

test('turns the blocks into BlockNote blocks, keeping their tree and attachments', async () => {
  await importFlutterData({ source: new FlutterFixture(), database, files });

  const blocks = await database.db.selectFrom('blocks').selectAll().orderBy('id').execute();
  expect(blocks.map((block) => [block.id, block.type, block.parent_block_id])).toEqual([
    ['block-1', 'heading', null],
    ['block-2', 'checkListItem', 'block-1'],
    ['block-3', 'attachment', null],
  ]);
  expect(JSON.parse(blocks[1]?.content ?? '')).toMatchObject({
    props: { checked: true },
    content: [{ type: 'text', text: 'slow' }],
  });
  expect(JSON.parse(blocks[2]?.content ?? '')).toEqual({ props: { attachmentId: 'attachment-1' } });
});

test('copies the files, checked against their hashes', async () => {
  const summary = await importFlutterData({ source: new FlutterFixture(), database, files });

  expect(summary).toMatchObject({ files: 2, failedFiles: 1 });
  expect(await files.has(pictureHash)).toBe(true);
  expect(await files.has(`${pictureHash}.thumb.jpg`)).toBe(true);
});

test('adds nothing when run again', async () => {
  const source = new FlutterFixture();
  await importFlutterData({ source, database, files });

  const again = await importFlutterData({ source, database, files });

  expect(Object.values(again.imported).every((count) => count === 0)).toBe(true);
  expect(again.files).toBe(0);
});

test('refuses a database that is not the Flutter app’s', async () => {
  const source = new FlutterFixture();
  source.query = () => Promise.resolve([{ name: 'spaces' }]);

  await expect(importFlutterData({ source, database, files })).rejects.toThrow('Not a database of the Flutter app');
});
