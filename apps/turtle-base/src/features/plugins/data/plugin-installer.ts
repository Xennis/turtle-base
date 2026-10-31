import type { KeyValueStore } from '@turtle-base/platform';
import type { PluginManifest } from '@turtle-base/plugin-api';
import {
  catalogUrl,
  fetchBundle,
  fetchCatalog,
  fetchManifest,
  parseCatalog,
  PluginSourceError,
  type Catalog,
  type CatalogEntry,
} from '@turtle-base/plugin-catalog';

import type { InstalledPlugin, InstalledPluginsRepository } from './installed-plugins-repository.ts';
import type { PluginLoader } from './plugin-loader.ts';

/** The catalog as last fetched - so the Plugins page shows something offline. */
const catalogCacheKey = 'plugin_catalog';

/** A plugin release ready to install - shown to the user to confirm first. */
export interface PluginCandidate {
  readonly manifestUrl: string;
  readonly manifest: PluginManifest;
  readonly fromCatalog: boolean;

  /** The installed version an update replaces. */
  readonly replaces?: InstalledPlugin;
}

/**
 * Installs, updates and removes plugins - from the catalog, or from the URL
 * of any manifest. Each install is tried in the loader before it's stored,
 * and takes effect once the page reloads.
 */
export class PluginInstaller {
  readonly #fetch: typeof fetch;
  readonly #prefs: KeyValueStore;
  readonly #repository: InstalledPluginsRepository;
  readonly #loader: PluginLoader;
  readonly #catalogUrl: string;

  constructor(options: {
    fetch: typeof fetch;
    prefs: KeyValueStore;
    repository: InstalledPluginsRepository;
    loader: PluginLoader;
    catalogUrl?: string;
  }) {
    this.#fetch = options.fetch;
    this.#prefs = options.prefs;
    this.#repository = options.repository;
    this.#loader = options.loader;
    this.#catalogUrl = options.catalogUrl ?? catalogUrl;
  }

  /** The catalog as last fetched, if ever. */
  cachedCatalog(): Catalog | undefined {
    const stored = this.#prefs.get(catalogCacheKey);
    if (stored === undefined) return undefined;
    try {
      return parseCatalog(JSON.parse(stored));
    } catch {
      return undefined;
    }
  }

  /** Fetches the catalog and keeps it for {@link cachedCatalog}. */
  async refreshCatalog(): Promise<Catalog> {
    const catalog = await fetchCatalog(this.#fetch, this.#catalogUrl);
    await this.#prefs.set(catalogCacheKey, JSON.stringify({ schemaVersion: 1, ...catalog }));
    return catalog;
  }

  /** The release `entry` vouches for - rejects when its manifest says otherwise. */
  async fromCatalog(entry: CatalogEntry): Promise<PluginCandidate> {
    const manifest = await fetchManifest(this.#fetch, entry.manifest);
    for (const key of ['id', 'version', 'sha256'] as const) {
      if (manifest[key] !== entry[key]) {
        throw new PluginSourceError(`The release of ${entry.name} doesn't match the catalog (${key})`);
      }
    }
    return this.#candidate({ manifestUrl: entry.manifest, manifest, fromCatalog: true }, undefined);
  }

  /** The plugin whose manifest lies at `url` - not checked by anyone. */
  async fromUrl(url: string, catalog: Catalog | undefined): Promise<PluginCandidate> {
    const manifest = await fetchManifest(this.#fetch, url.trim());
    return this.#candidate({ manifestUrl: url.trim(), manifest, fromCatalog: false }, catalog);
  }

  /**
   * A newer release of `installed`: the catalog's version, or for a plugin
   * installed from a URL, what's at that URL now. Undefined when there's
   * none.
   */
  async updateOf(installed: InstalledPlugin, catalog: Catalog | undefined): Promise<PluginCandidate | undefined> {
    if (installed.fromCatalog) {
      const entry = catalog?.plugins.find((plugin) => plugin.id === installed.manifest.id);
      return entry === undefined || entry.version === installed.manifest.version ? undefined : this.fromCatalog(entry);
    }
    const candidate = await this.fromUrl(installed.manifestUrl, catalog);
    return candidate.manifest.version === installed.manifest.version ? undefined : candidate;
  }

  /** Downloads the bundle, tries it and stores it. Rejects without storing anything when it doesn't load. */
  async install(candidate: PluginCandidate): Promise<void> {
    const source = await fetchBundle(this.#fetch, candidate.manifestUrl, candidate.manifest);
    await this.#loader.load(source, candidate.manifest);
    const { manifestUrl, manifest, fromCatalog } = candidate;
    await this.#repository.install({ manifestUrl, manifest, fromCatalog }, source);
  }

  remove(id: string): Promise<void> {
    return this.#repository.remove(id);
  }

  /**
   * Refuses a plugin taking over the id of one from elsewhere - its id is
   * the prefix of the rows its spaces hold.
   */
  #candidate(candidate: PluginCandidate, catalog: Catalog | undefined): PluginCandidate {
    const { manifest } = candidate;
    if (!candidate.fromCatalog && catalog?.plugins.some((plugin) => plugin.id === manifest.id) === true) {
      throw new PluginSourceError(`${manifest.name} is in the catalog - install it from there`);
    }
    const installed = this.#repository.list().find((plugin) => plugin.manifest.id === manifest.id);
    if (installed === undefined) return candidate;
    if (
      installed.fromCatalog !== candidate.fromCatalog ||
      (!candidate.fromCatalog && installed.manifestUrl !== candidate.manifestUrl)
    ) {
      throw new PluginSourceError(`A plugin "${manifest.id}" from elsewhere is installed already`);
    }
    return { ...candidate, replaces: installed };
  }
}
