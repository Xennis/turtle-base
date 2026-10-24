import { addCrdtColumns } from '@turtle-base/sql-crdt';
import type { CreateTableBuilder, Kysely } from 'kysely';
import type { Migration } from 'kysely/migration';

/**
 * The schema of the Flutter app's last version (drift schema 3), with times
 * in milliseconds and the CRDT columns written out.
 *
 * No foreign key constraints: sync merges rows in any order, so a page can
 * arrive before its space.
 */
export const initial: Migration = {
  async up(db: Kysely<unknown>) {
    await addCrdtColumns(
      db.schema
        .createTable('users')
        .addColumn('id', 'text', (column) => column.primaryKey())
        .addColumn('name', 'text', (column) => column.notNull())
        .addColumn('created_at', 'integer', (column) => column.notNull()),
    ).execute();

    await auditedTable(db, 'spaces', (table) =>
      table
        .addColumn('name', 'text', (column) => column.notNull())
        .addColumn('icon', 'text')
        .addColumn('position', 'integer', (column) => column.notNull()),
    );

    await auditedTable(db, 'collections', (table) =>
      table
        .addColumn('space_id', 'text', (column) => column.notNull())
        .addColumn('name', 'text', (column) => column.notNull())
        .addColumn('icon', 'text')
        .addColumn('title_field_label', 'text'),
    );

    await auditedTable(db, 'fields', (table) =>
      table
        .addColumn('collection_id', 'text', (column) => column.notNull())
        .addColumn('name', 'text', (column) => column.notNull())
        .addColumn('type', 'text', (column) => column.notNull())
        .addColumn('position', 'integer', (column) => column.notNull())
        .addColumn('config', 'text'),
    );
    await db.schema.createIndex('fields_collection_id').on('fields').column('collection_id').execute();

    await auditedTable(db, 'pages', (table) =>
      table
        .addColumn('space_id', 'text', (column) => column.notNull())
        .addColumn('collection_id', 'text')
        .addColumn('parent_page_id', 'text')
        .addColumn('title', 'text', (column) => column.notNull())
        .addColumn('icon', 'text')
        .addColumn('properties', 'text', (column) => column.notNull().defaultTo('{}'))
        .addColumn('position', 'integer', (column) => column.notNull()),
    );
    await db.schema.createIndex('pages_space_id').on('pages').column('space_id').execute();
    await db.schema.createIndex('pages_collection_id').on('pages').column('collection_id').execute();

    await auditedTable(db, 'blocks', (table) =>
      table
        .addColumn('page_id', 'text', (column) => column.notNull())
        .addColumn('parent_block_id', 'text')
        .addColumn('type', 'text', (column) => column.notNull())
        .addColumn('position', 'integer', (column) => column.notNull())
        .addColumn('content', 'text', (column) => column.notNull()),
    );
    await db.schema.createIndex('blocks_page_id').on('blocks').column('page_id').execute();

    await auditedTable(db, 'attachments', (table) =>
      table
        .addColumn('page_id', 'text', (column) => column.notNull())
        .addColumn('field_id', 'text')
        .addColumn('file_hash', 'text', (column) => column.notNull())
        .addColumn('name', 'text', (column) => column.notNull())
        .addColumn('mime_type', 'text', (column) => column.notNull())
        .addColumn('size', 'integer', (column) => column.notNull())
        .addColumn('width', 'integer')
        .addColumn('height', 'integer')
        .addColumn('position', 'integer', (column) => column.notNull()),
    );
    await db.schema.createIndex('attachments_page_id').on('attachments').column('page_id').execute();
  },
};

/** A table with an `id` primary key, its own columns, the audit and the CRDT columns. */
function auditedTable(
  db: Kysely<unknown>,
  name: string,
  columns: (table: CreateTableBuilder<string, 'id'>) => CreateTableBuilder<string, string>,
): Promise<void> {
  const table = columns(db.schema.createTable(name).addColumn('id', 'text', (column) => column.primaryKey()))
    .addColumn('created_at', 'integer', (column) => column.notNull())
    .addColumn('updated_at', 'integer', (column) => column.notNull())
    .addColumn('created_by', 'text', (column) => column.notNull())
    .addColumn('updated_by', 'text', (column) => column.notNull())
    .addColumn('deleted_at', 'integer');
  return addCrdtColumns(table).execute();
}
