import { createNodeSqlDriver } from '@turtle-base/platform/testing';
import { Kysely } from 'kysely';
import { beforeEach, expect, test } from 'vite-plus/test';

import { SqlDriverDialect } from './sql-driver-dialect.ts';

interface TestDatabase {
  items: { id: string; n: number };
}

let db: Kysely<TestDatabase>;

beforeEach(async () => {
  db = new Kysely<TestDatabase>({ dialect: new SqlDriverDialect(createNodeSqlDriver()) });
  await db.schema
    .createTable('items')
    .addColumn('id', 'text', (column) => column.primaryKey())
    .addColumn('n', 'integer', (column) => column.notNull())
    .execute();
});

test('runs typed queries', async () => {
  const inserted = await db.insertInto('items').values({ id: 'a', n: 1 }).executeTakeFirst();
  const updated = await db.updateTable('items').set({ n: 2 }).where('id', '=', 'a').executeTakeFirst();

  expect(inserted.numInsertedOrUpdatedRows).toBe(1n);
  expect(updated.numUpdatedRows).toBe(1n);
  expect(await db.selectFrom('items').selectAll().execute()).toEqual([{ id: 'a', n: 2 }]);
});

test('rolls back a failed transaction', async () => {
  const failing = db.transaction().execute(async (trx) => {
    await trx.insertInto('items').values({ id: 'a', n: 1 }).execute();
    throw new Error('abort');
  });

  await expect(failing).rejects.toThrow('abort');
  expect(await db.selectFrom('items').selectAll().execute()).toEqual([]);
});

test('keeps queries started meanwhile out of a transaction', async () => {
  const { promise: inside, resolve: entered } = Promise.withResolvers<void>();
  const { promise: proceed, resolve: release } = Promise.withResolvers<void>();
  const transaction = db.transaction().execute(async (trx) => {
    await trx.insertInto('items').values({ id: 'in', n: 1 }).execute();
    entered();
    await proceed;
    throw new Error('abort');
  });

  await inside;
  const outside = db.insertInto('items').values({ id: 'out', n: 1 }).execute();
  release();

  await expect(transaction).rejects.toThrow('abort');
  await outside;
  expect(await db.selectFrom('items').select('id').execute()).toEqual([{ id: 'out' }]);
});

test('rejects values SQLite cannot store as they are', async () => {
  const loose = db.withTables<{ loose: { id: string; n: unknown } }>();
  await loose.schema.createTable('loose').addColumn('id', 'text').addColumn('n', 'integer').execute();

  const insert = loose.insertInto('loose').values({ id: 'a', n: true }).execute();

  await expect(insert).rejects.toThrow(TypeError);
});
