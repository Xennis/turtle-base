import { textVariant } from '@turtle-base/plugin-api';

export function normalizeIsbn(value: string): string {
  return value.replaceAll(/[\s-]/g, '').toUpperCase();
}

/** Checks the length, characters and check digit of a normalized ISBN. */
export function isValidIsbn(value: string): boolean {
  // Only ASCII digits and X get past the patterns below.
  const digits = value.split('').map((char) => (char === 'X' ? 10 : Number(char)));
  if (/^\d{9}[\dX]$/.test(value)) {
    return digits.reduce((sum, digit, i) => sum + digit * (10 - i), 0) % 11 === 0;
  }
  if (/^97[89]\d{10}$/.test(value)) {
    return digits.reduce((sum, digit, i) => sum + digit * (i % 2 === 0 ? 1 : 3), 0) % 10 === 0;
  }
  return false;
}

/**
 * Splits off the 978/979 prefix of an ISBN-13. Grouping the rest correctly
 * needs the ISBN agency's range table, which isn't bundled.
 */
export function formatIsbn(value: string): string {
  return value.length === 13 ? `${value.slice(0, 3)}-${value.slice(3)}` : value;
}

/**
 * An ISBN-10 or ISBN-13, stored without separators (e.g. `9783453317178`)
 * and shown with its prefix split off.
 */
export const isbnVariant = textVariant({
  id: 'books.isbn',
  label: 'ISBN',
  normalize: normalizeIsbn,
  validate: (value) => (isValidIsbn(value) ? undefined : 'Enter a valid ISBN-10 or ISBN-13'),
  format: formatIsbn,
  link: (value) => new URL(`https://openlibrary.org/isbn/${encodeURIComponent(value)}`),
});
