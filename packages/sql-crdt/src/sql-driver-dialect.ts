import type { SqlDriver, SqlValue } from '@turtle-base/platform';
import {
  CompiledQuery,
  SqliteAdapter,
  SqliteIntrospector,
  SqliteQueryCompiler,
  type DatabaseConnection,
  type DatabaseIntrospector,
  type Dialect,
  type DialectAdapter,
  type Driver,
  type Kysely,
  type QueryCompiler,
  type QueryResult,
} from 'kysely';

/**
 * Kysely's SQLite dialect on top of a {@link SqlDriver}, so the same typed
 * queries run on every platform. Kysely brings the SQL (adapter, compiler,
 * introspection); only the connection is ours.
 */
export class SqlDriverDialect implements Dialect {
  readonly #driver: SqlDriver;

  constructor(driver: SqlDriver) {
    this.#driver = driver;
  }

  createDriver(): Driver {
    return new SingleConnectionDriver(this.#driver);
  }

  createQueryCompiler(): QueryCompiler {
    return new SqliteQueryCompiler();
  }

  createAdapter(): DialectAdapter {
    return new SqliteAdapter();
  }

  // Kysely's own dialects take `Kysely<any>` here as well.
  // oxlint-disable-next-line typescript/no-explicit-any
  createIntrospector(db: Kysely<any>): DatabaseIntrospector {
    return new SqliteIntrospector(db);
  }
}

/**
 * Hands out the one connection to one caller at a time. Unlike
 * better-sqlite3, a {@link SqlDriver} is asynchronous, so without the lock a
 * query started elsewhere while a transaction awaits would end up inside
 * that transaction.
 */
class SingleConnectionDriver implements Driver {
  readonly #connection: SqlDriverConnection;
  #lock: Promise<void> = Promise.resolve();
  #release: (() => void) | undefined;

  constructor(driver: SqlDriver) {
    this.#connection = new SqlDriverConnection(driver);
  }

  async init(): Promise<void> {}

  async acquireConnection(): Promise<DatabaseConnection> {
    const previous = this.#lock;
    const { promise, resolve } = Promise.withResolvers<void>();
    this.#lock = promise;
    await previous;
    this.#release = resolve;
    return this.#connection;
  }

  releaseConnection(): Promise<void> {
    const release = this.#release;
    this.#release = undefined;
    release?.();
    return Promise.resolve();
  }

  async beginTransaction(connection: DatabaseConnection): Promise<void> {
    await connection.executeQuery(CompiledQuery.raw('begin'));
  }

  async commitTransaction(connection: DatabaseConnection): Promise<void> {
    await connection.executeQuery(CompiledQuery.raw('commit'));
  }

  async rollbackTransaction(connection: DatabaseConnection): Promise<void> {
    await connection.executeQuery(CompiledQuery.raw('rollback'));
  }

  async destroy(): Promise<void> {
    await this.#connection.close();
  }
}

class SqlDriverConnection implements DatabaseConnection {
  readonly #driver: SqlDriver;

  constructor(driver: SqlDriver) {
    this.#driver = driver;
  }

  async executeQuery<R>(compiledQuery: CompiledQuery): Promise<QueryResult<R>> {
    const result = await this.#driver.execute(compiledQuery.sql, compiledQuery.parameters.map(toSqlValue));
    // Kysely types the rows by the query it built; the driver can't know them.
    // oxlint-disable-next-line typescript/no-unsafe-type-assertion
    const rows = [...result.rows] as R[];
    if (rows.length > 0) return { rows };
    return {
      rows,
      numAffectedRows: BigInt(result.changes),
      insertId: BigInt(result.lastInsertRowid),
    };
  }

  async *streamQuery<R>(compiledQuery: CompiledQuery, chunkSize: number): AsyncIterableIterator<QueryResult<R>> {
    const { rows } = await this.executeQuery<R>(compiledQuery);
    for (let i = 0; i < rows.length; i += chunkSize) {
      yield { rows: rows.slice(i, i + chunkSize) };
    }
  }

  close(): Promise<void> {
    return this.#driver.close();
  }
}

/**
 * Rejects what SQLite can't store as is - e.g. a `Date` or a boolean would be
 * silently turned into something else by some drivers but not by others.
 */
function toSqlValue(value: unknown): SqlValue {
  if (
    value === null ||
    typeof value === 'number' ||
    typeof value === 'bigint' ||
    typeof value === 'string' ||
    value instanceof Uint8Array
  ) {
    return value;
  }
  throw new TypeError(`Not a SQLite value: ${typeof value}`);
}
