import type { FieldTemplate, FieldVariant, TurtlePlugin } from '@turtle-base/plugin-api';

import type { AppDatabase } from '../../../core/database/app-database.ts';
import type { Space } from '../../../core/database/schema.ts';
import { SpacesRepository } from '../../spaces/data/spaces-repository.ts';
import {
  dateFieldType,
  filesAcceptKey,
  filesFieldType,
  filesMaxFilesKey,
  numberFieldType,
  numberMaxKey,
  numberMinKey,
  selectFieldType,
  textFieldType,
  type AnyFieldType,
} from '../../tables/data/base-field-type.ts';
import { CollectionsRepository } from '../../tables/data/collections-repository.ts';
import { FieldsRepository } from '../../tables/data/fields-repository.ts';
import { encodeSelectConfig } from '../../tables/data/select-field.ts';
import { isPluginSpaceId, pluginCollectionId, pluginFieldId, pluginSpaceId } from './plugin-registry.ts';

/**
 * An instance of a plugin is the space created by adding it, holding one
 * collection per template - from then on ordinary rows the user may change
 * freely. Their ids are derived from the plugin's (see plugin-registry.ts),
 * so the app recognizes them again.
 */
export class PluginInstancesRepository {
  readonly #database: AppDatabase;

  constructor(database: AppDatabase) {
    this.#database = database;
  }

  /** Active spaces created by adding `pluginId`, ordered as in the sidebar. */
  async listInstances(pluginId: string): Promise<Space[]> {
    const spaces = await new SpacesRepository(this.#database).listActive();
    return spaces.filter((space) => isPluginSpaceId(space.id, pluginId));
  }

  /** Creates a new space with the plugin's collections and their fields, all in one transaction. Returns the space's id. */
  add(plugin: TurtlePlugin): Promise<string> {
    return this.#database.transaction(async (tx) => {
      const collections = new CollectionsRepository(tx);
      const fields = new FieldsRepository(tx);
      const spaceId = await new SpacesRepository(tx).create({
        id: pluginSpaceId(plugin.id, crypto.randomUUID()),
        name: plugin.name,
        icon: plugin.icon ?? null,
      });
      for (const template of plugin.collections ?? []) {
        const collectionId = await collections.create({
          id: pluginCollectionId(spaceId, template.key),
          spaceId,
          name: template.name,
          icon: template.icon ?? null,
          titleFieldLabel: template.titleLabel ?? null,
        });
        for (const field of template.fields) {
          await fields.create({
            id: pluginFieldId(collectionId, field.key),
            collectionId,
            name: field.name,
            ...fieldTypeOf(field),
          });
        }
      }
      return spaceId;
    });
  }
}

/** The base type, variant and base type config a template stands for - what the field editor would write for the same choices. */
function fieldTypeOf(field: FieldTemplate): { type: AnyFieldType; variant?: FieldVariant; config: string | null } {
  switch (field.kind) {
    case 'text':
      return { type: textFieldType, ...(field.variant === undefined ? {} : { variant: field.variant }), config: null };
    case 'number': {
      const { min, max } = field;
      const config = {
        ...(min === undefined ? {} : { [numberMinKey]: min }),
        ...(max === undefined ? {} : { [numberMaxKey]: max }),
      };
      return { type: numberFieldType, config: Object.keys(config).length === 0 ? null : JSON.stringify(config) };
    }
    case 'date':
      return { type: dateFieldType, config: null };
    case 'select':
      return {
        type: selectFieldType,
        config: encodeSelectConfig(field.options.map(({ key, name, color }) => ({ id: key, name, color }))),
      };
    case 'files': {
      const accept = field.accept ?? [];
      const config = {
        ...(accept.length === 0 ? {} : { [filesAcceptKey]: accept }),
        ...(field.maxFiles === undefined ? {} : { [filesMaxFilesKey]: field.maxFiles }),
      };
      return { type: filesFieldType, config: Object.keys(config).length === 0 ? null : JSON.stringify(config) };
    }
  }
}
