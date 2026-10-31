import { pluginApiVersion, type PluginManifest } from '@turtle-base/plugin-api';
import * as v from 'valibot';

/** Why a plugin can't be fetched or installed - its `message` is shown to the user. */
export class PluginSourceError extends Error {
  override readonly name = 'PluginSourceError';
}

const hexSha256 = v.pipe(v.string(), v.regex(/^[0-9a-f]{64}$/, 'Expected a SHA-256 as lowercase hex'));

/** Host names, optionally `*.` in front - see `PluginPermissions.network`. */
const hostName = v.pipe(v.string(), v.regex(/^(\*\.)?[a-z0-9-]+(\.[a-z0-9-]+)+$/, 'Expected a host name'));

export const manifestSchema = v.object({
  id: v.string(),
  name: v.pipe(v.string(), v.minLength(1)),
  version: v.pipe(v.string(), v.regex(/^\d+\.\d+\.\d+$/, 'Expected a version like 1.2.0')),
  apiVersion: v.pipe(v.number(), v.integer()),
  author: v.string(),
  description: v.string(),
  icon: v.optional(v.string()),
  // A file next to the manifest - no path, so it can't point elsewhere.
  main: v.pipe(v.string(), v.regex(/^[\w-]+(\.[\w-]+)*\.js$/, 'Expected a file name like plugin.js')),
  sha256: hexSha256,
  permissions: v.object({ network: v.optional(v.array(hostName)) }),
});

/** Parses a manifest by its shape only - see {@link parseManifest}. */
export function readManifest(value: unknown): PluginManifest {
  const result = v.safeParse(manifestSchema, value);
  if (!result.success) {
    const issue = result.issues[0];
    throw new PluginSourceError(`Invalid manifest: ${v.getDotPath(issue) ?? 'value'}: ${issue.message}`);
  }
  const { icon, permissions, ...rest } = result.output;
  return {
    ...rest,
    ...(icon === undefined ? {} : { icon }),
    permissions: permissions.network === undefined ? {} : { network: permissions.network },
  };
}

/** Throws unless `manifest` is built against the major of the plugin API this app supports. */
export function checkApiVersion(manifest: PluginManifest): void {
  if (manifest.apiVersion !== pluginApiVersion) {
    throw new PluginSourceError(
      `${manifest.name} needs version ${manifest.apiVersion} of the plugin API, this app has version ${pluginApiVersion}`,
    );
  }
}

/**
 * Parses and checks a manifest: its shape, and that it's built against a
 * major of the plugin API this app supports.
 */
export function parseManifest(value: unknown): PluginManifest {
  const manifest = readManifest(value);
  checkApiVersion(manifest);
  return manifest;
}

/** Fetches and checks the manifest at `url` - see {@link parseManifest}. */
export async function fetchManifest(fetchFn: typeof fetch, url: string): Promise<PluginManifest> {
  return parseManifest(await fetchJson(fetchFn, url, 'manifest'));
}

/** Where the bundle of `manifest`, found at `manifestUrl`, lies - next to it. */
export function bundleUrlOf(manifestUrl: string, manifest: PluginManifest): string {
  return new URL(manifest.main, manifestUrl).href;
}

/** Fetches the bundle of `manifest` and checks it against the manifest's hash. Returns its source. */
export async function fetchBundle(
  fetchFn: typeof fetch,
  manifestUrl: string,
  manifest: PluginManifest,
): Promise<string> {
  const url = bundleUrlOf(manifestUrl, manifest);
  const response = await get(fetchFn, url, 'plugin');
  const bytes = new Uint8Array(await response.arrayBuffer());
  if ((await sha256Hex(bytes)) !== manifest.sha256) {
    throw new PluginSourceError(`The plugin at ${url} doesn't match its manifest`);
  }
  return new TextDecoder().decode(bytes);
}

/** As lowercase hex. */
export async function sha256Hex(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

/** Plugins only come over https. */
export function checkSourceUrl(url: string): void {
  if (!URL.canParse(url) || new URL(url).protocol !== 'https:') {
    throw new PluginSourceError(`Not an https URL: ${url}`);
  }
}

export async function fetchJson(fetchFn: typeof fetch, url: string, what: string): Promise<unknown> {
  const response = await get(fetchFn, url, what);
  try {
    return (await response.json()) as unknown;
  } catch (error) {
    throw new PluginSourceError(`The ${what} at ${url} isn't JSON`, { cause: error });
  }
}

async function get(fetchFn: typeof fetch, url: string, what: string): Promise<Response> {
  checkSourceUrl(url);
  let response: Response;
  try {
    response = await fetchFn(url);
  } catch (error) {
    throw new PluginSourceError(`Couldn't load the ${what} from ${url}`, { cause: error });
  }
  if (response.status !== 200)
    throw new PluginSourceError(`Couldn't load the ${what} from ${url} (${response.status})`);
  return response;
}
