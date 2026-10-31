import type { PluginResponse } from './plugin-fetch.ts';

/** A {@link PluginResponse} with `body` as JSON - or as is, if it's a string. */
export function responseOf(url: string, body: unknown, status = 200): PluginResponse {
  const text = typeof body === 'string' ? body : JSON.stringify(body);
  return {
    ok: status >= 200 && status < 300,
    status,
    url,
    headers: {},
    text: () => Promise.resolve(text),
    json: () => Promise.resolve().then((): unknown => JSON.parse(text)),
  };
}
