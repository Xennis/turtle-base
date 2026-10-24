import type { CrdtColumns } from '@turtle-base/sql-crdt';

/**
 * Standard audit and soft-delete columns shared by every business table.
 * Soft-delete keeps deleted rows recoverable instead of removing them, which
 * also avoids data loss when sync merges a delete with a concurrent edit made
 * on another device. Times are milliseconds since the epoch.
 */
export interface AuditColumns {
  created_at: number;
  updated_at: number;
  created_by: string;
  updated_by: string;
  deleted_at: number | null;
}

/**
 * Not an auth system - no passwords, no login. A row is created automatically
 * on first app start and referenced by other tables' audit columns (who
 * created/updated a record).
 */
export interface UsersTable extends CrdtColumns {
  id: string;
  name: string;
  created_at: number;
}

/** Container above collections and pages (e.g. "Default", "Fitness"). */
export interface SpacesTable extends AuditColumns, CrdtColumns {
  id: string;
  name: string;
  icon: string | null;
  position: number;
}

/**
 * A user-defined table with user-defined columns. Its columns are defined by
 * fields, its rows are pages with `collection_id` set.
 */
export interface CollectionsTable extends AuditColumns, CrdtColumns {
  id: string;
  space_id: string;
  name: string;
  icon: string | null;

  /**
   * Display label for the built-in title column (shown as "Name" by default) -
   * not a field, since every entry already has a title (see pages).
   */
  title_field_label: string | null;
}

/**
 * A column definition of a collection. Referenced by its stable id (not name)
 * from `pages.properties`, so renaming a field never touches stored data.
 */
export interface FieldsTable extends AuditColumns, CrdtColumns {
  id: string;
  collection_id: string;
  name: string;

  /** A base type id, e.g. `text` or `select`. */
  type: string;
  position: number;

  /**
   * JSON, type-specific (e.g. `targetCollectionId` for relation, the options
   * for select), plus the optional `variant` id.
   */
  config: string | null;
}

/**
 * A page is either freestanding (`collection_id` null) or a collection entry,
 * unifying the "page" and "database row" concept into one. Rich text content
 * lives in blocks.
 */
export interface PagesTable extends AuditColumns, CrdtColumns {
  id: string;
  space_id: string;
  collection_id: string | null;

  /** Nested pages are supported by the schema but not yet by the UI. */
  parent_page_id: string | null;
  title: string;
  icon: string | null;

  /** JSON `{"<field id>": value, ...}`, only meaningful for collection entries. */
  properties: string;
  position: number;
}

/**
 * A single rich-text block of a page. One block per row - rather than one
 * JSON blob per page - so sync can merge at block granularity instead of
 * overwriting a whole page.
 */
export interface BlocksTable extends AuditColumns, CrdtColumns {
  id: string;
  page_id: string;

  /** Nested blocks, e.g. a list inside a list. */
  parent_block_id: string | null;

  /** The editor's block type, e.g. `paragraph` or `heading`. */
  type: string;
  position: number;

  /** JSON, the editor's block without its children. */
  content: string;
}

/**
 * One use of a file on a page - the value (or one of the values) of a files
 * field, or a file in the page's rich text. The bytes live apart from the
 * database, named by `file_hash`, so two attachments of the same file share
 * them.
 */
export interface AttachmentsTable extends AuditColumns, CrdtColumns {
  id: string;
  page_id: string;

  /** Null for a file in the page's rich text (an attachment block). */
  field_id: string | null;

  /** `sha256-<hex>` of the content. */
  file_hash: string;

  /** The original file name. */
  name: string;
  mime_type: string;

  /** In bytes. */
  size: number;

  /** Pixel size of an image, to lay it out before it's loaded. */
  width: number | null;
  height: number | null;

  /**
   * Order within the page's field (or rich text). Ties - two devices adding
   * offline - are broken by id.
   */
  position: number;
}

export interface Database {
  users: UsersTable;
  spaces: SpacesTable;
  collections: CollectionsTable;
  fields: FieldsTable;
  pages: PagesTable;
  blocks: BlocksTable;
  attachments: AttachmentsTable;
}

/** Every table of {@link Database} - all of them sync. */
export const crdtTables = [
  'users',
  'spaces',
  'collections',
  'fields',
  'pages',
  'blocks',
  'attachments',
] as const satisfies readonly (keyof Database)[];
