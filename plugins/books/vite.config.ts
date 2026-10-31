import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

import { pluginApiVersion, type PluginManifest, type PluginPermissions } from '@turtle-base/plugin-api';
import * as v from 'valibot';
import { defineConfig, type Plugin } from 'vite-plus';

const { version } = v.parse(
  v.object({ version: v.string() }),
  JSON.parse(readFileSync(new URL('package.json', import.meta.url), 'utf8')),
);

/** The part of the bundle's plugin the manifest repeats. */
const bundleSchema = v.object({
  default: v.object({ id: v.string(), name: v.string(), description: v.string(), icon: v.optional(v.string()) }),
});

export default defineConfig({
  plugins: [
    pluginManifest({
      author: 'Xennis',
      permissions: { network: ['openlibrary.org', 'covers.openlibrary.org'] },
    }),
  ],
  build: {
    // One ES module without imports - everything (plugin-api, valibot) bundled in.
    lib: { entry: 'src/main.ts', formats: ['es'], fileName: () => 'books.js' },
    target: 'es2024',
    // Readable, so users can look at what they install.
    minify: false,
  },
  test: {
    name: 'books',
    include: ['src/**/*.test.ts'],
  },
});

/**
 * Writes `books-manifest.json` next to the bundle - id, name, description
 * and icon read from the built bundle itself, which also proves it loads
 * on its own.
 */
function pluginManifest(options: { author: string; permissions: PluginPermissions }): Plugin {
  return {
    name: 'turtle-base:plugin-manifest',
    apply: 'build',
    async generateBundle(_, bundle) {
      const chunk = Object.values(bundle).find((output) => output.type === 'chunk' && output.isEntry);
      if (chunk?.type !== 'chunk') throw new Error('No entry chunk');
      const code = Buffer.from(chunk.code);
      const plugin = v.parse(
        bundleSchema,
        await import(`data:text/javascript;base64,${code.toString('base64')}`),
      ).default;
      const manifest: PluginManifest = {
        id: plugin.id,
        name: plugin.name,
        version,
        apiVersion: pluginApiVersion,
        author: options.author,
        description: plugin.description,
        ...(plugin.icon === undefined ? {} : { icon: plugin.icon }),
        main: chunk.fileName,
        sha256: createHash('sha256').update(code).digest('hex'),
        permissions: options.permissions,
      };
      this.emitFile({
        type: 'asset',
        fileName: `${plugin.id}-manifest.json`,
        source: `${JSON.stringify(manifest, null, 2)}\n`,
      });
    },
  };
}
