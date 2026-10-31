import { textVariant, urlVariant } from '@turtle-base/plugin-api';
import { describe, expect, test } from 'vite-plus/test';

import type { Field } from '../../../core/database/schema.ts';
import { textFieldType } from './base-field-type.ts';
import { conversionMode } from './field-conversion.ts';
import { FieldTypeRegistry } from './field-type-registry.ts';
import type { ParsedInput } from './resolved-field.ts';
import { encodeSelectConfig } from './select-field.ts';

function fieldRow(type: string, config: string | null = null): Field {
  return {
    id: 'f',
    collection_id: 'c',
    name: 'Field',
    type,
    position: 0,
    config,
    created_at: 0,
    updated_at: 0,
    created_by: 'u',
    updated_by: 'u',
    deleted_at: null,
    hlc: '',
    node_id: '',
    modified: '',
  };
}

function storedOf(parsed: ParsedInput) {
  if (parsed.kind === 'error') throw new Error(`Unexpected parse error: ${parsed.message}`);
  return parsed.stored;
}

function errorOf(parsed: ParsedInput) {
  return parsed.kind === 'error' ? parsed.message : undefined;
}

const registry = new FieldTypeRegistry();

describe('resolve', () => {
  test('reads the variant from the config', () => {
    const field = registry.resolve(fieldRow('text', '{"variant": "url"}'));
    expect(field.base).toBe(textFieldType);
    expect(field.variant).toBe(urlVariant);
    expect(field.typeLabel).toBe('URL');
  });

  test('maps the legacy url type to text with the url variant', () => {
    const field = registry.resolve(fieldRow('url'));
    expect(field.base).toBe(textFieldType);
    expect(field.variant).toBe(urlVariant);
  });

  test('ignores a variant this device does not know', () => {
    const field = registry.resolve(fieldRow('text', '{"variant": "books.isbn"}'));
    expect(field.variant).toBeUndefined();
  });

  test('ignores a variant of another base type', () => {
    expect(registry.resolve(fieldRow('number', '{"variant": "url"}')).variant).toBeUndefined();
  });

  test('ignores a config that is not a JSON object', () => {
    expect(registry.resolve(fieldRow('text', 'not json')).variant).toBeUndefined();
  });

  test('falls back to unsupported for an unknown base type', () => {
    const field = registry.resolve(fieldRow('hologram'));
    expect(field.base.kind).toBe('unsupported');
    expect(field.typeLabel).toBe('Unsupported (hologram)');
    expect(field.display({ x: 1 })).toBe('{"x":1}');
  });

  test("applies a plugin's variant", () => {
    const isbn = textVariant({
      id: 'books.isbn',
      label: 'ISBN',
      normalize: (value) => value.replaceAll('-', ''),
      validate: (value) => (value.length === 13 ? undefined : 'Enter 13 digits'),
      format: (value) => `${value.slice(0, 3)}-${value.slice(3)}`,
    });
    const field = new FieldTypeRegistry([isbn]).resolve(fieldRow('text', '{"variant": "books.isbn"}'));
    expect(storedOf(field.parse('978-3-453-31717-8'))).toBe('9783453317178');
    expect(field.display('9783453317178')).toBe('978-3453317178');
    expect(field.parse('978-3-453').kind).toBe('error');
  });

  test('registers variants passed in', () => {
    const variant = textVariant({ id: 'test.shout', label: 'Shout' });
    const withVariant = new FieldTypeRegistry([variant]);
    expect(withVariant.choices.map((choice) => choice.key)).toContain('test.shout');
    expect(withVariant.resolve(fieldRow('text', '{"variant": "test.shout"}')).variant).toBe(variant);
  });
});

describe('number', () => {
  const field = registry.resolve(fieldRow('number'));

  test('reads numeric strings stored before numbers were JSON numbers', () => {
    expect(field.valueOf('12.5')).toBe(12.5);
    expect(field.errorFor('12.5')).toBeUndefined();
  });

  test('stores parsed input as a JSON number', () => {
    expect(storedOf(field.parse('42'))).toBe(42);
  });

  test('flags and still shows a value that is not a number', () => {
    expect(field.errorFor('3a')).toBeDefined();
    expect(field.display('3a')).toBe('3a');
  });

  test('has the number input hint', () => {
    expect(field.inputHint).toBe('number');
  });
});

describe('number config', () => {
  const field = registry.resolve(fieldRow('number', '{"min": 0, "max": 10}'));

  test('rejects values outside min/max', () => {
    expect(errorOf(field.parse('11'))).toBe('Enter a number from 0 to 10');
    expect(field.parse('-1').kind).toBe('error');
    expect(storedOf(field.parse('10'))).toBe(10);
  });

  test('flags stored values outside min/max', () => {
    expect(field.errorFor(12)).toBeDefined();
  });
});

describe('text config', () => {
  test('requires a full match of the pattern', () => {
    const field = registry.resolve(fieldRow('text', '{"pattern": "[A-Z]{3}"}'));
    expect(storedOf(field.parse('ABC'))).toBe('ABC');
    expect(field.parse('ABCD').kind).toBe('error');
  });

  test('ignores a pattern that does not compile', () => {
    const field = registry.resolve(fieldRow('text', '{"pattern": "("}'));
    expect(storedOf(field.parse('anything'))).toBe('anything');
  });
});

describe('text', () => {
  const field = registry.resolve(fieldRow('text'));

  test('reads values of other literal types as text', () => {
    expect(field.display(42)).toBe('42');
    expect(field.errorFor(42)).toBeUndefined();
  });

  test('stores empty input as null', () => {
    expect(storedOf(field.parse('  '))).toBeNull();
  });
});

