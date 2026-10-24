import { sql, type Kysely } from 'kysely';

import { MergeError, recordCount, type Changeset, type CrdtRecord } from './changeset.ts';
import { CrdtClock } from './crdt-clock.ts';
import { CrdtPlugin } from './crdt-plugin.ts';
import { Hlc } from './hlc.ts';

export interface NodeFilter {
  /** Only rows last written by this node. */
  readonly onlyNodeId?: string | undefined;
  /** Only rows last written by any other node. */
  readonly exceptNodeId?: string | undefined;
}

export interface ChangesetFilter extends NodeFilter {
  /** Only rows this node stored after that time. */
  readonly modifiedAfter?: Hlc | undefined;
}

interface TableInfo {
  readonly columns: ReadonlySet<string>;
  readonly primaryKey: readonly string[];
}

/**
 * The CRDT of one database: its clock, the {@link CrdtPlugin} that stamps
 * local writes, and changesets to exchange with other nodes. Ported from
 * `sql_crdt`'s `SqlCrdt`.
 */
export class Crdt<DB> {
  readonly clock: CrdtClock;
  readonly plugin: CrdtPlugin;
  /** Without plugins - the tables are only known by name here, and every query is raw SQL. */
  readonly #db: Kysely<DB>;
  readonly #tables: readonly string[];
  readonly #onTablesChanged: (tables: readonly string[]) => void;
  readonly #tableInfo = new Map<string, TableInfo>();

  private constructor(
    db: Kysely<DB>,
    clock: CrdtClock,
    tables: readonly string[],
    onTablesChanged: (tables: readonly string[]) => void,
  ) {
    this.#db = db;
    this.clock = clock;
    this.#tables = tables;
    this.#onTablesChanged = onTablesChanged;
    this.plugin = new CrdtPlugin({ clock, tables, onTablesChanged });
  }

  /**
   * Picks up the clock where the stored data left off - including the node
   * id, which `modified` carries. An empty database gets `nodeId` (a random
   * one by default). The tables must exist already, i.e. after migrating.
   */
  static async open<DB>(
    db: Kysely<DB>,
    options: {
      tables: readonly string[];
      nodeId?: string;
      onTablesChanged?: (tables: readonly string[]) => void;
    },
  ): Promise<Crdt<DB>> {
    const plain = db.withoutPlugins();
    const stored = await lastModified(plain, options.tables, {});
    const clock = new CrdtClock(stored ?? Hlc.zero(options.nodeId ?? crypto.randomUUID()));
    return new Crdt(plain, clock, options.tables, options.onTablesChanged ?? (() => {}));
  }

  get nodeId(): string {
    return this.clock.nodeId;
  }

