import { DatabaseSync, type SQLInputValue } from 'node:sqlite';

import type { KeyValueStore, SecretStorage } from './key-value-store.ts';
import type { SqlDriver, SqlResult, SqlRow, SqlValue } from './sql-driver.ts';

/**
 * A {@link SqlDriver} on Node's built-in SQLite - an in-memory database
 * unless `path` is given. No native module, so tests run anywhere Node does.
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

export class MemoryKeyValueStore implements KeyValueStore {
  readonly #values = new Map<string, string>();

  get(key: string): string | undefined {
    return this.#values.get(key);
  }

  set(key: string, value: string): Promise<void> {
    this.#values.set(key, value);
    return Promise.resolve();
  }

  remove(key: string): Promise<void> {
    this.#values.delete(key);
    return Promise.resolve();
  }
}

export class MemorySecretStorage implements SecretStorage {
  readonly #values = new Map<string, string>();

  get(key: string): Promise<string | undefined> {
    return Promise.resolve(this.#values.get(key));
  }

  set(key: string, value: string): Promise<void> {
    this.#values.set(key, value);
    return Promise.resolve();
  }

  remove(key: string): Promise<void> {
    this.#values.delete(key);
    return Promise.resolve();
  }
}
