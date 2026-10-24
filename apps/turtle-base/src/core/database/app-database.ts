import type { KeyValueStore, SqlDriver } from '@turtle-base/platform';
import { Crdt, SqlDriverDialect } from '@turtle-base/sql-crdt';
import { Kysely } from 'kysely';
import { Migrator } from 'kysely/migration';

import { migrationProvider } from './migrations/migrations.ts';
import { crdtTables, type Database } from './schema.ts';

/** Where `prefs` keeps which `users` row this device considers itself. */
const localUserIdKey = 'local_user_id';

/**
 * The app's database: migrated, with every write going through the CRDT
 * plugin, so repositories get sync tracking without knowing about it.
 */
export class AppDatabase {
  /** Typed queries - writes are stamped for sync. */
  readonly db: Kysely<Database>;
  readonly crdt: Crdt<Database>;
  readonly #prefs: KeyValueStore | undefined;
  /** Shared with the instances {@link transaction} hands out. */
  readonly #identity: { userId?: string };

  private constructor(
    db: Kysely<Database>,
    crdt: Crdt<Database>,
    prefs: KeyValueStore | undefined,
    identity: { userId?: string } = {},
  ) {
    this.db = db;
    this.crdt = crdt;
    this.#prefs = prefs;
    this.#identity = identity;
  }

  /**
   * Runs `work` in one transaction: everything it writes through the
   * database it's handed lands together or not at all. Repositories created
   * on that database take part; the outer one must not be used meanwhile -
   * it waits for the transaction's connection.
   */
  transaction<T>(work: (database: AppDatabase) => Promise<T>): Promise<T> {
    return this.db.transaction().execute((trx) => work(new AppDatabase(trx, this.crdt, this.#prefs, this.#identity)));
  }

  /**
   * `prefs` persists {@link currentUserId} across restarts; without it, it's
   * only cached in memory - enough for tests simulating several devices in
   * one process. `onTablesChanged` hears about every local write and merge.
   */
  static async open(options: {
    sql: SqlDriver;
    prefs?: KeyValueStore;
    onTablesChanged?: (tables: readonly string[]) => void;
    nodeId?: string;
  }): Promise<AppDatabase> {
    const plain = new Kysely<Database>({ dialect: new SqlDriverDialect(options.sql) });
    const { error, results = [] } = await new Migrator({ db: plain, provider: migrationProvider }).migrateToLatest();
    if (error !== undefined) {
      throw new Error('Migrating the database failed', { cause: error });
    }

    const crdt = await Crdt.open(plain, {
      tables: crdtTables,
      ...(options.onTablesChanged === undefined ? {} : { onTablesChanged: options.onTablesChanged }),
      ...(options.nodeId === undefined ? {} : { nodeId: options.nodeId }),
    });
    const database = new AppDatabase(plain.withPlugin(crdt.plugin), crdt, options.prefs);
    const created = results.some((result) => result.migrationName === '0001-initial' && result.status === 'Success');
    if (created) await database.#seedDefaults();
    return database;
  }

  /**
   * Runs once, when the database is created. There is no login - a local
   * user profile always exists from the first start. No space is seeded: a
   * fresh device may be about to sync in existing spaces from elsewhere, so
   * the UI offers "create a space" and "go to Settings to sync" instead.
   */
  async #seedDefaults(): Promise<void> {
    await this.db
      .insertInto('users')
      .values({ id: crypto.randomUUID(), name: 'You', created_at: Date.now() })
      .execute();
  }

  /**
   * Which `users` row this device considers itself, for the audit columns.
   * Remembered in `prefs` rather than looked up as "the" row, because sync
   * merges in other devices' users.
   */
  async currentUserId(): Promise<string> {
    const known = this.#identity.userId ?? this.#prefs?.get(localUserIdKey);
    if (known !== undefined) {
      this.#identity.userId = known;
      return known;
    }
    // First time this device resolves its identity: creating the database
    // seeds exactly one row before sync can bring in others, so the row
    // found here is this device's own. If sync somehow got there first,
    // there is no telling which row is - the first one is adopted.
    const row = await this.db.selectFrom('users').select('id').orderBy('created_at').executeTakeFirstOrThrow();
    await this.#prefs?.set(localUserIdKey, row.id);
    this.#identity.userId = row.id;
    return row.id;
  }

  close(): Promise<void> {
    return this.db.destroy();
  }
}