  /** The newest `modified` of the matching rows, undefined if there are none. */
  getLastModified(filter: NodeFilter = {}): Promise<Hlc | undefined> {
    return lastModified(this.#db, this.#tables, filter);
  }

  /** The matching rows of every CRDT table, CRDT columns included. */
  async getChangeset(filter: ChangesetFilter = {}): Promise<Changeset> {
    const changeset: Record<string, CrdtRecord[]> = {};
    for (const table of this.#tables) {
      const conditions = nodeConditions(filter);
      // `modified` always carries this node's id, see CrdtColumns.
      const after = filter.modifiedAfter?.withNodeId(this.nodeId).toString();
      if (after !== undefined) conditions.push(sql`modified > ${after}`);
      const where = conditions.length > 0 ? sql`WHERE ${sql.join(conditions, sql` AND `)}` : sql``;
      const { rows } = await sql<CrdtRecord>`SELECT * FROM ${sql.table(table)} ${where}`.execute(this.#db);
      changeset[table] = rows;
    }
    return changeset;
  }

  /**
   * Merges another node's changeset: per row, the version with the newer
   * `hlc` wins. Idempotent and order independent, so merging the same
   * changeset twice, or several in any order, ends in the same state. All or
   * nothing - a changeset that doesn't fit throws a {@link MergeError}.
   */
  async merge(changeset: Changeset): Promise<void> {
    if (recordCount(changeset) === 0) return;
    const merged = this.#validate(changeset);
    const tables = Object.keys(changeset);
    const infos = new Map<string, TableInfo>();
    for (const table of tables) infos.set(table, await this.#info(table));

    await this.#db.transaction().execute(async (trx) => {
      for (const [table, records] of Object.entries(changeset)) {
        const info = infos.get(table);
        if (info === undefined) continue;
        for (const record of records) {
          const row: Record<string, string | number | null> = {
            ...record,
            node_id: Hlc.parse(String(record['hlc'])).nodeId,
            modified: merged.toString(),
          };
          const unknown = Object.keys(row).filter((column) => !info.columns.has(column));
          if (unknown.length > 0) {
            throw new MergeError(
              `Unknown columns in ${table}: ${unknown.join(', ')} - written by a newer app version?`,
            );
          }
          const columns = Object.keys(row);
          const updates = columns.map((column) => sql`${sql.ref(column)} = excluded.${sql.ref(column)}`);
          await sql`
            INSERT INTO ${sql.table(table)} (${sql.join(columns.map((column) => sql.ref(column)))})
            VALUES (${sql.join(columns.map((column) => row[column] ?? null))})
            ON CONFLICT (${sql.join(info.primaryKey.map((column) => sql.ref(column)))}) DO UPDATE
            SET ${sql.join(updates)}
            WHERE excluded.hlc > ${sql.table(table)}.hlc
          `.execute(trx);
        }
      }
    });

    this.clock.observe(merged);
    this.#onTablesChanged(tables);
  }

  /**
   * Checks every record's timestamp against the clock - like `crdt`'s
   * `validateChangeset` - and returns the newest, carrying this node's id.
   */
  #validate(changeset: Changeset): Hlc {
    let hlc = this.clock.canonicalTime;
    for (const [table, records] of Object.entries(changeset)) {
      if (!this.#tables.includes(table)) throw new MergeError(`Unknown table: ${table}`);
      for (const record of records) {
        const raw = record['hlc'];
        try {
          if (typeof raw !== 'string') throw new TypeError('hlc is missing');
          hlc = hlc.merge(Hlc.parse(raw));
        } catch (error) {
          throw new MergeError(`Invalid record in ${table}: ${JSON.stringify(record)}`, { cause: error });
        }
      }
    }
    return hlc;
  }

  async #info(table: string): Promise<TableInfo> {
    const cached = this.#tableInfo.get(table);
    if (cached !== undefined) return cached;
    const { rows } = await sql<{ name: string; pk: number }>`
      SELECT name, pk FROM pragma_table_info(${table})
    `.execute(this.#db);
    const info: TableInfo = {
      columns: new Set(rows.map((row) => row.name)),
      primaryKey: rows
        .filter((row) => row.pk > 0)
        .toSorted((a, b) => a.pk - b.pk)
        .map((row) => row.name),
    };
    if (info.primaryKey.length === 0) throw new MergeError(`Table ${table} has no primary key`);
    this.#tableInfo.set(table, info);
    return info;
  }
}

function nodeConditions(filter: NodeFilter) {
  const conditions = [];
  if (filter.onlyNodeId !== undefined) conditions.push(sql`node_id = ${filter.onlyNodeId}`);
  if (filter.exceptNodeId !== undefined) conditions.push(sql`node_id != ${filter.exceptNodeId}`);
  return conditions;
}

async function lastModified<DB>(
  db: Kysely<DB>,
  tables: readonly string[],
  filter: NodeFilter,
): Promise<Hlc | undefined> {
  if (tables.length === 0) return undefined;
  const conditions = nodeConditions(filter);
  const where = conditions.length > 0 ? sql`WHERE ${sql.join(conditions, sql` AND `)}` : sql``;
  const perTable = tables.map((table) => sql`SELECT max(modified) AS modified FROM ${sql.table(table)} ${where}`);
  const { rows } = await sql<{ modified: string | null }>`
    SELECT max(modified) AS modified FROM (${sql.join(perTable, sql` UNION ALL `)})
  `.execute(db);
  const modified = rows[0]?.modified;
  return modified === null || modified === undefined ? undefined : Hlc.parse(modified);
}
