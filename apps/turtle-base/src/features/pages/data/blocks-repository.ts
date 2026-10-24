import type { AppDatabase } from '../../../core/database/app-database.ts';
import { createdBy, updatedBy } from '../../../core/database/audit.ts';
import type { Block } from '../../../core/database/schema.ts';

type Changes = Partial<Pick<Block, 'content' | 'type' | 'parent_block_id' | 'position' | 'deleted_at'>>;

export class BlocksRepository {
  readonly #database: AppDatabase;

  constructor(database: AppDatabase) {
    this.#database = database;
  }

  /**
   * Active blocks of a page, in sibling order. Blocks form a tree via
   * `parent_block_id` - this returns the flat list, rebuilding the tree for
   * rendering is left to the caller.
   */
  listActiveInPage(pageId: string): Promise<Block[]> {
    return this.#database.db
      .selectFrom('blocks')
      .selectAll()
      .where('page_id', '=', pageId)
      .where('deleted_at', 'is', null)
      .orderBy('position')
      .orderBy('id')
      .execute();
  }

  /**
   * `type` is a plain string - block types stay open-ended. `id` can be given
   * so it matches one the editor already assigned (see block-sync.ts),
   * generated if omitted.
   */
  async create(options: {
    id?: string;
    pageId: string;
    parentBlockId?: string | null;
    type: string;
    content?: string;
  }): Promise<string> {
    const id = options.id ?? crypto.randomUUID();
    const parentBlockId = options.parentBlockId ?? null;
    const userId = await this.#database.currentUserId();
    await this.#database.db
      .insertInto('blocks')
      .values({
        id,
        page_id: options.pageId,
        parent_block_id: parentBlockId,
        type: options.type,
        position: await this.#nextPosition(options.pageId, parentBlockId),
        content: options.content ?? '{}',
        deleted_at: null,
        ...createdBy(userId),
      })
      .execute();
    return id;
  }

  updateContent(id: string, content: string): Promise<void> {
    return this.#update(id, { content });
  }

  changeType(id: string, type: string): Promise<void> {
    return this.#update(id, { type });
  }

  reorder(id: string, position: number): Promise<void> {
    return this.#update(id, { position });
  }

  /** Changes both parent and position together (e.g. indenting a block into a list). */
  move(id: string, parentBlockId: string | null, position: number): Promise<void> {
    return this.#update(id, { parent_block_id: parentBlockId, position });
  }

  /** Does not cascade to nested blocks - not needed by any feature yet. */
  softDelete(id: string): Promise<void> {
    return this.#update(id, { deleted_at: Date.now() });
  }

  restore(id: string): Promise<void> {
    return this.#update(id, { deleted_at: null });
  }

  async #update(id: string, changes: Changes): Promise<void> {
    const userId = await this.#database.currentUserId();
    await this.#database.db
      .updateTable('blocks')
      .set({ ...changes, ...updatedBy(userId) })
      .where('id', '=', id)
      .execute();
  }

  async #nextPosition(pageId: string, parentBlockId: string | null): Promise<number> {
    const { max } = await this.#database.db
      .selectFrom('blocks')
      .select((eb) => eb.fn.max('position').as('max'))
      .where('page_id', '=', pageId)
      .where('parent_block_id', parentBlockId === null ? 'is' : '=', parentBlockId)
      .executeTakeFirstOrThrow();
    return (max ?? -1) + 1;
  }
}
