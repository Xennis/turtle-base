import { pluginApiVersion, type PluginManifest } from '@turtle-base/plugin-api';
import { checkApiVersion, pluginOfModule, sha256Hex } from '@turtle-base/plugin-catalog';

import type { PluginLoader } from './plugin-loader.ts';

/** Like the page's loader, for Node - which imports data: URLs, not blob: ones. */
export const dataUrlPluginLoader: PluginLoader = {
  async load(source, manifest) {
    checkApiVersion(manifest);
    return pluginOfModule(await import(`data:text/javascript;base64,${btoa(source)}`), manifest);
  },
};

/** The source of a bundle exporting a plugin `id` with one collection, and its manifest. */
export async function bundleOf(
  id: string,
  version = '1.0.0',
): Promise<{ source: string; manifest: PluginManifest; manifestUrl: string }> {
  const source = `export default ${JSON.stringify({
    id,
    name: id.toUpperCase(),
    description: `The ${id} plugin`,
    collections: [{ key: 'items', name: 'Items', fields: [{ kind: 'date', key: 'due', name: 'Due' }] }],
  })};`;
  const manifest: PluginManifest = {
    id,
    name: id.toUpperCase(),
    version,
    apiVersion: pluginApiVersion,
    author: 'Tester',
    description: `The ${id} plugin`,
    main: `${id}.js`,
    sha256: await sha256Hex(new TextEncoder().encode(source)),
    permissions: { network: [`${id}.example.org`] },
  };
  return { source, manifest, manifestUrl: `https://example.org/${id}/${version}/${id}-manifest.json` };
}
