import type { AppDatabase } from '../../../core/database/app-database.ts';
import { createdBy, updatedBy } from '../../../core/database/audit.ts';
import type { Attachment } from '../../../core/database/schema.ts';

/** What an attachment records about its file, see `AttachmentsTable`. */
export type AttachmentFile = Pick<Attachment, 'file_hash' | 'name' | 'mime_type' | 'size' | 'width' | 'height'>;

export function isImage(attachment: Pick<Attachment, 'mime_type'>): boolean {
  return attachment.mime_type.startsWith('image/');
}

type Changes = Partial<Pick<Attachment, 'position' | 'deleted_at'>>;

export class AttachmentsRepository {
  readonly #database: AppDatabase;

  constructor(database: AppDatabase) {
    this.#database = database;
  }

  /** The value of a files field on a page, in order. */
  listInField(pageId: string, fieldId: string): Promise<Attachment[]> {
    return this.#database.db
      .selectFrom('attachments')
      .selectAll()
      .where('page_id', '=', pageId)
      .where('field_id', '=', fieldId)
      .where('deleted_at', 'is', null)
      .orderBy('position')
      .orderBy('id')
      .execute();
  }

  /**
   * Every active attachment of a files field across a collection's entries,
   * grouped by page id - e.g. for tile covers.
   */
  async listInFieldOfCollection(collectionId: string, fieldId: string): Promise<Map<string, Attachment[]>> {
    const rows = await this.#database.db
      .selectFrom('attachments')
      .innerJoin('pages', 'pages.id', 'attachments.page_id')
      .selectAll('attachments')
      .where('pages.collection_id', '=', collectionId)
      .where('attachments.field_id', '=', fieldId)
      .where('attachments.deleted_at', 'is', null)
      .orderBy('attachments.position')
      .orderBy('attachments.id')
      .execute();
    const byPage = new Map<string, Attachment[]>();
    for (const row of rows) byPage.set(row.page_id, [...(byPage.get(row.page_id) ?? []), row]);
    return byPage;
  }

  /** Also finds deleted ones - a block can still reference one, e.g. right after undoing its removal. */
  byId(id: string): Promise<Attachment | undefined> {
    return this.#database.db.selectFrom('attachments').selectAll().where('id', '=', id).executeTakeFirst();
  }

  /** Attachments in a page's rich text (no field), deleted ones included, see block-sync.ts. */
  allInPageContent(pageId: string): Promise<Attachment[]> {
    return this.#database.db
      .selectFrom('attachments')
      .selectAll()
      .where('page_id', '=', pageId)
      .where('field_id', 'is', null)
      .execute();
  }

  /** The hashes of all attachments' files - unless `activeOnly`, including deleted ones, which can be restored. */
  async fileHashes(activeOnly: boolean): Promise<Set<string>> {
    let query = this.#database.db.selectFrom('attachments').select('file_hash').distinct();
    if (activeOnly) query = query.where('deleted_at', 'is', null);
    return new Set((await query.execute()).map((row) => row.file_hash));
  }

  /** Appends `file` to the page's field (`fieldId`) or, with no field, to its rich text. */
  async create(options: { pageId: string; fieldId?: string | null; file: AttachmentFile }): Promise<string> {
    const id = crypto.randomUUID();
    const fieldId = options.fieldId ?? null;
    const userId = await this.#database.currentUserId();
    await this.#database.db
      .insertInto('attachments')
      .values({
        id,
        page_id: options.pageId,
        field_id: fieldId,
        ...options.file,
        position: await this.#nextPosition(options.pageId, fieldId),
        deleted_at: null,
        ...createdBy(userId),
      })
      .execute();
    return id;
  }

  /** A new attachment of `source`'s file on `pageId`, e.g. for a block pasted from another page. */
  copyTo(source: Attachment, pageId: string, fieldId: string | null = null): Promise<string> {
    const { file_hash, name, mime_type, size, width, height } = source;
    return this.create({ pageId, fieldId, file: { file_hash, name, mime_type, size, width, height } });
  }

  /** Gives the attachments `orderedIds`' order, only touching the ones whose position changes. */
  async reorderAll(orderedIds: readonly string[]): Promise<void> {
    if (orderedIds.length === 0) return;
    const rows = await this.#database.db
      .selectFrom('attachments')
      .select(['id', 'position'])
      .where('id', 'in', orderedIds)
      .execute();
    const positions = new Map(rows.map((row) => [row.id, row.position]));
    await this.#database.transaction(async (tx) => {
      const attachments = new AttachmentsRepository(tx);
      for (const [index, id] of orderedIds.entries()) {
        if (positions.get(id) !== index) await attachments.#update(id, { position: index });
      }
    });
  }

  /** The file itself stays - other attachments may share it, and this one can be restored. */
  softDelete(id: string): Promise<void> {
    return this.#update(id, { deleted_at: Date.now() });
  }

  restore(id: string): Promise<void> {
    return this.#update(id, { deleted_at: null });
  }

  async #update(id: string, changes: Changes): Promise<void> {
    const userId = await this.#database.currentUserId();
    await this.#database.db
      .updateTable('attachments')
      .set({ ...changes, ...updatedBy(userId) })
      .where('id', '=', id)
      .execute();
  }

  async #nextPosition(pageId: string, fieldId: string | null): Promise<number> {
    const { max } = await this.#database.db
      .selectFrom('attachments')
      .select((eb) => eb.fn.max('position').as('max'))
      .where('page_id', '=', pageId)
      .where('field_id', fieldId === null ? 'is' : '=', fieldId)
      .executeTakeFirstOrThrow();
    return (max ?? -1) + 1;
  }
}
