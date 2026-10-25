import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';

import type { ListenForRedirect } from './loopback-google-authenticator.ts';

/** A {@link ListenForRedirect} on Node's HTTP server - for Electron's main process and the tests. */
export const listenForRedirectOnNode: ListenForRedirect = async (state, timeoutMs) => {
  let settle: ((query: URLSearchParams | undefined) => void) | undefined;
  const query = new Promise<URLSearchParams | undefined>((resolve) => {
    settle = resolve;
  });
  const server = createServer((request, response) => {
    const params = new URL(request.url ?? '/', 'http://127.0.0.1').searchParams;
    if (params.get('state') !== state) {
      response.writeHead(404).end();
      return;
    }
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    response.end(
      params.get('code') === null
        ? '<p>Signing in to turtle-base was cancelled. You can close this tab.</p>'
        : '<p>Signed in to turtle-base. You can close this tab.</p>',
    );
    settle?.(params);
    server.close();
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  // oxlint-disable-next-line typescript/no-unsafe-type-assertion -- listening on a TCP port, never a pipe
  const { port } = server.address() as AddressInfo;
  const timeout = setTimeout(() => {
    settle?.(undefined);
    server.close();
  }, timeoutMs);
  server.on('close', () => clearTimeout(timeout));
  return { redirectUri: `http://127.0.0.1:${port}`, query };
};
