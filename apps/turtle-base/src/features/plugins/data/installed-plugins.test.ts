import { MemoryFileDirectory, MemoryKeyValueStore } from '@turtle-base/platform/testing';
import { expect, test } from 'vite-plus/test';

import { InstalledPluginsRepository } from './installed-plugins-repository.ts';
import { InstalledPlugins } from './installed-plugins.ts';
import { bundleOf, dataUrlPluginLoader } from './plugin-bundle.test-support.ts';

function repository() {
  const files = new MemoryFileDirectory();
  const prefs = new MemoryKeyValueStore();
  return { files, prefs, repository: new InstalledPluginsRepository(prefs, files) };
}

test('loads an installed plugin from its stored bundle', async () => {
  const { repository: installed } = repository();
  const { source, manifest, manifestUrl } = await bundleOf('demo');
  await installed.install({ manifestUrl, manifest, fromCatalog: true }, source);

  const plugins = await InstalledPlugins.load(installed, dataUrlPluginLoader);

  expect(plugins.plugins.map((plugin) => plugin.id)).toStrictEqual(['demo']);
  expect(plugins.broken).toStrictEqual([]);
  expect(plugins.hostsOf('demo')).toStrictEqual(['demo.example.org']);
  expect(plugins.hostsOf('books')).toStrictEqual([]);
});

test('replaces the bundle of an updated plugin', async () => {
  const { files, repository: installed } = repository();
  const first = await bundleOf('demo', '1.0.0');
  const second = await bundleOf('demo', '1.1.0');
  await installed.install({ ...first, fromCatalog: true }, first.source);

  await installed.install({ ...second, fromCatalog: true }, second.source);

  expect(installed.list().map(({ manifest }) => manifest.version)).toStrictEqual(['1.1.0']);
  expect(await files.list()).toStrictEqual(['demo-1.1.0.js']);
});

test('removes a plugin and its bundle', async () => {
  const { files, repository: installed } = repository();
  const { source, manifest, manifestUrl } = await bundleOf('demo');
  await installed.install({ manifestUrl, manifest, fromCatalog: false }, source);

  await installed.remove('demo');

  expect(installed.list()).toStrictEqual([]);
  expect(await files.list()).toStrictEqual([]);
});

test('starts without a plugin whose bundle was changed', async () => {
  const { files, repository: installed } = repository();
  const demo = await bundleOf('demo');
  const other = await bundleOf('other');
  await installed.install({ ...demo, fromCatalog: true }, demo.source);
  await installed.install({ ...other, fromCatalog: true }, other.source);
  const handle = await files.writeTemp(new Blob(['export default {};']).stream());
  await files.commitTemp(handle, 'demo-1.0.0.js');

  const plugins = await InstalledPlugins.load(installed, dataUrlPluginLoader);

  expect(plugins.plugins.map((plugin) => plugin.id)).toStrictEqual(['other']);
  expect(plugins.broken.map(({ installed: { manifest }, error }) => [manifest.id, error])).toStrictEqual([
    ['demo', 'The installed bundle was changed'],
  ]);
});

test('starts without a plugin that does not match its manifest', async () => {
  const { repository: installed } = repository();
  const { source, manifest, manifestUrl } = await bundleOf('demo');
  await installed.install({ manifestUrl, manifest: { ...manifest, id: 'other' }, fromCatalog: true }, source);

  const plugins = await InstalledPlugins.load(installed, dataUrlPluginLoader);

  expect(plugins.plugins).toStrictEqual([]);
  expect(plugins.broken[0]?.error).toMatch(/manifest names other/);
});

test('reads a broken list of installed plugins as empty', async () => {
  const { prefs, repository: installed } = repository();
  await prefs.set('installed_plugins', '{not json');

  expect(installed.list()).toStrictEqual([]);
});
