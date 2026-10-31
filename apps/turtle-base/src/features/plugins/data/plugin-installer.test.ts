import { MemoryFileDirectory, MemoryKeyValueStore } from '@turtle-base/platform/testing';
import type { CatalogEntry } from '@turtle-base/plugin-catalog';
import { expect, test } from 'vite-plus/test';

import { InstalledPluginsRepository } from './installed-plugins-repository.ts';
import { bundleOf, dataUrlPluginLoader } from './plugin-bundle.test-support.ts';
import { PluginInstaller } from './plugin-installer.ts';

const catalogUrl = 'https://example.org/catalog.json';

type Bundle = Awaited<ReturnType<typeof bundleOf>>;

function entryOf({ manifest, manifestUrl }: Bundle): CatalogEntry {
  const { id, name, author, description, version, sha256 } = manifest;
  return { id, name, author, description, manifest: manifestUrl, version, sha256 };
}

/** An installer whose network serves `bundles` and a catalog listing `listed` of them. */
function installerServing(bundles: readonly Bundle[], listed: readonly Bundle[] = bundles) {
  const files: Record<string, string> = {
    [catalogUrl]: JSON.stringify({ schemaVersion: 1, plugins: listed.map(entryOf) }),
  };
  for (const { source, manifest, manifestUrl } of bundles) {
    files[manifestUrl] = JSON.stringify(manifest);
    files[new URL(manifest.main, manifestUrl).href] = source;
  }
  const fetchFn: typeof fetch = (input) => {
    const body = files[input instanceof Request ? input.url : String(input)];
    return Promise.resolve(body === undefined ? new Response(null, { status: 404 }) : new Response(body));
  };
  const prefs = new MemoryKeyValueStore();
  const repository = new InstalledPluginsRepository(prefs, new MemoryFileDirectory());
  const installer = new PluginInstaller({ fetch: fetchFn, prefs, repository, loader: dataUrlPluginLoader, catalogUrl });
  return { installer, repository };
}

test('installs a plugin from the catalog', async () => {
  const demo = await bundleOf('demo');
  const { installer, repository } = installerServing([demo]);

  const catalog = await installer.refreshCatalog();
  const candidate = await installer.fromCatalog(catalog.plugins[0] ?? entryOf(demo));
  await installer.install(candidate);

  expect(repository.list()).toStrictEqual([
    { manifestUrl: demo.manifestUrl, manifest: demo.manifest, fromCatalog: true },
  ]);
  expect(installer.cachedCatalog()).toStrictEqual(catalog);
});

test('refuses a catalog entry its release does not match', async () => {
  const demo = await bundleOf('demo');
  const { installer } = installerServing([demo]);

  await expect(installer.fromCatalog({ ...entryOf(demo), version: '9.9.9' })).rejects.toThrow(
    /doesn't match the catalog/,
  );
});

test('installs a plugin from a URL, marked as not from the catalog', async () => {
  const demo = await bundleOf('demo');
  const { installer, repository } = installerServing([demo], []);

  await installer.install(await installer.fromUrl(demo.manifestUrl, await installer.refreshCatalog()));

  expect(repository.list()[0]?.fromCatalog).toBe(false);
});

test('refuses a plugin from a URL with the id of a catalog plugin', async () => {
  const demo = await bundleOf('demo');
  const { installer } = installerServing([demo]);

  await expect(installer.fromUrl(demo.manifestUrl, await installer.refreshCatalog())).rejects.toThrow(/in the catalog/);
});

test('refuses a plugin from another URL with the id of an installed one', async () => {
  const demo = await bundleOf('demo');
  const copy = { ...demo, manifestUrl: 'https://other.example/demo-manifest.json' };
  const { installer } = installerServing([demo, copy], []);
  await installer.install(await installer.fromUrl(demo.manifestUrl, undefined));

  await expect(installer.fromUrl(copy.manifestUrl, undefined)).rejects.toThrow(/from elsewhere/);
});

test('finds the update the catalog lists', async () => {
  const first = await bundleOf('demo', '1.0.0');
  const second = await bundleOf('demo', '1.1.0');
  const { installer, repository } = installerServing([first, second], [second]);
  await installer.install(await installer.fromCatalog(entryOf(first)));
  const catalog = await installer.refreshCatalog();
  const [current] = repository.list();
  if (current === undefined) throw new Error('Not installed');

  const update = await installer.updateOf(current, catalog);

  expect(update?.manifest.version).toBe('1.1.0');
  expect(update?.replaces).toStrictEqual(current);
  if (update === undefined) throw new Error('No update');
  await installer.install(update);
  expect(await installer.updateOf(repository.list()[0] ?? current, catalog)).toBeUndefined();
});

test('installs nothing when the bundle does not load', async () => {
  const demo = await bundleOf('demo');
  const broken = { ...demo, manifest: { ...demo.manifest, id: 'other' } };
  const { installer, repository } = installerServing([broken], []);

  await expect(installer.install({ ...broken, fromCatalog: false })).rejects.toThrow(/manifest names other/);
  expect(repository.list()).toStrictEqual([]);
});
