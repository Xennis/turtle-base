/** A value SQLite can bind and return. */
export type SqlValue = null | number | bigint | string | Uint8Array;

export type SqlRow = Readonly<Record<string, SqlValue>>;

export interface SqlResult {
  /** Empty for statements that return no rows. */
  readonly rows: readonly SqlRow[];

  /** Rows changed by an INSERT, UPDATE or DELETE. */
  readonly changes: number;
  readonly lastInsertRowid: number | bigint;
}

/**
 * One SQLite connection, as narrow as possible so every platform can offer
 * it: Electron runs it in the main process behind IPC, Capacitor through its
 * SQLite plugin, tests on `node:sqlite`. Statements run one at a time in the
 * order they're called - transactions are plain `BEGIN`/`COMMIT` statements,
 * so callers serialize them (the Kysely dialect in `sql-crdt` does).
 */
export interface SqlDriver {
  execute(sql: string, params: readonly SqlValue[]): Promise<SqlResult>;
  close(): Promise<void>;
}
