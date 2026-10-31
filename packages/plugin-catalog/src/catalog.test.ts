import { expect, test } from 'vite-plus/test';

import { parseCatalog } from './catalog.ts';

const books = {
  id: 'books',
  name: 'Books',
  author: 'Xennis',
  description: 'Reading list',
  icon: '📚',
  manifest: 'https://github.com/Xennis/turtle-base/releases/download/books-v1.0.0/books-manifest.json',
  version: '1.0.0',
  sha256: '0'.repeat(64),
};

test('parses a catalog', () => {
  expect(parseCatalog({ schemaVersion: 1, plugins: [books] })).toStrictEqual({ plugins: [books] });
});

test('rejects a plugin listed twice', () => {
  expect(() => parseCatalog({ schemaVersion: 1, plugins: [books, books] })).toThrow(/listed twice/);
});

test('rejects a manifest that is not https', () => {
  expect(() =>
    parseCatalog({ schemaVersion: 1, plugins: [{ ...books, manifest: 'http://example.org/manifest.json' }] }),
  ).toThrow(/manifest/);
});

test('rejects an unknown schema version', () => {
  expect(() => parseCatalog({ schemaVersion: 2, plugins: [] })).toThrow(/schemaVersion/);
});
