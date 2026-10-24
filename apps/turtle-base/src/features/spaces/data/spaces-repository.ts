import type { AppDatabase } from '../../../core/database/app-database.ts';
import { createdBy, updatedBy } from '../../../core/database/audit.ts';
import type { Space } from '../../../core/database/schema.ts';

export class SpacesRepository {
  readonly #database: AppDatabase;

  constructor(database: AppDatabase) {
    this.#database = database;
  }

  /** Active (non-deleted) spaces, ordered as shown in the sidebar. */
  listActive(): Promise<Space[]> {
    return this.#database.db
      .selectFrom('spaces')
      .selectAll()
      .where('deleted_at', 'is', null)
      .orderBy('position')
      .execute();
  }

  /** `id` defaults to a fresh uuid - plugins derive theirs (see PluginInstancesRepository). */
  async create(options: { name: string; icon?: string | null; id?: string }): Promise<string> {
    const { db } = this.#database;
    const id = options.id ?? crypto.randomUUID();
    const userId = await this.#database.currentUserId();
    await db
      .insertInto('spaces')
      .values({
        id,
        name: options.name,
        icon: options.icon ?? null,
        position: await this.#nextPosition(),
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

  reorder(id: string, position: number): Promise<void> {
    return this.#update(id, { position });
  }

  softDelete(id: string): Promise<void> {
    return this.#update(id, { deleted_at: Date.now() });
  }

  restore(id: string): Promise<void> {
    return this.#update(id, { deleted_at: null });
  }

  async #update(id: string, changes: Partial<Pick<Space, 'name' | 'icon' | 'position' | 'deleted_at'>>) {
    const userId = await this.#database.currentUserId();
    await this.#database.db
      .updateTable('spaces')
      .set({ ...changes, ...updatedBy(userId) })
      .where('id', '=', id)
      .execute();
  }

  async #nextPosition(): Promise<number> {
    const { max } = await this.#database.db
      .selectFrom('spaces')
      .select((eb) => eb.fn.max('position').as('max'))
      .executeTakeFirstOrThrow();
    return (max ?? -1) + 1;
  }
}