describe('url variant', () => {
  const field = registry.resolve(fieldRow('text', '{"variant": "url"}'));

  test('rejects an invalid URL', () => {
    expect(field.parse('not a url').kind).toBe('error');
  });

  test('normalizes and links a valid one', () => {
    expect(storedOf(field.parse(' example.com '))).toBe('example.com');
    expect(field.linkFor('example.com')?.href).toBe('https://example.com/');
  });

  test('does not link an invalid stored value', () => {
    expect(field.linkFor('not a url')).toBeUndefined();
  });
});

describe('email and phone variants', () => {
  test('email validates and links via mailto', () => {
    const field = registry.resolve(fieldRow('text', '{"variant": "email"}'));
    expect(field.parse('me@').kind).toBe('error');
    expect(field.linkFor('me@example.com')?.href).toBe('mailto:me@example.com');
  });

  test('phone links its digits via tel', () => {
    const field = registry.resolve(fieldRow('text', '{"variant": "phone"}'));
    expect(field.parse('call me').kind).toBe('error');
    expect(field.linkFor('+49 (30) 123-4567')?.href).toBe('tel:+49301234567');
  });
});

describe('date', () => {
  const field = registry.resolve(fieldRow('date'));

  test('stores a plain date without a time', () => {
    expect(storedOf(field.parse('2026-07-18'))).toBe('2026-07-18');
    expect(storedOf(field.parse('2026-07-18T00:00:00'))).toBe('2026-07-18');
  });

  test('keeps the time of a timestamp', () => {
    expect(field.errorFor('2026-07-18T10:30:00')).toBeUndefined();
    expect(field.display('2026-07-18T10:30:00')).toBe('2026-07-18T10:30:00.000');
  });

  test('converts a timestamp with a zone to UTC', () => {
    expect(storedOf(field.parse('2026-07-18T10:30:00+02:00'))).toBe('2026-07-18T08:30:00.000Z');
  });

  test('rejects dates that do not exist', () => {
    expect(field.parse('2026-02-30').kind).toBe('error');
    expect(field.parse('2026-13-01').kind).toBe('error');
    expect(field.parse('yesterday').kind).toBe('error');
  });
});

describe('checkbox', () => {
  const field = registry.resolve(fieldRow('checkbox'));

  test('reads booleans, numbers and yes/no text', () => {
    expect(field.valueOf(true)).toBe(true);
    expect(field.valueOf(0)).toBe(false);
    expect(field.valueOf('Yes')).toBe(true);
    expect(field.errorFor('maybe')).toBeDefined();
    expect(field.display(true)).toBe('Yes');
  });

  test('is read as 1/0 by a number field', () => {
    expect(registry.resolve(fieldRow('number')).valueOf(true)).toBe(1);
  });
});

describe('location', () => {
  const field = registry.resolve(fieldRow('location'));

  test('parses "lat, lng" into an object', () => {
    expect(storedOf(field.parse('52.52, 13.405'))).toEqual({ lat: 52.52, lng: 13.405 });
    expect(storedOf(field.parse('geo:-33.86;151.2'))).toEqual({ lat: -33.86, lng: 151.2 });
  });

  test('rejects text and out-of-range coordinates', () => {
    expect(field.parse('Berlin').kind).toBe('error');
    expect(field.parse('91, 0').kind).toBe('error');
  });

  test('displays and links a stored position', () => {
    const raw = { lat: 52.52, lng: 13.405 };
    expect(field.display(raw)).toBe('52.52, 13.405');
    expect(field.linkFor(raw)?.host).toBe('www.openstreetmap.org');
  });

  test('is read as "lat, lng" by a text field', () => {
    expect(registry.resolve(fieldRow('text')).display({ lat: 52.52, lng: 13.405 })).toBe('52.52, 13.405');
  });
});

describe('select', () => {
  const config = encodeSelectConfig([
    { id: 'o1', name: 'Red', color: 'red' },
    { id: 'o2', name: 'Blue', color: 'blue' },
  ]);

  test('reads option names, as left behind by a field converted from text', () => {
    const field = registry.resolve(fieldRow('select', config));
    expect(field.valueOf('red')).toEqual(['o1']);
    expect(field.display('red')).toBe('Red');
  });

  test('a multi-select splits comma-separated names', () => {
    expect(registry.resolve(fieldRow('multiSelect', config)).valueOf('Red, Blue')).toEqual(['o1', 'o2']);
  });

  test('reads a single select id as a multi-select value and back', () => {
    const multi = registry.resolve(fieldRow('multiSelect', config));
    const single = registry.resolve(fieldRow('select', config));
    expect(multi.valueOf('o2')).toEqual(['o2']);
    expect(single.storedFor(['o2'])).toBe('o2');
  });

  test('rejects names of options that do not exist', () => {
    expect(registry.resolve(fieldRow('select', config)).parse('Green').kind).toBe('error');
  });
});

function baseType(id: string) {
  return registry.baseById(id);
}

describe('conversionMode', () => {
  test('rewrites ids, keeps everything else lazy', () => {
    expect(conversionMode(baseType('text'), baseType('number'))).toBe('lazy');
    expect(conversionMode(baseType('select'), baseType('multiSelect'))).toBe('lazy');
    expect(conversionMode(baseType('select'), baseType('text'))).toBe('rewrite');
    expect(conversionMode(baseType('relation'), baseType('text'))).toBe('rewrite');
  });

  test('offers nothing for files, relations as target and unknown types', () => {
    expect(conversionMode(baseType('files'), baseType('text'))).toBe('none');
    expect(conversionMode(baseType('text'), baseType('relation'))).toBe('none');
    expect(conversionMode(baseType('relation'), baseType('number'))).toBe('none');
    expect(conversionMode(baseType('hologram'), baseType('text'))).toBe('none');
  });
});
