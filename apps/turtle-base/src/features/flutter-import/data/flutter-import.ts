import type { FlutterAppData } from '@turtle-base/platform';
import * as v from 'valibot';

import type { AppDatabase } from '../../../core/database/app-database.ts';
import type { FileStore } from '../../../packages/file-store/file-store.ts';
import { blockFromAppFlowy } from './appflowy-blocks.ts';

const tables = ['users', 'spaces', 'collections', 'fields', 'pages', 'blocks', 'attachments'] as const;

export type ImportedTable = (typeof tables)[number];

export interface ImportSummary {
  /** Rows taken over per table - rows already here (an earlier import) aren't counted. */
  readonly imported: Readonly<Record<ImportedTable, number>>;
  readonly files: number;
  /** Files that couldn't be read or didn't match their name's hash. */
  readonly failedFiles: number;
}

/** Rows inserted per statement - well below SQLite's limit of bound parameters. */
const batchSize = 100;

/**
 * drift stored times as Unix seconds; the TypeScript app stores
 * milliseconds. Values that already are milliseconds are kept.
 */
const time = v.pipe(
  v.number(),
  v.transform((value) => (value < 1e11 ? value * 1000 : value)),
);

const audit = {
  created_at: time,
  updated_at: time,
  created_by: v.string(),
  updated_by: v.string(),
  deleted_at: v.nullable(time),
};

const schemas = {
  users: v.object({ id: v.string(), name: v.string(), created_at: time }),
  spaces: v.object({ ...audit, id: v.string(), name: v.string(), icon: v.nullable(v.string()), position: v.number() }),
  collections: v.object({
    ...audit,
    id: v.string(),
    space_id: v.string(),
    name: v.string(),
    icon: v.nullable(v.string()),
    title_field_label: v.nullable(v.string()),
  }),
  fields: v.object({
    ...audit,
    id: v.string(),
    collection_id: v.string(),
    name: v.string(),
    type: v.string(),
    position: v.number(),
    config: v.nullable(v.string()),
  }),
  pages: v.object({
    ...audit,
    id: v.string(),
    space_id: v.string(),
    collection_id: v.nullable(v.string()),
    parent_page_id: v.nullable(v.string()),
    title: v.string(),
    icon: v.nullable(v.string()),
    properties: v.string(),
    position: v.number(),
  }),
  blocks: v.pipe(
    v.object({
      ...audit,
      id: v.string(),
      page_id: v.string(),
      parent_block_id: v.nullable(v.string()),
      type: v.string(),
      position: v.number(),
      content: v.string(),
    }),
    // The Flutter app's editor was AppFlowy, this one's is BlockNote.
    v.transform((block) => ({ ...block, ...blockFromAppFlowy(block.type, block.content) })),
  ),
  attachments: v.object({
    ...audit,
    id: v.string(),
    page_id: v.string(),
    field_id: v.nullable(v.string()),
    file_hash: v.string(),
    name: v.string(),
    mime_type: v.string(),
    size: v.number(),
    width: v.nullable(v.number()),
    height: v.nullable(v.number()),
    position: v.number(),
  }),
} satisfies Record<ImportedTable, v.GenericSchema>;

/**
 * Takes over the Flutter app's data - once, on the desktop; other devices
 * then get it through sync. Rows keep their ids (so relations, plugin ids
 * and attachments still match) but are written as this device's changes, so
 * they sync out like new ones. The Flutter app's data is only read.
 */
export async function importFlutterData(options: {
  source: FlutterAppData;
  database: AppDatabase;
  files: FileStore;
}): Promise<ImportSummary> {
  const { source, database, files } = options;
  const found = new Set(
    (await source.query("SELECT name FROM sqlite_master WHERE type = 'table'")).map((row) => row['name']),
  );
  const missing = tables.filter((table) => !found.has(table));
  if (missing.length > 0) {
    throw new Error(`Not a database of the Flutter app - no table ${missing.join(', ')}`);
  }

  const imported = await database.transaction(async (trx) => {
    const counts: Record<ImportedTable, number> = {
      users: 0,
      spaces: 0,
      collections: 0,
      fields: 0,
      pages: 0,
      blocks: 0,
      attachments: 0,
    };
    for (const table of tables) {
      // Rows the Flutter app's sync deleted for good (is_deleted) are gone there too; soft-deleted ones
      // (deleted_at) come along, they can be restored.
      const rows = (await source.query(`SELECT * FROM ${table} WHERE is_deleted = 0`)).map((row) =>
        v.parse(schemas[table], row),
      );
      const before = await countRows(trx, table);
      for (let start = 0; start < rows.length; start += batchSize) {
        await insertBatch(trx, table, rows.slice(start, start + batchSize));
      }
      counts[table] = (await countRows(trx, table)) - before;
    }
    return counts;
  });

  let copied = 0;
  let failedFiles = 0;
  for (const name of await source.listFiles()) {
    if (await files.has(name)) continue;
    try {
      await files.put(name, await source.readFile(name));
      copied++;
    } catch (error) {
      console.warn(`[flutter-import] file ${name} not taken over:`, error);
      failedFiles++;
    }
  }
  return { imported, files: copied, failedFiles };
}

async function countRows(database: AppDatabase, table: ImportedTable): Promise<number> {
  const { count } = await database.db
    .selectFrom(table)
    .select((eb) => eb.fn.countAll<number | bigint>().as('count'))
    .executeTakeFirstOrThrow();
  return Number(count);
}

/** Inserts the rows, leaving out any whose id is already there. */
async function insertBatch(
  database: AppDatabase,
  table: ImportedTable,
  rows: readonly v.InferOutput<(typeof schemas)[ImportedTable]>[],
): Promise<void> {
  if (rows.length === 0) return;
  // Each table's rows come from its own schema above, whose columns are exactly the table's.
  // oxlint-disable-next-line typescript/no-explicit-any, typescript/no-unsafe-type-assertion, typescript/no-unsafe-argument
  await database.db
    .insertInto(table)
    .values(rows)
    .onConflict((conflict) => conflict.column('id').doNothing())
    .execute();
}
