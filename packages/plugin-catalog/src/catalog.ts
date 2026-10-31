import * as v from 'valibot';

import { fetchJson, PluginSourceError } from './manifest.ts';

/** The plugin catalog of this repo, as the app fetches it. */
export const catalogUrl = 'https://raw.githubusercontent.com/Xennis/turtle-base/main/catalog/catalog.json';

/** A plugin of the catalog - the version it vouches for, pinned by the bundle's hash. */
export interface CatalogEntry {
  readonly id: string;
  readonly name: string;
  readonly author: string;
  readonly description: string;
  readonly icon?: string;

  /** An https URL of the release's `manifest.json`. */
  readonly manifest: string;
  readonly version: string;
  readonly sha256: string;
}

export interface Catalog {
  readonly plugins: readonly CatalogEntry[];
}

const entrySchema = v.object({
  id: v.string(),
  name: v.string(),
  author: v.string(),
  description: v.string(),
  icon: v.optional(v.string()),
  manifest: v.pipe(v.string(), v.url(), v.startsWith('https://')),
  version: v.string(),
  sha256: v.pipe(v.string(), v.regex(/^[0-9a-f]{64}$/)),
});

export const catalogSchema = v.object({
  schemaVersion: v.literal(1),
  plugins: v.array(entrySchema),
});

/** Parses a catalog. Throws a {@link PluginSourceError} for a broken one or one with an id twice. */
export function parseCatalog(value: unknown): Catalog {
  const result = v.safeParse(catalogSchema, value);
  if (!result.success) {
    const issue = result.issues[0];
    throw new PluginSourceError(`Invalid catalog: ${v.getDotPath(issue) ?? 'value'}: ${issue.message}`);
  }
  const ids = new Set<string>();
  const plugins = result.output.plugins.map(({ icon, ...entry }) => {
    if (ids.has(entry.id)) throw new PluginSourceError(`Invalid catalog: ${entry.id} is listed twice`);
    ids.add(entry.id);
    return { ...entry, ...(icon === undefined ? {} : { icon }) };
  });
  return { plugins };
}

export async function fetchCatalog(fetchFn: typeof fetch, url = catalogUrl): Promise<Catalog> {
  return parseCatalog(await fetchJson(fetchFn, url, 'catalog'));
}
