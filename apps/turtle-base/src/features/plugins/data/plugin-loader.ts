import type { PluginManifest, TurtlePlugin } from '@turtle-base/plugin-api';
import { checkApiVersion, pluginOfModule } from '@turtle-base/plugin-catalog';

/**
 * Turns a plugin's bundle into the {@link TurtlePlugin} it exports. The one
 * place that decides how plugin code runs - in the page for now, in a
 * sandbox once the catalog takes plugins of others.
 */
export interface PluginLoader {
  /** Rejects when the bundle doesn't load or holds no valid plugin of the manifest's id. */
  load(source: string, manifest: PluginManifest): Promise<TurtlePlugin>;
}

/** Imports bundles into the page: as blob: URLs, which the CSP allows for scripts. */
export const pagePluginLoader: PluginLoader = {
  async load(source, manifest) {
    checkApiVersion(manifest);
    const url = URL.createObjectURL(new Blob([source], { type: 'text/javascript' }));
    try {
      return pluginOfModule(await import(/* @vite-ignore */ url), manifest);
    } finally {
      URL.revokeObjectURL(url);
    }
  },
};
