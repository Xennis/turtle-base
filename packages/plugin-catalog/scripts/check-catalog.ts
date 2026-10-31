// Checks a catalog against the releases it points to: each manifest
// matches its entry, each bundle its hash, and each bundle exports a valid
// plugin of that id. Runs the bundles - fine while the catalog holds only
// this repo's plugins, a sandbox's job before it takes others.
//
//   node packages/plugin-catalog/scripts/check-catalog.ts [catalog/catalog.json]

import { readFile } from 'node:fs/promises';

import { fetchBundle, fetchManifest, parseCatalog, pluginOfModule } from '../src/index.ts';

const path = process.argv[2] ?? 'catalog/catalog.json';
const catalog = parseCatalog(JSON.parse(await readFile(path, 'utf8')));

for (const entry of catalog.plugins) {
  const manifest = await fetchManifest(fetch, entry.manifest);
  for (const key of ['id', 'version', 'sha256'] as const) {
    if (manifest[key] !== entry[key]) {
      throw new Error(`${entry.id}: the catalog has ${key} ${entry[key]}, the manifest ${manifest[key]}`);
    }
  }
  const source = await fetchBundle(fetch, entry.manifest, manifest);
  pluginOfModule(await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`), manifest);
  console.log(`${entry.id} ${entry.version}: ok`);
}
console.log(`${path}: ${catalog.plugins.length} plugins checked`);
