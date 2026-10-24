import type { CollectionTemplate, FieldVariant, TurtlePlugin } from '@turtle-base/plugin-api';

/**
 * Separates the parts of the ids a plugin's rows get, e.g.
 * `books.<uuid>.reading_list` - see plugin-api's README.
 */
export const idSeparator = '.';

export function pluginSpaceId(pluginId: string, instanceId: string): string {
  return `${pluginId}${idSeparator}${instanceId}`;
}

export function pluginCollectionId(spaceId: string, templateKey: string): string {
  return `${spaceId}${idSeparator}${templateKey}`;
}

export function pluginFieldId(collectionId: string, fieldKey: string): string {
  return `${collectionId}${idSeparator}${fieldKey}`;
}

/** Whether `spaceId` is a space created by adding the plugin `pluginId`. */
export function isPluginSpaceId(spaceId: string, pluginId: string): boolean {
  const parts = spaceId.split(idSeparator);
  return parts.length === 2 && parts[0] === pluginId;
}

/** The plugins the app ships with - registered at build time, nothing is loaded at runtime yet. */
export class PluginRegistry {
  readonly plugins: readonly TurtlePlugin[];

  /**
   * Throws for a plugin breaking the id rules of plugin-api's README - a
   * programming error, caught by any test that builds the registry.
   */
  constructor(plugins: readonly TurtlePlugin[] = []) {
    const ids = new Set<string>();
    for (const plugin of plugins) {
      checkKey(plugin.id, 'plugin id');
      if (ids.has(plugin.id)) throw new Error(`Duplicate plugin id ${plugin.id}`);
      ids.add(plugin.id);
      checkPlugin(plugin);
    }
    this.plugins = plugins;
  }

  get variants(): FieldVariant[] {
    return this.plugins.flatMap((plugin) => plugin.variants ?? []);
  }

  /** Plugins that create a space when added - one with only variants has nothing to add. */
  get addable(): TurtlePlugin[] {
    return this.plugins.filter((plugin) => (plugin.collections ?? []).length > 0);
  }

  byId(id: string): TurtlePlugin | undefined {
    return this.plugins.find((plugin) => plugin.id === id);
  }

  /**
   * The template `collectionId` was created from, undefined for a collection
   * the user created or one of a plugin this device doesn't have.
   */
  templateOf(collectionId: string): CollectionTemplate | undefined {
    const parts = collectionId.split(idSeparator);
    if (parts.length !== 3) return undefined;
    const [pluginId = '', , key] = parts;
    return this.byId(pluginId)?.collections?.find((collection) => collection.key === key);
  }
}

function checkPlugin(plugin: TurtlePlugin): void {
  for (const variant of plugin.variants ?? []) {
    if (!variant.id.startsWith(`${plugin.id}${idSeparator}`)) {
      throw new Error(`Variant ${variant.id} of plugin ${plugin.id} must start with "${plugin.id}."`);
    }
  }
  const collections = plugin.collections ?? [];
  checkUnique(
    collections.map((collection) => collection.key),
    `collection key in ${plugin.id}`,
  );
  for (const collection of collections) {
    checkUnique(
      collection.fields.map((field) => field.key),
      `field key in ${plugin.id}.${collection.key}`,
    );
    for (const field of collection.fields) {
      if (field.kind === 'select') {
        checkUnique(
          field.options.map((option) => option.key),
          `option key in ${collection.key}.${field.key}`,
        );
      }
    }
  }
}

function checkUnique(keys: readonly string[], what: string): void {
  const seen = new Set<string>();
  for (const key of keys) {
    checkKey(key, what);
    if (seen.has(key)) throw new Error(`Duplicate ${what}: ${key}`);
    seen.add(key);
  }
}

function checkKey(key: string, what: string): void {
  if (key.length === 0 || key.includes(idSeparator))
    throw new Error(`Invalid ${what} "${key}": empty or contains a dot`);
}
