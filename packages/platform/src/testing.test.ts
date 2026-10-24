import { expect, test } from 'vite-plus/test';

import { bytesOf, createNodeSqlDriver, MemoryFileDirectory, streamOf } from './testing.ts';

test('returns rows for queries and changes for writes', async () => {
  const driver = createNodeSqlDriver();
  await driver.execute('CREATE TABLE t (id TEXT PRIMARY KEY, n INTEGER)', []);

  const insert = await driver.execute('INSERT INTO t (id, n) VALUES (?, ?)', ['a', 1]);
  const update = await driver.execute('UPDATE t SET n = n + 1', []);
  const select = await driver.execute('SELECT id, n FROM t', []);

  expect(insert).toEqual({ rows: [], changes: 1, lastInsertRowid: 1 });
  expect(update.changes).toBe(1);
  expect(select.rows).toEqual([{ id: 'a', n: 2 }]);
  await driver.close();
});

test('returns the rows of a write with RETURNING', async () => {
  const driver = createNodeSqlDriver();
  await driver.execute('CREATE TABLE t (id TEXT PRIMARY KEY)', []);

  const result = await driver.execute('INSERT INTO t (id) VALUES (?) RETURNING id', ['a']);

  expect(result.rows).toEqual([{ id: 'a' }]);
});

test('rejects on invalid SQL', async () => {
  const driver = createNodeSqlDriver();

  await expect(driver.execute('SELEKT 1', [])).rejects.toThrow(/syntax error/);
});

test('a memory file directory names temporary files on commit', async () => {
  const files = new MemoryFileDirectory();

  const handle = await files.writeTemp(streamOf(new Uint8Array([1, 2, 3])));
  expect(await files.list()).toEqual([]);
  await files.commitTemp(handle, 'abc');

  expect(await files.list()).toEqual(['abc']);
  expect(await files.size('abc')).toBe(3);
  expect(await files.readHead('abc', 2)).toEqual(new Uint8Array([1, 2]));
  expect(await bytesOf(await files.read('abc'))).toEqual(new Uint8Array([1, 2, 3]));
  expect(files.pendingTemps).toBe(0);
});
