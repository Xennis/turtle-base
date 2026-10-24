import { expect, test } from 'vite-plus/test';

import { FileAccept } from './file-accept.ts';

function accepts(accept: FileAccept, mimeType: string, fileName: string): boolean {
  return accept.accepts({ mimeType, fileName });
}

test('any accepts everything', () => {
  expect(accepts(FileAccept.any, 'application/zip', 'a.zip')).toBe(true);
});

test('a wildcard matches the whole MIME family', () => {
  expect(accepts(FileAccept.images, 'image/jpeg', 'a.jpg')).toBe(true);
  expect(accepts(FileAccept.images, 'application/pdf', 'a.jpg')).toBe(false);
});

test('an exact MIME type and an extension each match', () => {
  const xml = FileAccept.parse('application/xml, .XML');
  expect(accepts(xml, 'application/xml', 'a.txt')).toBe(true);
  expect(accepts(xml, 'text/plain', 'feed.xml')).toBe(true);
  expect(accepts(xml, 'text/plain', 'feed.txt')).toBe(false);
  expect(accepts(xml, 'text/plain', '.xml')).toBe(false);
});

test('parse() trims, lowercases and drops empty parts', () => {
  expect(FileAccept.parse(' Image/* ,, .PDF ').patterns).toEqual(['image/*', '.pdf']);
});

test("dialogExtensions lists extensions, or nothing when it can't", () => {
  expect(FileAccept.any.dialogExtensions).toBeUndefined();
  expect(FileAccept.pdf.dialogExtensions).toEqual(['pdf']);
  expect(FileAccept.images.dialogExtensions).toContain('png');
  expect(FileAccept.parse('text/*').dialogExtensions).toBeUndefined();
});

test('isImagesOnly', () => {
  expect(FileAccept.images.isImagesOnly).toBe(true);
  expect(FileAccept.parse('image/*, .pdf').isImagesOnly).toBe(false);
  expect(FileAccept.any.isImagesOnly).toBe(false);
});

test('equals ignores the order', () => {
  expect(FileAccept.parse('.a, .b').equals(FileAccept.parse('.b, .a'))).toBe(true);
  expect(FileAccept.parse('.a').equals(FileAccept.parse('.a, .b'))).toBe(false);
});
