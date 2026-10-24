import { createNodeSqlDriver, MemoryKeyValueStore } from '@turtle-base/platform/testing';
import { Hlc } from '@turtle-base/sql-crdt';
import { sql } from 'kysely';
import { expect, test } from 'vite-plus/test';

import { AppDatabase } from './app-database.ts';
import { crdtTables } from './schema.ts';

test('creates every table as a CRDT table', async () => {
  const database = await AppDatabase.open({ sql: createNodeSqlDriver() });

  const { rows } = await sql<{ name: string }>`
    SELECT name FROM sqlite_master
    WHERE type = 'table' AND name NOT LIKE 'kysely_%' AND name NOT LIKE 'sqlite_%'
  `.execute(database.db);

  expect(rows.map((row) => row.name).toSorted()).toEqual([...crdtTables].toSorted());
});

test('seeds the local user once, stamped for sync', async () => {
  const driver = createNodeSqlDriver();
  const first = await AppDatabase.open({ sql: driver, nodeId: 'node-a' });
  await AppDatabase.open({ sql: driver });

  const users = await first.db.selectFrom('users').selectAll().execute();

  expect(users).toHaveLength(1);
  expect(users[0]?.name).toBe('You');
  expect(Hlc.parse(users[0]?.hlc ?? '').nodeId).toBe('node-a');
});

test('remembers the current user in prefs', async () => {
  const prefs = new MemoryKeyValueStore();
  const database = await AppDatabase.open({ sql: createNodeSqlDriver(), prefs });

  const userId = await database.currentUserId();

  expect(prefs.get('local_user_id')).toBe(userId);
  await database.db.insertInto('users').values({ id: 'other', name: 'Other', created_at: 0 }).execute();
  expect(await database.currentUserId()).toBe(userId);
});

test('reports writes to the tables changed', async () => {
  const changed: string[] = [];
  const database = await AppDatabase.open({
    sql: createNodeSqlDriver(),
    onTablesChanged: (tables) => changed.push(...tables),
  });

  await database.db
    .updateTable('users')
    .set({ name: 'Me' })
    .where('id', '=', await database.currentUserId())
    .execute();

  expect(changed).toEqual(['users', 'users']);
});
