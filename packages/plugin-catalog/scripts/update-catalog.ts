// Puts a released plugin into the catalog - or replaces its entry with the
// new release. Used by the plugin release workflow.
//
//   node packages/plugin-catalog/scripts/update-catalog.ts <catalog.json> <dist/manifest.json> <manifest URL>

import { readFile, writeFile } from 'node:fs/promises';

import { parseCatalog, parseManifest, type CatalogEntry } from '../src/index.ts';

const [catalogPath, manifestPath, manifestUrl] = process.argv.slice(2);
if (catalogPath === undefined || manifestPath === undefined || manifestUrl === undefined) {
  throw new Error('Usage: update-catalog.ts <catalog.json> <manifest.json> <manifest URL>');
}
const catalog = parseCatalog(JSON.parse(await readFile(catalogPath, 'utf8')));
const manifest = parseManifest(JSON.parse(await readFile(manifestPath, 'utf8')));

const entry: CatalogEntry = {
  id: manifest.id,
  name: manifest.name,
  author: manifest.author,
  description: manifest.description,
  ...(manifest.icon === undefined ? {} : { icon: manifest.icon }),
  manifest: manifestUrl,
  version: manifest.version,
  sha256: manifest.sha256,
};
const plugins = [...catalog.plugins.filter((plugin) => plugin.id !== entry.id), entry].toSorted((a, b) =>
  a.id.localeCompare(b.id),
);
// Validates the result, e.g. an http URL.
parseCatalog({ schemaVersion: 1, plugins });
await writeFile(catalogPath, `${JSON.stringify({ schemaVersion: 1, plugins }, null, 2)}\n`);
console.log(`${catalogPath}: ${entry.id} ${entry.version}`);
