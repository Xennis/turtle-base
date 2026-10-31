import { expect, test } from 'vite-plus/test';

import { isAllowedUrl, pluginFetchOf } from './plugin-fetch.ts';

test('allows only https to the named hosts and subdomains of wildcards', () => {
  const hosts = ['openlibrary.org', '*.archive.org'];

  expect(isAllowedUrl('https://openlibrary.org/search.json', hosts)).toBe(true);
  expect(isAllowedUrl('https://ia800.us.archive.org/x.jpg', hosts)).toBe(true);
  expect(isAllowedUrl('https://archive.org/', hosts)).toBe(false);
  expect(isAllowedUrl('https://evilarchive.org/', hosts)).toBe(false);
  expect(isAllowedUrl('https://covers.openlibrary.org/b/1.jpg', hosts)).toBe(false);
  expect(isAllowedUrl('http://openlibrary.org/', hosts)).toBe(false);
  expect(isAllowedUrl('not a url', hosts)).toBe(false);
});

test('passes the request on and reads the answer', async () => {
  const requests: Request[] = [];
  const fetchFn = pluginFetchOf(
    (input, init) => {
      requests.push(new Request(input, init));
      return Promise.resolve(Response.json({ docs: [] }));
    },
    ['openlibrary.org'],
  );

  const response = await fetchFn('https://openlibrary.org/search.json', { headers: { 'User-Agent': 'Test' } });

  expect(requests[0]?.headers.get('User-Agent')).toBe('Test');
  expect(response.status).toBe(200);
  expect(response.headers['content-type']).toBe('application/json');
  expect(await response.json()).toStrictEqual({ docs: [] });
});

test('rejects a host not allowed without requesting it', async () => {
  let requested = false;
  const fetchFn = pluginFetchOf(() => {
    requested = true;
    return Promise.resolve(new Response());
  }, ['openlibrary.org']);

  await expect(fetchFn('https://example.org/')).rejects.toThrow(TypeError);
  expect(requested).toBe(false);
});
