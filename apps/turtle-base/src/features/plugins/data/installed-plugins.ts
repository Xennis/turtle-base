import type { TurtlePlugin } from '@turtle-base/plugin-api';

import type { InstalledPlugin, InstalledPluginsRepository } from './installed-plugins-repository.ts';
import type { PluginLoader } from './plugin-loader.ts';

export interface LoadedPlugin {
  readonly installed: InstalledPlugin;
  readonly plugin: TurtlePlugin;
}

export interface BrokenPlugin {
  readonly installed: InstalledPlugin;

  /** Why it didn't load - shown on its card. */
  readonly error: string;
}

/**
 * The installed plugins as loaded at start - those that loaded, and those
 * that didn't (the app starts without them). Installing or removing one
 * reloads the page, so this never changes while it runs.
 */
export class InstalledPlugins {
  readonly loaded: readonly LoadedPlugin[];
  readonly broken: readonly BrokenPlugin[];

  constructor(loaded: readonly LoadedPlugin[] = [], broken: readonly BrokenPlugin[] = []) {
    this.loaded = loaded;
    this.broken = broken;
  }

  /** Loads each installed plugin from its stored bundle - offline. */
  static async load(repository: InstalledPluginsRepository, loader: PluginLoader): Promise<InstalledPlugins> {
    const loaded: LoadedPlugin[] = [];
    const broken: BrokenPlugin[] = [];
    for (const installed of repository.list()) {
      try {
        const plugin = await loader.load(await repository.readBundle(installed), installed.manifest);
        loaded.push({ installed, plugin });
      } catch (error) {
        console.warn(`[plugins] ${installed.manifest.id} didn't load:`, error);
        broken.push({ installed, error: error instanceof Error ? error.message : String(error) });
      }
    }
    return new InstalledPlugins(loaded, broken);
  }

  get plugins(): TurtlePlugin[] {
    return this.loaded.map(({ plugin }) => plugin);
  }

  /** All installed plugins, loaded or not, by id. */
  byId(id: string): InstalledPlugin | undefined {
    return [...this.loaded, ...this.broken].find(({ installed }) => installed.manifest.id === id)?.installed;
  }

  /**
   * The hosts plugin `id` may reach - see PluginPermissions. Undefined for a
   * plugin built into the app.
   */
  hostsOf(id: string): readonly string[] | undefined {
    const installed = this.byId(id);
    return installed === undefined ? undefined : (installed.manifest.permissions.network ?? []);
  }
}
