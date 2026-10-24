import { describe, expect, test } from 'vite-plus/test';

import { numberVariant, patternTextVariant, textVariant, type FieldVariant } from './field-variant.ts';

describe('patternTextVariant', () => {
  const variant = patternTextVariant({ id: 'digits', label: 'Digits', pattern: /\d+/, message: 'Digits only' });

  test('accepts a full match', () => {
    expect(variant.validate('123')).toBeUndefined();
  });

  test('rejects a partial match', () => {
    expect(variant.validate('123a')).toBe('Digits only');
    expect(variant.validate('a123')).toBe('Digits only');
  });

  test('anchors every alternative', () => {
    const alternatives = patternTextVariant({ id: 'ab', label: 'AB', pattern: /a|ab/, message: 'No' });
    expect(alternatives.validate('ab')).toBeUndefined();
    expect(alternatives.validate('abc')).toBe('No');
  });
});

test('a variant without hooks passes values through', () => {
  const variant = numberVariant({ id: 'plain', label: 'Plain' });
  expect(variant.inputHint).toBe('number');
  expect(variant.validate(3)).toBeUndefined();
  expect(variant.normalize(3)).toBe(3);
  expect(variant.format(3)).toBeUndefined();
  expect(variant.link(3)).toBeUndefined();
});

test('the base type narrows the value type', () => {
  const variant: FieldVariant = textVariant({ id: 'upper', label: 'Upper', normalize: (v) => v.toUpperCase() });
  expect(variant.baseTypeId === 'text' ? variant.normalize('abc') : undefined).toBe('ABC');
});
