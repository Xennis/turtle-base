import type { GoogleAuthenticator, SecretStorage } from '@turtle-base/platform';

import * as v from 'valibot';

const authorizeEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
const tokenEndpoint = 'https://oauth2.googleapis.com/token';
const driveFileScope = 'https://www.googleapis.com/auth/drive.file';
const refreshTokenKey = 'crdt_file_sync.google_drive.refresh_token';

/** How long the browser has for the consent before signing in gives up. */
const consentTimeoutMs = 5 * 60 * 1000;

/** An access token is refreshed this long before it expires, so a request doesn't carry one that just ran out. */
const expiryMarginMs = 60 * 1000;

const tokenSchema = v.object({
  access_token: v.string(),
  expires_in: v.number(),
  refresh_token: v.optional(v.string()),
});
const tokenErrorSchema = v.object({ error: v.string(), error_description: v.optional(v.string()) });

/** Google's token endpoint refused - `code` is OAuth's error code, e.g. `invalid_grant` for a revoked sign-in. */
export class GoogleAuthError extends Error {
  override readonly name = 'GoogleAuthError';
  readonly code: string;

  constructor(code: string, description: string | undefined) {
    super(`Google sign-in failed: ${code}${description === undefined ? '' : ` (${description})`}`);
    this.code = code;
  }
}

export interface LoopbackGoogleAuthenticatorOptions {
  /** A "Desktop app" OAuth client - not confidential for installed apps (RFC 8252), see the README. */
  readonly clientId: string;
  readonly clientSecret: string;
  /** Where the refresh token is kept, the only thing that outlives the app. */
  readonly secrets: SecretStorage;
  readonly fetch: typeof fetch;
  /** Opens the consent page in the user's browser. */
  readonly openBrowser: (url: string) => Promise<void>;
  /** Catches the redirect back from the consent page - a server only the platform can run. */
  readonly listenForRedirect: ListenForRedirect;
}

/**
 * Starts a server on a free port of 127.0.0.1 for the redirect after the
 * consent. It answers the first request carrying `state` (anything else gets
 * a 404), settles `query` with that request's query and stops - or stops
 * after `timeoutMs`, settling it with undefined.
 */
export type ListenForRedirect = (
  state: string,
  timeoutMs: number,
) => Promise<{ readonly redirectUri: string; readonly query: Promise<URLSearchParams | undefined> }>;

/**
 * Google sign-in on Linux and macOS, which have no native Google Sign-In:
 * the "installed app" loopback flow (RFC 8252) with PKCE. A server on a free
 * port of 127.0.0.1 catches the redirect after the user agreed in their own
 * browser.
 */
export class LoopbackGoogleAuthenticator implements GoogleAuthenticator {
  readonly #options: LoopbackGoogleAuthenticatorOptions;
  #access: { token: string; expiresAt: number } | undefined;

  constructor(options: LoopbackGoogleAuthenticatorOptions) {
    this.#options = options;
  }

  /** Without asking Google - an access token is only fetched for the first request, so it works offline too. */
  async signInSilently(): Promise<boolean> {
    return (await this.#options.secrets.get(refreshTokenKey)) !== undefined;
  }

  async signIn(): Promise<void> {
    const verifier = randomBase64Url(32);
    const state = randomBase64Url(16);
    const { redirectUri, query } = await this.#options.listenForRedirect(state, consentTimeoutMs);
    const url = new URL(authorizeEndpoint);
    url.search = new URLSearchParams({
      client_id: this.#options.clientId,
      redirect_uri: redirectUri,
      response_type: 'code',
      scope: driveFileScope,
      code_challenge: base64Url(
        new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))),
      ),
      code_challenge_method: 'S256',
      state,
      // A refresh token every time, also when the app was allowed before (e.g. after signing out).
      access_type: 'offline',
      prompt: 'consent',
    }).toString();
    await this.#options.openBrowser(url.href);
    const redirect = await query;
    if (redirect === undefined) throw new GoogleAuthError('timeout', undefined);
    const code = redirect.get('code');
    if (code === null) throw new GoogleAuthError(redirect.get('error') ?? 'no_code', undefined);
    const token = await this.#requestToken({
      grant_type: 'authorization_code',
      code,
      redirect_uri: redirectUri,
      code_verifier: verifier,
    });
    if (token.refresh_token === undefined) throw new GoogleAuthError('no_refresh_token', undefined);
    await this.#options.secrets.set(refreshTokenKey, token.refresh_token);
  }

  async signOut(): Promise<void> {
    this.#access = undefined;
    await this.#options.secrets.remove(refreshTokenKey);
  }

  async accessToken(): Promise<string> {
    if (this.#access !== undefined && this.#access.expiresAt - expiryMarginMs > Date.now()) return this.#access.token;
    const refreshToken = await this.#options.secrets.get(refreshTokenKey);
    if (refreshToken === undefined) throw new Error('Not signed in to Google');
    try {
      await this.#requestToken({ grant_type: 'refresh_token', refresh_token: refreshToken });
    } catch (error) {
      // Revoked or expired - only signing in again helps, so the stale token goes.
      if (error instanceof GoogleAuthError && error.code === 'invalid_grant') await this.signOut();
      throw error;
    }
    if (this.#access === undefined) throw new Error('No access token');
    return this.#access.token;
  }

  async #requestToken(params: Record<string, string>): Promise<v.InferOutput<typeof tokenSchema>> {
    const response = await this.#options.fetch(tokenEndpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: this.#options.clientId,
        client_secret: this.#options.clientSecret,
        ...params,
      }),
    });
    const body: unknown = await response.json();
    if (!response.ok) {
      const error = v.safeParse(tokenErrorSchema, body);
      throw error.success
        ? new GoogleAuthError(error.output.error, error.output.error_description)
        : new GoogleAuthError(`http_${response.status}`, undefined);
    }
    const token = v.parse(tokenSchema, body);
    this.#access = { token: token.access_token, expiresAt: Date.now() + token.expires_in * 1000 };
    return token;
  }
}

function randomBase64Url(length: number): string {
  return base64Url(crypto.getRandomValues(new Uint8Array(length)));
}

function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/, '');
}
