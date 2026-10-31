import type { PluginFetch } from '@turtle-base/plugin-api';

/**
 * Whether `url` may be requested by a plugin allowed to reach `hosts`: https
 * only, the host named exactly or, for `*.example.org`, a subdomain of it.
 * Only the URL the plugin picks is checked - a redirect is the named
 * server's choice.
 */
export function isAllowedUrl(url: string, hosts: readonly string[]): boolean {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  if (parsed.protocol !== 'https:') return false;
  const host = parsed.hostname;
  return hosts.some((allowed) =>
    allowed.startsWith('*.') ? host.endsWith(allowed.slice(1)) && host.length > allowed.length - 1 : host === allowed,
  );
}

/**
 * The plugins' view of `fetchFn`, limited to `hosts` (see
 * {@link isAllowedUrl}) - undefined for a plugin built into the app.
 */
export function pluginFetchOf(fetchFn: typeof fetch, hosts: readonly string[] | undefined): PluginFetch {
  return async (url, init) => {
    if (hosts !== undefined && !isAllowedUrl(url, hosts)) throw new TypeError(`Not allowed to reach ${url}`);
    const response = await fetchFn(url, {
      ...(init?.method === undefined ? {} : { method: init.method }),
      ...(init?.headers === undefined ? {} : { headers: { ...init.headers } }),
      ...(init?.body === undefined ? {} : { body: init.body }),
      ...(init?.signal === undefined ? {} : { signal: init.signal }),
    });
    // A body can be read once - text() and json() share it.
    let text: Promise<string> | undefined;
    const read = () => (text ??= response.text());
    return {
      ok: response.ok,
      status: response.status,
      url: response.url,
      headers: Object.fromEntries(response.headers),
      text: read,
      json: async (): Promise<unknown> => JSON.parse(await read()),
    };
  };
}
