import { expect, test } from 'vite-plus/test';

import { sniffMimeType } from './sniff-mime-type.ts';

function bytes(...parts: (string | number[])[]): Uint8Array {
  return new Uint8Array(
    parts.flatMap((part) => (typeof part === 'string' ? [...new TextEncoder().encode(part)] : part)),
  );
}

test('recognizes common types by their magic number', () => {
  expect(sniffMimeType(bytes([0xff, 0xd8, 0xff, 0xe0]))).toBe('image/jpeg');
  expect(sniffMimeType(bytes('%PDF-1.7'))).toBe('application/pdf');
  expect(sniffMimeType(bytes('GIF89a'))).toBe('image/gif');
  expect(sniffMimeType(bytes('RIFF', [0, 0, 0, 0], 'WEBPVP8 '))).toBe('image/webp');
});

test('tells ISO media files apart by their brand', () => {
  expect(sniffMimeType(bytes([0, 0, 0, 24], 'ftypheic'))).toBe('image/heic');
  expect(sniffMimeType(bytes([0, 0, 0, 24], 'ftypisom'))).toBe('video/mp4');
  expect(sniffMimeType(bytes([0, 0, 0, 24], 'ftypxxxx'))).toBeUndefined();
});

test('reveals nothing for plain text', () => {
  expect(sniffMimeType(bytes('hello'))).toBeUndefined();
});
