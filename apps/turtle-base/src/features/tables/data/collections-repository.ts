import type { AppDatabase } from '../../../core/database/app-database.ts';
import { createdBy, updatedBy } from '../../../core/database/audit.ts';
import type { Collection } from '../../../core/database/schema.ts';

type Changes = Partial<Pick<Collection, 'name' | 'icon' | 'title_field_label' | 'space_id' | 'deleted_at'>>;

export class CollectionsRepository {
  readonly #database: AppDatabase;

  constructor(database: AppDatabase) {
    this.#database = database;
  }

  /**
   * Active (non-deleted) collections of a space, in creation order.
   * Collections have no explicit position - unlike spaces, reordering them
   * was not part of the requirements.
   */
  listActiveInSpace(spaceId: string): Promise<Collection[]> {
    return this.#database.db
      .selectFrom('collections')
      .selectAll()
      .where('space_id', '=', spaceId)
      .where('deleted_at', 'is', null)
      .orderBy('created_at')
      .orderBy('id')
      .execute();
  }

  byId(id: string): Promise<Collection | undefined> {
    return this.#database.db.selectFrom('collections').selectAll().where('id', '=', id).executeTakeFirst();
  }

  /** `id` defaults to a fresh uuid - plugins derive theirs (see PluginInstancesRepository). */
  async create(options: {
    spaceId: string;
    name: string;
    icon?: string | null;
    titleFieldLabel?: string | null;
    id?: string;
  }): Promise<string> {
    const id = options.id ?? crypto.randomUUID();
    const userId = await this.#database.currentUserId();
    await this.#database.db
      .insertInto('collections')
      .values({
        id,
        space_id: options.spaceId,
        name: options.name,
        icon: options.icon ?? null,
        title_field_label: options.titleFieldLabel ?? null,
        deleted_at: null,
        ...createdBy(userId),
      })
      .execute();
    return id;
  }

  rename(id: string, name: string): Promise<void> {
    return this.#update(id, { name });
  }

  setIcon(id: string, icon: string | null): Promise<void> {
    return this.#update(id, { icon });
  }

  /**
   * Label for the built-in title column (shown as "Name" if null or empty) -
   * not a field, see `CollectionsTable.title_field_label`.
   */
  setTitleFieldLabel(id: string, label: string | null): Promise<void> {
    return this.#update(id, { title_field_label: label });
  }

  move(id: string, spaceId: string): Promise<void> {
    return this.#update(id, { space_id: spaceId });
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
      .updateTable('collections')
      .set({ ...changes, ...updatedBy(userId) })
      .where('id', '=', id)
      .execute();
  }
}
