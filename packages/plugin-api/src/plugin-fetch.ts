/**
 * The network as a plugin sees it - a small part of `fetch`, without DOM
 * types, so plugins compile without the DOM and a sandbox can provide all
 * of it. The app only lets it reach the hosts of the plugin's manifest.
 */
export type PluginFetch = (url: string, init?: PluginFetchInit) => Promise<PluginResponse>;

export interface PluginFetchInit {
  readonly method?: string;
  readonly headers?: Readonly<Record<string, string>>;
  readonly body?: string;
  readonly signal?: AbortSignal;
}

export interface PluginResponse {
  readonly ok: boolean;
  readonly status: number;

  /** The final URL, after redirects. */
  readonly url: string;

  /** Lowercase header names. */
  readonly headers: Readonly<Record<string, string>>;
  text(): Promise<string>;

  /** Rejects when the body isn't JSON. */
  json(): Promise<unknown>;
}
