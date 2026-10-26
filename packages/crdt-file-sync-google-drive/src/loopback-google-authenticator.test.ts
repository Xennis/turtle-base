import { MemorySecretStorage } from '@turtle-base/platform/testing';
import { createHash } from 'node:crypto';
import { describe, expect, test } from 'vite-plus/test';

import { GoogleAuthError, LoopbackGoogleAuthenticator } from './loopback-google-authenticator.ts';
import { listenForRedirectOnNode } from './testing.ts';

/** Google's token endpoint: hands out tokens, and remembers what it was sent. */
class FakeTokenEndpoint {
  readonly urls: string[] = [];
  readonly requests: URLSearchParams[] = [];
  /** The next answer - by default a fresh access token. */
  answer: () => Response = () => Response.json({ access_token: `access-${this.requests.length}`, expires_in: 3600 });

  readonly fetch: typeof fetch = async (input, init) => {
    const request = new Request(input, init);
    this.urls.push(request.url);
    this.requests.push(new URLSearchParams(await request.text()));
    return this.answer();
  };
}

function authenticatorOn(endpoint: FakeTokenEndpoint, secrets = new MemorySecretStorage()) {
  const consentPages: URL[] = [];
  const authenticator = new LoopbackGoogleAuthenticator({
    clientId: 'client-id',
    clientSecret: 'client-secret',
    secrets,
    fetch: endpoint.fetch,
    listenForRedirect: listenForRedirectOnNode,
    // The user agrees right away: the browser follows the redirect back to the app.
    openBrowser: (url) => {
      const page = new URL(url);
      consentPages.push(page);
      const redirect = new URL(page.searchParams.get('redirect_uri') ?? '');
      redirect.search = new URLSearchParams({
        code: 'the-code',
        state: page.searchParams.get('state') ?? '',
      }).toString();
      void fetch(redirect);
      return Promise.resolve();
    },
  });
  return { authenticator, consentPages, secrets };
}

describe('signIn()', () => {
  test('exchanges the redirected code with the PKCE verifier and keeps the refresh token', async () => {
    const endpoint = new FakeTokenEndpoint();
    endpoint.answer = () => Response.json({ access_token: 'access', expires_in: 3600, refresh_token: 'refresh' });
    const { authenticator, consentPages, secrets } = authenticatorOn(endpoint);

    await authenticator.signIn();

    const [page] = consentPages;
    const [request] = endpoint.requests;
    expect(page?.searchParams.get('redirect_uri')).toMatch(/^http:\/\/127\.0\.0\.1:\d+$/);
    expect(request?.get('grant_type')).toBe('authorization_code');
    expect(request?.get('code')).toBe('the-code');
    const challenge = createHash('sha256')
      .update(request?.get('code_verifier') ?? '')
      .digest('base64url');
    expect(page?.searchParams.get('code_challenge')).toBe(challenge);
    expect(await secrets.get('crdt_file_sync.google_drive.refresh_token')).toBe('refresh');
    expect(await authenticator.accessToken()).toBe('access');
    expect(endpoint.urls).toEqual(['https://oauth2.googleapis.com/token']);
  });

  test('fails on a refused consent', async () => {
    const endpoint = new FakeTokenEndpoint();
    const authenticator = new LoopbackGoogleAuthenticator({
      clientId: 'client-id',
      clientSecret: 'client-secret',
      secrets: new MemorySecretStorage(),
      fetch: endpoint.fetch,
      listenForRedirect: listenForRedirectOnNode,
      openBrowser: (url) => {
        const page = new URL(url);
        const redirect = new URL(page.searchParams.get('redirect_uri') ?? '');
        redirect.search = `error=access_denied&state=${page.searchParams.get('state') ?? ''}`;
        void fetch(redirect);
        return Promise.resolve();
      },
    });

    await expect(authenticator.signIn()).rejects.toThrow(GoogleAuthError);
    expect(endpoint.requests).toHaveLength(0);
  });
});

describe('accessToken()', () => {
  test('refreshes with the stored refresh token, and reuses the access token until it expires', async () => {
    const endpoint = new FakeTokenEndpoint();
    const secrets = new MemorySecretStorage();
    await secrets.set('crdt_file_sync.google_drive.refresh_token', 'refresh');
    const { authenticator } = authenticatorOn(endpoint, secrets);

    expect(await authenticator.signInSilently()).toBe(true);
    expect(await authenticator.accessToken()).toBe('access-1');
    expect(await authenticator.accessToken()).toBe('access-1');
    expect(endpoint.requests.map((request) => request.get('refresh_token'))).toEqual(['refresh']);
  });

  test('forgets a revoked sign-in', async () => {
    const endpoint = new FakeTokenEndpoint();
    endpoint.answer = () => Response.json({ error: 'invalid_grant' }, { status: 400 });
    const secrets = new MemorySecretStorage();
    await secrets.set('crdt_file_sync.google_drive.refresh_token', 'refresh');
    const { authenticator } = authenticatorOn(endpoint, secrets);

    await expect(authenticator.accessToken()).rejects.toThrow('invalid_grant');
    expect(await authenticator.signInSilently()).toBe(false);
  });

  test('rejects when not signed in', async () => {
    const { authenticator } = authenticatorOn(new FakeTokenEndpoint());

    expect(await authenticator.signInSilently()).toBe(false);
    await expect(authenticator.accessToken()).rejects.toThrow('Not signed in');
  });
});
