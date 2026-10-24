import {
  AliasNode,
  PrimitiveValueListNode,
  TableNode,
  ValueListNode,
  ValuesNode,
  type ColumnNode,
  type ColumnType,
  type ColumnUpdateNode,
  type CreateTableBuilder,
  type InsertQueryNode,
  type KyselyPlugin,
  type OperationNode,
  type PluginTransformQueryArgs,
  type PluginTransformResultArgs,
  type QueryId,
  type QueryResult,
  type RootOperationNode,
  type UnknownRow,
  type UpdateQueryNode,
  type ValueNode,
  type ValuesItemNode,
} from 'kysely';

import type { CrdtClock } from './crdt-clock.ts';

/**
 * The columns every CRDT table has besides its own: the timestamp of the
 * row's last write (`hlc`), the node that made it (`node_id`), and when this
 * node last stored the row (`modified`, the own node's time - also for
 * merged rows, so "what changed here since X" is one comparison).
 */
export const crdtColumns = ['hlc', 'node_id', 'modified'] as const;

/** The {@link crdtColumns} for a table type - readable, but only ever written by this package. */
export interface CrdtColumns {
  hlc: ColumnType<string, never, never>;
  node_id: ColumnType<string, never, never>;
  modified: ColumnType<string, never, never>;
}

/** Adds the {@link crdtColumns} to a table being created. */
export function addCrdtColumns<TB extends string, C extends string>(
  builder: CreateTableBuilder<TB, C>,
): CreateTableBuilder<TB, C | (typeof crdtColumns)[number]> {
  return builder
    .addColumn('hlc', 'text', (column) => column.notNull())
    .addColumn('node_id', 'text', (column) => column.notNull())
    .addColumn('modified', 'text', (column) => column.notNull());
}

/**
 * Stamps every write to a CRDT table with the next timestamp of `clock`, so
 * code using the query builder gets sync for free - like `sql_crdt` did by
 * rewriting SQL strings, but on Kysely's query tree.
 *
 * INSERT and UPDATE (including an upsert's `DO UPDATE`) get the
 * {@link crdtColumns} set; DELETE is rejected, since a deleted row couldn't
 * be synced (the app soft-deletes via `deleted_at`). Raw `sql` statements
 * pass through untouched - writes must use the query builder.
 */
export class CrdtPlugin implements KyselyPlugin {
  readonly #clock: CrdtClock;
  readonly #tables: ReadonlySet<string>;
  readonly #onTablesChanged: (tables: readonly string[]) => void;
  readonly #written = new WeakMap<QueryId, string>();

  constructor(options: {
    clock: CrdtClock;
    /** The CRDT tables; writes to others (e.g. Kysely's migration tables) pass through. */
    tables: readonly string[];
    /** Called after each successful write, e.g. to refresh queries. */
    onTablesChanged?: (tables: readonly string[]) => void;
  }) {
    this.#clock = options.clock;
    this.#tables = new Set(options.tables);
    this.#onTablesChanged = options.onTablesChanged ?? (() => {});
  }

  transformQuery({ node, queryId }: PluginTransformQueryArgs): RootOperationNode {
    switch (node.kind) {
      case 'InsertQueryNode': {
        const table = tableName(node.into);
        if (table === undefined || !this.#tables.has(table)) return node;
        this.#written.set(queryId, table);
        return this.#stampInsert(node);
      }
      case 'UpdateQueryNode': {
        const table = tableName(node.table);
        if (table === undefined || !this.#tables.has(table)) return node;
        this.#written.set(queryId, table);
        return { ...node, updates: [...(node.updates ?? []), ...this.#stampUpdates()] } satisfies UpdateQueryNode;
      }
      case 'DeleteQueryNode': {
        const tables = node.from.froms.map(tableName);
        if (tables.some((table) => table !== undefined && this.#tables.has(table))) {
          throw new Error(`DELETE on CRDT table ${tables.join(', ')} - soft-delete via deleted_at instead`);
        }
        return node;
      }
      default:
        return node;
    }
  }

  transformResult({ queryId, result }: PluginTransformResultArgs): Promise<QueryResult<UnknownRow>> {
    const table = this.#written.get(queryId);
    if (table !== undefined) this.#onTablesChanged([table]);
    return Promise.resolve(result);
  }

  #stampInsert(node: InsertQueryNode): InsertQueryNode {
    const { columns, values, onConflict } = node;
    if (columns === undefined || values === undefined || !ValuesNode.is(values)) {
      throw new Error('CRDT inserts need explicit columns and values (no defaults, no INSERT ... SELECT)');
    }
    const [hlc, nodeId, modified] = this.#stampValues();
    const rows = values.values.map((row): ValuesItemNode => {
      if (PrimitiveValueListNode.is(row)) return { ...row, values: [...row.values, hlc, nodeId, modified] };
      if (ValueListNode.is(row)) {
        return { ...row, values: [...row.values, valueNode(hlc), valueNode(nodeId), valueNode(modified)] };
      }
      throw new Error(`Unsupported insert row: ${(row as OperationNode).kind}`);
    });
    const stamped: ValuesNode = { ...values, values: rows };
    return {
      ...node,
      columns: [...columns, ...crdtColumns.map(columnNode)],
      values: stamped,
      ...(onConflict?.updates === undefined
        ? {}
        : { onConflict: { ...onConflict, updates: [...onConflict.updates, ...this.#stampUpdates()] } }),
    };
  }

  /** A fresh timestamp per statement, written as `hlc` and `modified`. */
  #stampValues(): [string, string, string] {
    const hlc = this.#clock.next();
    return [hlc.toString(), hlc.nodeId, hlc.toString()];
  }

  #stampUpdates(): ColumnUpdateNode[] {
    const values = this.#stampValues();
    return crdtColumns.map((column, i) => ({
      kind: 'ColumnUpdateNode',
      column: columnNode(column),
      value: valueNode(values[i] ?? ''),
    }));
  }
}

function tableName(node: OperationNode | undefined): string | undefined {
  if (node === undefined) return undefined;
  if (AliasNode.is(node)) return tableName(node.node);
  return TableNode.is(node) ? node.table.identifier.name : undefined;
}

function columnNode(name: string): ColumnNode {
  return { kind: 'ColumnNode', column: { kind: 'IdentifierNode', name } };
}

function valueNode(value: string): ValueNode {
  return { kind: 'ValueNode', value };
}
