import { patternTextVariant, textVariant, type FieldVariant } from './field-variant.ts';

export const urlVariant = textVariant({
  id: 'url',
  label: 'URL',
  inputHint: 'url',
  normalize: (value) => value.trim(),
  validate: (value) => (isValidUrl(value) ? undefined : 'Enter a valid URL, e.g. example.com'),
  link: (value) => new URL(value.includes('://') ? value : `https://${value}`),
});

export const emailVariant = patternTextVariant({
  id: 'email',
  label: 'Email',
  pattern: /[^@\s]+@[^@\s]+\.[^@\s]+/,
  message: 'Enter a valid email address',
  inputHint: 'email',
  normalize: (value) => value.trim(),
  link: (value) => new URL(`mailto:${value}`),
});

export const phoneVariant = patternTextVariant({
  id: 'phone',
  label: 'Phone',
  pattern: /\+?[0-9][0-9 ()/.-]{2,}/,
  message: 'Enter a valid phone number, e.g. +49 30 1234567',
  inputHint: 'phone',
  normalize: (value) => value.trim(),
  link: (value) => new URL(`tel:${value.replaceAll(/[^0-9+]/g, '')}`),
});

/**
 * Variants every turtle-base app offers - plugins may use them in their
 * collection templates, e.g. a URL field linking to the source.
 */
export const commonVariants: readonly FieldVariant[] = [urlVariant, emailVariant, phoneVariant];

/** A host with a dot, with or without a scheme (`example.com` counts). */
export function isValidUrl(value: string): boolean {
  const withScheme = value.includes('://') ? value : `https://${value}`;
  const url = URL.parse(withScheme);
  return url !== null && url.hostname.includes('.');
}
