import { createNodeSqlDriver } from '@turtle-base/platform/testing';
import { Kysely } from 'kysely';
import { beforeEach, expect, test } from 'vite-plus/test';

import { CrdtClock } from './crdt-clock.ts';
import { addCrdtColumns, CrdtPlugin, type CrdtColumns } from './crdt-plugin.ts';
import { Hlc } from './hlc.ts';
import { SqlDriverDialect } from './sql-driver-dialect.ts';

interface TestDatabase {
  items: { id: string; name: string } & CrdtColumns;
  local: { key: string };
}

let clock: CrdtClock;
let changed: string[][];
let db: Kysely<TestDatabase>;

beforeEach(async () => {
  clock = new CrdtClock(Hlc.zero('node-a'));
  changed = [];
  const plain = new Kysely<TestDatabase>({ dialect: new SqlDriverDialect(createNodeSqlDriver()) });
  await addCrdtColumns(
    plain.schema
      .createTable('items')
      .addColumn('id', 'text', (column) => column.primaryKey())
      .addColumn('name', 'text', (column) => column.notNull()),
  ).execute();
  await plain.schema.createTable('local').addColumn('key', 'text').execute();
  db = plain.withPlugin(
    new CrdtPlugin({ clock, tables: ['items'], onTablesChanged: (tables) => changed.push([...tables]) }),
  );
});

function rows() {
  return db.selectFrom('items').selectAll().orderBy('id').execute();
}

test('stamps inserted rows with the next timestamp', async () => {
  await db.insertInto('items').values({ id: 'a', name: 'A' }).execute();

  const [row] = await rows();
  const hlc = Hlc.parse(row?.hlc ?? '');
  expect(hlc.nodeId).toBe('node-a');
  expect(row).toMatchObject({ node_id: 'node-a', modified: row?.hlc });
  expect(clock.canonicalTime).toEqual(hlc);
  expect(changed).toEqual([['items']]);
});

test('stamps every row of a multi-row insert alike', async () => {
  await db
    .insertInto('items')
    .values([
      { id: 'a', name: 'A' },
      { id: 'b', name: 'B' },
    ])
    .execute();

  const [a, b] = await rows();
  expect(a?.hlc).toBeDefined();
  expect(a?.hlc).toBe(b?.hlc);
});

test('stamps updates with a newer timestamp', async () => {
  await db.insertInto('items').values({ id: 'a', name: 'A' }).execute();
  const [before] = await rows();

  await db.updateTable('items').set({ name: 'B' }).where('id', '=', 'a').execute();

  const [after] = await rows();
  expect(after?.name).toBe('B');
  expect(Hlc.parse(after?.hlc ?? '').compare(Hlc.parse(before?.hlc ?? ''))).toBeGreaterThan(0);
});

test("stamps an upsert's update", async () => {
  await db.insertInto('items').values({ id: 'a', name: 'A' }).execute();
  const [before] = await rows();

  await db
    .insertInto('items')
    .values({ id: 'a', name: 'B' })
    .onConflict((conflict) => conflict.column('id').doUpdateSet({ name: 'B' }))
    .execute();

  const [after] = await rows();
  expect(after?.name).toBe('B');
  expect(after?.hlc).not.toBe(before?.hlc);
});

test('rejects deletes on CRDT tables', async () => {
  await expect(db.deleteFrom('items').where('id', '=', 'a').execute()).rejects.toThrow(/soft-delete/);
});

test('leaves other tables alone', async () => {
  await db.insertInto('local').values({ key: 'k' }).execute();
  await db.deleteFrom('local').execute();

  expect(changed).toEqual([]);
});

test('rejects inserts it cannot stamp', async () => {
  const fromSelect = db
    .insertInto('items')
    .columns(['id', 'name'])
    .expression((eb) => eb.selectFrom('local').select(['key as id', 'key as name']));

  await expect(fromSelect.execute()).rejects.toThrow(/explicit columns and values/);
});
