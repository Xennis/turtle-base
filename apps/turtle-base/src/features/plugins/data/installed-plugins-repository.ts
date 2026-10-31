import type { FileDirectory, KeyValueStore } from '@turtle-base/platform';
import type { PluginManifest } from '@turtle-base/plugin-api';
import { readManifest, sha256Hex } from '@turtle-base/plugin-catalog';
import * as v from 'valibot';

/** Device-local like all prefs - another device installs its plugins itself. */
const installedKey = 'installed_plugins';

/** A plugin installed on this device - its bundle lies in Platform.plugins. */
export interface InstalledPlugin {
  /** Where its manifest came from - updates are looked for there (or in the catalog). */
  readonly manifestUrl: string;
  readonly manifest: PluginManifest;

  /** Whether it was installed from the catalog, rather than from a URL nobody checked. */
  readonly fromCatalog: boolean;
}

const installedSchema = v.array(v.object({ manifestUrl: v.string(), manifest: v.unknown(), fromCatalog: v.boolean() }));

/**
 * The installed plugins: their manifests in the prefs, their bundles in a
 * {@link FileDirectory} (named `<id>-<version>.js`).
 */
export class InstalledPluginsRepository {
  readonly #prefs: KeyValueStore;
  readonly #files: FileDirectory;

  constructor(prefs: KeyValueStore, files: FileDirectory) {
    this.#prefs = prefs;
    this.#files = files;
  }

  /** In the order they were installed. A broken list reads as empty rather than stopping the app. */
  list(): InstalledPlugin[] {
    const stored = this.#prefs.get(installedKey);
    if (stored === undefined) return [];
    try {
      return v.parse(installedSchema, JSON.parse(stored)).map(({ manifestUrl, manifest, fromCatalog }) => ({
        manifestUrl,
        manifest: readManifest(manifest),
        fromCatalog,
      }));
    } catch (error) {
      console.warn('[plugins] unreadable list of installed plugins:', error);
      return [];
    }
  }

  /** The bundle's source - rejects when it's gone or doesn't match the manifest's hash. */
  async readBundle(plugin: InstalledPlugin): Promise<string> {
    const bytes = new Uint8Array(
      await new Response(await this.#files.read(bundleNameOf(plugin.manifest))).arrayBuffer(),
    );
    if ((await sha256Hex(bytes)) !== plugin.manifest.sha256) throw new Error('The installed bundle was changed');
    return new TextDecoder().decode(bytes);
  }

  /**
   * Stores the bundle, then lists the plugin - replacing an installed one of
   * the same id, whose old bundle is deleted.
   */
  async install(plugin: InstalledPlugin, source: string): Promise<void> {
    const handle = await this.#files.writeTemp(new Blob([source]).stream());
    await this.#files.commitTemp(handle, bundleNameOf(plugin.manifest));
    const list = this.list();
    const previous = list.find((installed) => installed.manifest.id === plugin.manifest.id);
    await this.#store([...list.filter((installed) => installed !== previous), plugin]);
    if (previous !== undefined && previous.manifest.version !== plugin.manifest.version) {
      await this.#files.remove(bundleNameOf(previous.manifest));
    }
  }

  async remove(id: string): Promise<void> {
    const plugin = this.list().find((installed) => installed.manifest.id === id);
    if (plugin === undefined) return;
    await this.#store(this.list().filter((installed) => installed.manifest.id !== id));
    await this.#files.remove(bundleNameOf(plugin.manifest));
  }

  async #store(plugins: readonly InstalledPlugin[]): Promise<void> {
    await this.#prefs.set(installedKey, JSON.stringify(plugins));
  }
}

function bundleNameOf(manifest: PluginManifest): string {
  return `${manifest.id}-${manifest.version}.js`;
}
