import { LookupError } from '@turtle-base/plugin-api';
import { expect, test } from 'vite-plus/test';

import { coverUrlOf, OpenLibraryClient, openLibraryUserAgent, workUrlOf } from './open-library-client.ts';

/** Shaped like real answers of https://openlibrary.org/search.json. */
const duneWork = {
  key: '/works/OL893414W',
  title: 'Dune',
  author_name: ['Frank Herbert'],
  first_publish_year: 1965,
  number_of_pages_median: 608,
  cover_i: 11481354,
  editions: {
    numFound: 1,
    docs: [{ title: 'Der Wüstenplanet', cover_i: 15247677, isbn: ['3453317173', '9783453317178'] }],
  },
};

function clientAnswering(body: unknown, status = 200): { client: OpenLibraryClient; requested: () => URL } {
  let requested: URL | undefined;
  const fetchFn = (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    requested = new URL(input instanceof Request ? input.url : input);
    expect(new Headers(init?.headers).get('User-Agent')).toBe(openLibraryUserAgent);
    return Promise.resolve(new Response(JSON.stringify(body), { status }));
  };
  return {
    client: new OpenLibraryClient(fetchFn),
    requested: () => {
      if (requested === undefined) throw new Error('Nothing requested');
      return requested;
    },
  };
}

test('searches an ISBN by its normalized form', async () => {
  const { client, requested } = clientAnswering({ docs: [duneWork] });

  const books = await client.search('978-3-453-31717-8');

  expect(requested().searchParams.get('q')).toBe('isbn:9783453317178');
  expect(books).toEqual([
    {
      workKey: '/works/OL893414W',
      title: 'Der Wüstenplanet',
      authors: ['Frank Herbert'],
      firstPublishYear: 1965,
      pages: 608,
      isbn: '9783453317178',
      coverId: 15247677,
    },
  ]);
  expect(books.map(workUrlOf)).toEqual(['https://openlibrary.org/works/OL893414W']);
  expect(books.map((book) => coverUrlOf(book, 'L'))).toEqual(['https://covers.openlibrary.org/b/id/15247677-L.jpg']);
});

test('searches anything else as free text', async () => {
  const { client, requested } = clientAnswering({ docs: [] });

  expect(await client.search(' dune herbert ')).toEqual([]);
  expect(requested().searchParams.get('q')).toBe('dune herbert');
  expect(requested().searchParams.get('fields')).toContain('editions.isbn');
});

test('falls back to the work without a matching edition', async () => {
  const { client } = clientAnswering({
    docs: [{ key: '/works/OL1W', title: 'Untitled work', cover_i: 7 }, { title: 'No key - skipped' }],
  });

  const books = await client.search('untitled');

  expect(books).toEqual([{ workKey: '/works/OL1W', title: 'Untitled work', authors: [], coverId: 7 }]);
  expect(books.map((book) => coverUrlOf(book, 'M'))).toEqual(['https://covers.openlibrary.org/b/id/7-M.jpg']);
});

test('prefers a valid ISBN-13 of the edition', async () => {
  const { client } = clientAnswering({
    docs: [
      {
        key: '/works/OL1W',
        title: 'Book',
        editions: { docs: [{ isbn: ['0804429571', '080442957X', '9783453317178'] }] },
      },
    ],
  });

  expect((await client.search('book'))[0]?.isbn).toBe('9783453317178');
});

test('rejects with a LookupError on an error response', async () => {
  const { client } = clientAnswering('Service unavailable', 503);

  await expect(client.search('dune')).rejects.toBeInstanceOf(LookupError);
});

test('rejects with a LookupError on an unknown format', async () => {
  const { client } = clientAnswering({ results: [] });

  await expect(client.search('dune')).rejects.toBeInstanceOf(LookupError);
});

test('rejects with a LookupError when unreachable', async () => {
  const client = new OpenLibraryClient(() => Promise.reject(new TypeError('offline')));

  await expect(client.search('dune')).rejects.toBeInstanceOf(LookupError);
});
