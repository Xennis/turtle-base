import { expect, test } from 'vite-plus/test';

import { isbnVariant } from './isbn.ts';

test('normalizes separators and a lowercase check digit', () => {
  expect(isbnVariant.normalize('978-3-453-31717-8 ')).toBe('9783453317178');
  expect(isbnVariant.normalize('0-8044-2957-x')).toBe('080442957X');
});

test('validates the check digit of ISBN-10 and ISBN-13', () => {
  expect(isbnVariant.validate('9783453317178')).toBeUndefined();
  expect(isbnVariant.validate('080442957X')).toBeUndefined();
  expect(isbnVariant.validate('9783453317179')).toBeDefined();
  expect(isbnVariant.validate('0804429571')).toBeDefined();
  expect(isbnVariant.validate('12345')).toBeDefined();
});

test('formats an ISBN-13 with its prefix split off', () => {
  expect(isbnVariant.format('9783453317178')).toBe('978-3453317178');
  expect(isbnVariant.format('080442957X')).toBe('080442957X');
});

test('links to Open Library', () => {
  expect(isbnVariant.link('9783453317178')?.href).toBe('https://openlibrary.org/isbn/9783453317178');
});
