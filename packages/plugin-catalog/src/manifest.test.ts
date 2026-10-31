import { pluginApiVersion, type PluginManifest } from '@turtle-base/plugin-api';
import { expect, test } from 'vite-plus/test';

import { bundleUrlOf, fetchBundle, fetchManifest, parseManifest, PluginSourceError, sha256Hex } from './manifest.ts';

const source = 'export default {};';
const sha256 = await sha256Hex(new TextEncoder().encode(source));

const manifest: PluginManifest = {
  id: 'demo',
  name: 'Demo',
  version: '1.2.0',
  apiVersion: pluginApiVersion,
  author: 'Someone',
  description: 'A demo',
  main: 'demo.js',
  sha256,
  permissions: { network: ['example.org', '*.example.org'] },
};

const manifestUrl = 'https://example.org/releases/1.2.0/demo-manifest.json';

/** Answers each URL of `files` with its body, everything else with 404. */
function serving(files: Record<string, string>): typeof fetch {
  return (input) => {
    const url = input instanceof Request ? input.url : String(input);
    const body = files[url];
    return Promise.resolve(body === undefined ? new Response(null, { status: 404 }) : new Response(body));
  };
}

test('parses a manifest', () => {
  expect(parseManifest(JSON.parse(JSON.stringify(manifest)))).toStrictEqual(manifest);
});

test('rejects a manifest of another major of the API', () => {
  expect(() => parseManifest({ ...manifest, apiVersion: pluginApiVersion + 1 })).toThrow(/version 2 of the plugin API/);
});

test('rejects a main pointing elsewhere', () => {
  expect(() => parseManifest({ ...manifest, main: '../other.js' })).toThrow(PluginSourceError);
  expect(() => parseManifest({ ...manifest, main: 'https://evil.example/x.js' })).toThrow(PluginSourceError);
});

test('rejects permissions that are no host names', () => {
  expect(() => parseManifest({ ...manifest, permissions: { network: ['https://example.org'] } })).toThrow(
    /permissions\.network/,
  );
});

test('finds the bundle next to the manifest', () => {
  expect(bundleUrlOf(manifestUrl, manifest)).toBe('https://example.org/releases/1.2.0/demo.js');
});

test('fetches a manifest and its bundle', async () => {
  const fetchFn = serving({
    [manifestUrl]: JSON.stringify(manifest),
    'https://example.org/releases/1.2.0/demo.js': source,
  });

  const fetched = await fetchManifest(fetchFn, manifestUrl);

  expect(fetched).toStrictEqual(manifest);
  expect(await fetchBundle(fetchFn, manifestUrl, fetched)).toBe(source);
});

test('rejects a bundle that does not match the hash', async () => {
  const fetchFn = serving({ 'https://example.org/releases/1.2.0/demo.js': 'export default { evil: true };' });

  await expect(fetchBundle(fetchFn, manifestUrl, manifest)).rejects.toThrow(/doesn't match/);
});

test('only fetches over https', async () => {
  await expect(fetchManifest(serving({}), 'http://example.org/manifest.json')).rejects.toThrow(/Not an https URL/);
});

test('names a source that is not there', async () => {
  await expect(fetchManifest(serving({}), manifestUrl)).rejects.toThrow(/\(404\)/);
});
