import { expect, test } from 'vite-plus/test';

import { draftOf, readingList } from './reading-list.ts';

test('maps a book to a draft for the reading list', () => {
  const draft = draftOf({
    workKey: '/works/OL893414W',
    title: 'Der Wüstenplanet',
    authors: ['Frank Herbert'],
    firstPublishYear: 1965,
    pages: 608,
    isbn: '9783453317178',
    coverId: 15247677,
  });

  expect(draft).toEqual({
    title: 'Der Wüstenplanet',
    subtitle: 'Frank Herbert · 1965',
    thumbnail: 'https://covers.openlibrary.org/b/id/15247677-M.jpg',
    values: {
      status: 'want',
      author: 'Frank Herbert',
      year: 1965,
      pages: 608,
      isbn: '9783453317178',
      openlibrary: 'https://openlibrary.org/works/OL893414W',
    },
    files: { cover: ['https://covers.openlibrary.org/b/id/15247677-L.jpg'] },
  });
});

test("leaves out what Open Library doesn't know", () => {
  const draft = draftOf({ workKey: '/works/OL1W', title: 'Unknown', authors: [] });

  expect(draft).toEqual({
    title: 'Unknown',
    subtitle: '',
    values: { status: 'want', openlibrary: 'https://openlibrary.org/works/OL1W' },
    files: {},
  });
});

test('every draft value has a field in the reading list', () => {
  const keys = new Set(readingList.fields.map((field) => field.key));
  const draft = draftOf({
    workKey: '/works/OL1W',
    title: 'T',
    authors: ['A'],
    firstPublishYear: 1,
    pages: 1,
    isbn: '9783453317178',
    coverId: 1,
  });

  const used = [
    ...Object.keys(draft.values ?? {}),
    ...Object.keys(draft.files ?? {}),
    readingList.lookup?.uniqueFieldKey,
  ];
  for (const key of used) expect(keys).toContain(key);
  const status = readingList.fields.find((field) => field.kind === 'select');
  expect(status?.options.map((option) => option.key)).toContain(draft.values?.['status']);
});
