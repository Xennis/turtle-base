import { describe, expect, test } from 'vite-plus/test';

import { emailVariant, phoneVariant, urlVariant } from './common-variants.ts';

describe('urlVariant', () => {
  test('accepts a host with or without scheme', () => {
    expect(urlVariant.validate('example.com')).toBeUndefined();
    expect(urlVariant.validate('https://example.com/path')).toBeUndefined();
    expect(urlVariant.validate('example')).toBeDefined();
  });

  test('links to https when the scheme is missing', () => {
    expect(urlVariant.link('example.com')?.href).toBe('https://example.com/');
    expect(urlVariant.link('http://example.com')?.href).toBe('http://example.com/');
  });
});

test('emailVariant links to mailto', () => {
  expect(emailVariant.validate('a@example.com')).toBeUndefined();
  expect(emailVariant.validate('a@example')).toBeDefined();
  expect(emailVariant.link('a@example.com')?.href).toBe('mailto:a@example.com');
});

test('phoneVariant links to tel without separators', () => {
  expect(phoneVariant.validate('+49 30 1234567')).toBeUndefined();
  expect(phoneVariant.validate('call me')).toBeDefined();
  expect(phoneVariant.link('+49 (30) 123-4567')?.href).toBe('tel:+49301234567');
});
