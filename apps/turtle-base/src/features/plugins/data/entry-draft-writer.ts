import type { EntryDraft } from '@turtle-base/plugin-api';

import type { AppDatabase } from '../../../core/database/app-database.ts';
import type { FileStore } from '../../../packages/file-store/file-store.ts';
import { AttachmentsRepository } from '../../files/data/attachments-repository.ts';
import { decodePageProperties, PagesRepository } from '../../pages/data/pages-repository.ts';
import type { Json } from '../../tables/data/base-field-type.ts';
import { CollectionsRepository } from '../../tables/data/collections-repository.ts';
import type { FieldTypeRegistry } from '../../tables/data/field-type-registry.ts';
import { FieldsRepository } from '../../tables/data/fields-repository.ts';
import type { ResolvedField } from '../../tables/data/resolved-field.ts';
import { pluginFieldId } from './plugin-registry.ts';

/**
 * Turns an {@link EntryDraft} a plugin's lookup found into an entry of the
 * plugin's collection - through the same checks as the user's input, so a
 * field the user deleted or changed since only drops its value.
 */
export class EntryDraftWriter {
  readonly #database: AppDatabase;
  readonly #fieldTypes: FieldTypeRegistry;
  readonly #files: FileStore;
  readonly #fetch: typeof fetch;

  constructor(
    database: AppDatabase,
    options: { fieldTypes: FieldTypeRegistry; files: FileStore; fetch: typeof fetch },
  ) {
    this.#database = database;
    this.#fieldTypes = options.fieldTypes;
    this.#files = options.files;
    this.#fetch = options.fetch;
  }

  /**
   * An active entry with the same value of `uniqueFieldKey` as `draft`, so
   * picking a result twice opens it instead of adding a copy. Undefined when
   * there's none, or no such field (anymore).
   */
  async findExisting(
    collectionId: string,
    draft: EntryDraft,
    uniqueFieldKey: string | undefined,
  ): Promise<string | undefined> {
    if (uniqueFieldKey === undefined) return undefined;
    const field = (await this.#fieldsByKey(collectionId)).get(uniqueFieldKey);
    const value = field?.storedFor(draft.values?.[uniqueFieldKey]);
    if (field === undefined || value === undefined) return undefined;
    const entries = await new PagesRepository(this.#database).listActiveInCollection(collectionId);
    return entries.find((entry) => decodePageProperties(entry.properties)[field.id] === value)?.id;
  }

  /** Creates the entry with the draft's title and values, without its files - see {@link attachFiles}. */
  async create(collectionId: string, draft: EntryDraft): Promise<string> {
    const fields = await this.#fieldsByKey(collectionId);
    const properties: Record<string, Json> = {};
    for (const [key, raw] of Object.entries(draft.values ?? {})) {
      const field = fields.get(key);
      const stored = field?.storedFor(raw);
      if (field !== undefined && stored !== undefined) properties[field.id] = stored;
    }
    const collection = await new CollectionsRepository(this.#database).byId(collectionId);
    if (collection === undefined) throw new Error(`No collection ${collectionId}`);
    return new PagesRepository(this.#database).create({
      spaceId: collection.space_id,
      collectionId,
      title: draft.title,
      properties,
    });
  }

  /**
   * Downloads the draft's files into their files fields, checked against the
   * field's `accept` and `maxFiles` like picked files. A file that fails is
   * skipped - the entry stays without it.
   */
  async attachFiles(collectionId: string, pageId: string, draft: EntryDraft): Promise<void> {
    const fields = await this.#fieldsByKey(collectionId);
    const attachments = new AttachmentsRepository(this.#database);
    for (const [fieldKey, urls] of Object.entries(draft.files ?? {})) {
      const field = fields.get(fieldKey);
      if (field?.typed.kind !== 'files') continue;
      const { accept, maxFiles } = field.typed.config;
      let count = (await attachments.listInField(pageId, field.id)).length;
      for (const url of urls) {
        if (maxFiles !== undefined && count >= maxFiles) break;
        try {
          const response = await this.#fetch(url);
          if (response.status !== 200 || response.body === null) throw new Error(`HTTP ${response.status}`);
          const name = new URL(url).pathname.split('/').findLast((segment) => segment.length > 0) ?? 'download';
          const stored = await this.#files.import({ name, bytes: response.body });
          if (!accept.accepts({ mimeType: stored.mimeType, fileName: name })) continue;
          await attachments.create({
            pageId,
            fieldId: field.id,
            file: {
              file_hash: stored.hash,
              name,
              mime_type: stored.mimeType,
              size: stored.size,
              width: stored.width,
              height: stored.height,
            },
          });
          count++;
        } catch (error) {
          console.warn(`[plugins] no file from ${url}:`, error);
        }
      }
    }
  }

  /** The collection's active fields created from the template, by their key - fields the user added have no key. */
  async #fieldsByKey(collectionId: string): Promise<Map<string, ResolvedField>> {
    const prefix = pluginFieldId(collectionId, '');
    const rows = await new FieldsRepository(this.#database).listActiveInCollection(collectionId);
    return new Map(
      rows
        .filter((row) => row.id.startsWith(prefix))
        .map((row) => [row.id.slice(prefix.length), this.#fieldTypes.resolve(row)]),
    );
  }
}
