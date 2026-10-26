import { DatabaseSync, type SQLInputValue } from 'node:sqlite';

import type { SqlDriver, SqlResult, SqlRow, SqlValue } from './sql-driver.ts';

/**
 * A {@link SqlDriver} on Node's built-in SQLite - an in-memory database
 * unless `path` is given. No native module - for the tests.
 */
export function createNodeSqlDriver(path = ':memory:'): SqlDriver {
  const db = new DatabaseSync(path);
  return {
    execute(sql: string, params: readonly SqlValue[]): Promise<SqlResult> {
      try {
        const statement = db.prepare(sql);
        const values: SQLInputValue[] = [...params];
        if (statement.columns().length > 0) {
          // node:sqlite's row type is a plain record of SQLite values, the same shape as SqlRow.
          const rows = statement.all(...values) as SqlRow[];
          return Promise.resolve({ rows, changes: 0, lastInsertRowid: 0 });
        }
        const { changes, lastInsertRowid } = statement.run(...values);
        return Promise.resolve({ rows: [], changes: Number(changes), lastInsertRowid });
      } catch (error) {
        return Promise.reject(error instanceof Error ? error : new Error(String(error)));
      }
    },
    close(): Promise<void> {
      db.close();
      return Promise.resolve();
    },
  };
}
