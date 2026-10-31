import type { CollectionTemplate, FieldVariant, TurtlePlugin } from '@turtle-base/plugin-api';
import { idSeparator, validatePlugin } from '@turtle-base/plugin-catalog';

export function pluginSpaceId(pluginId: string, instanceId: string): string {
  return `${pluginId}${idSeparator}${instanceId}`;
}

export function pluginCollectionId(spaceId: string, templateKey: string): string {
  return `${spaceId}${idSeparator}${templateKey}`;
}

export function pluginFieldId(collectionId: string, fieldKey: string): string {
  return `${collectionId}${idSeparator}${fieldKey}`;
}

/** The plugin a space, collection or field of a plugin was created by - for any other id, its first part. */
export function pluginIdOf(id: string): string {
  return id.split(idSeparator)[0] ?? id;
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
      validatePlugin(plugin);
      if (ids.has(plugin.id)) throw new Error(`Duplicate plugin id ${plugin.id}`);
      ids.add(plugin.id);
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
