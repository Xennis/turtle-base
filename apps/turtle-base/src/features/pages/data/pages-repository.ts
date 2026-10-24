import type { AppDatabase } from '../../../core/database/app-database.ts';
import { createdBy, updatedBy } from '../../../core/database/audit.ts';
import type { Page } from '../../../core/database/schema.ts';
import type { Json } from '../../tables/data/base-field-type.ts';

/**
 * Decodes a page's raw `properties` column into a map keyed by field id. Only
 * meaningful for pages that are a collection entry; anything that isn't a
 * JSON object reads as empty.
 */
export function decodePageProperties(properties: string): Record<string, unknown> {
  try {
    const decoded: unknown = JSON.parse(properties);
    return typeof decoded === 'object' && decoded !== null && !Array.isArray(decoded) ? { ...decoded } : {};
  } catch {
    return {};
  }
}

type Changes = Partial<Pick<Page, 'title' | 'icon' | 'properties' | 'space_id' | 'position' | 'deleted_at'>>;

export class PagesRepository {
  readonly #database: AppDatabase;

  constructor(database: AppDatabase) {
    this.#database = database;
  }

  /** Active entries of a collection, in row order. */
  listActiveInCollection(collectionId: string): Promise<Page[]> {
    return this.#database.db
      .selectFrom('pages')
      .selectAll()
      .where('collection_id', '=', collectionId)
      .where('deleted_at', 'is', null)
      .orderBy('position')
      .orderBy('id')
      .execute();
  }

  /**
   * Active top-level, freestanding pages of a space (not a collection entry,
   * no parent) - what the sidebar shows.
   */
  listTopLevelInSpace(spaceId: string): Promise<Page[]> {
    return this.#database.db
      .selectFrom('pages')
      .selectAll()
      .where('space_id', '=', spaceId)
      .where('collection_id', 'is', null)
      .where('parent_page_id', 'is', null)
      .where('deleted_at', 'is', null)
      .orderBy('position')
      .orderBy('id')
      .execute();
  }

  byId(id: string): Promise<Page | undefined> {
    return this.#database.db.selectFrom('pages').selectAll().where('id', '=', id).executeTakeFirst();
  }

  async create(options: {
    spaceId: string;
    collectionId?: string | null;
    parentPageId?: string | null;
    title?: string;
    icon?: string | null;
    properties?: Readonly<Record<string, Json>>;
  }): Promise<string> {
    const id = crypto.randomUUID();
    const collectionId = options.collectionId ?? null;
    const parentPageId = options.parentPageId ?? null;
    const userId = await this.#database.currentUserId();
    const position =
      collectionId === null
        ? await this.#nextPositionInSpace(options.spaceId, parentPageId)
        : await this.#nextPositionInCollection(collectionId);
    await this.#database.db
      .insertInto('pages')
      .values({
        id,
        space_id: options.spaceId,
        collection_id: collectionId,
        parent_page_id: parentPageId,
        title: options.title ?? '',
        icon: options.icon ?? null,
        properties: JSON.stringify(options.properties ?? {}),
        position,
        deleted_at: null,
        ...createdBy(userId),
      })
      .execute();
    return id;
  }

  rename(id: string, title: string): Promise<void> {
    return this.#update(id, { title });
  }

  setIcon(id: string, icon: string | null): Promise<void> {
    return this.#update(id, { icon });
  }

  /** Reads-modifies-writes the single field's value, leaving the rest of `properties` untouched. */
  async setPropertyValue(id: string, fieldId: string, value: Json): Promise<void> {
    const page = await this.#database.db
      .selectFrom('pages')
      .select('properties')
      .where('id', '=', id)
      .executeTakeFirstOrThrow();
    const properties = { ...decodePageProperties(page.properties), [fieldId]: value };
    await this.#update(id, { properties: JSON.stringify(properties) });
  }

  move(id: string, spaceId: string): Promise<void> {
    return this.#update(id, { space_id: spaceId });
  }

  reorder(id: string, position: number): Promise<void> {
    return this.#update(id, { position });
  }

  softDelete(id: string): Promise<void> {
    return this.#update(id, { deleted_at: Date.now() });
  }

  restore(id: string): Promise<void> {
    return this.#update(id, { deleted_at: null });
  }

  async #update(id: string, changes: Changes): Promise<void> {
    const userId = await this.#database.currentUserId();
    await this.#database.db
      .updateTable('pages')
      .set({ ...changes, ...updatedBy(userId) })
      .where('id', '=', id)
      .execute();
  }

  async #nextPositionInCollection(collectionId: string): Promise<number> {
    const { max } = await this.#database.db
      .selectFrom('pages')
      .select((eb) => eb.fn.max('position').as('max'))
      .where('collection_id', '=', collectionId)
      .executeTakeFirstOrThrow();
    return (max ?? -1) + 1;
  }

  async #nextPositionInSpace(spaceId: string, parentPageId: string | null): Promise<number> {
    const { max } = await this.#database.db
      .selectFrom('pages')
      .select((eb) => eb.fn.max('position').as('max'))
      .where('space_id', '=', spaceId)
      .where('collection_id', 'is', null)
      .where('parent_page_id', parentPageId === null ? 'is' : '=', parentPageId)
      .executeTakeFirstOrThrow();
    return (max ?? -1) + 1;
  }
}
