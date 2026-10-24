import { optionColors } from '@turtle-base/plugin-api';
import { expect, test } from 'vite-plus/test';

import {
  decodeSelectOptions,
  decodeSelectValue,
  encodeSelectConfig,
  encodeSelectValue,
  nextOptionColor,
  resolveSelectValue,
  type SelectOption,
} from './select-field.ts';

const todo: SelectOption = { id: 'o1', name: 'To do', color: 'gray' };
const done: SelectOption = { id: 'o2', name: 'Done', color: 'green' };

test('encodes and decodes options in order', () => {
  expect(decodeSelectOptions(encodeSelectConfig([todo, done]))).toEqual([todo, done]);
});

test('decodeSelectOptions returns empty for null or option-less config', () => {
  expect(decodeSelectOptions(null)).toEqual([]);
  expect(decodeSelectOptions('{"targetCollectionId": "c1"}')).toEqual([]);
});

test('an unknown stored color falls back to gray', () => {
  const options = decodeSelectOptions('{"options": [{"id": "o1", "name": "A", "color": "teal"}]}');
  expect(options).toEqual([{ id: 'o1', name: 'A', color: 'gray' }]);
});

test('skips malformed options', () => {
  expect(decodeSelectOptions('{"options": [{"id": 1}, {"id": "o1", "name": "A", "color": "red"}]}')).toEqual([
    { id: 'o1', name: 'A', color: 'red' },
  ]);
});

test('decodeSelectValue accepts both a single id and a list', () => {
  expect(decodeSelectValue('o1')).toEqual(['o1']);
  expect(decodeSelectValue(['o1', 'o2'])).toEqual(['o1', 'o2']);
  expect(decodeSelectValue('')).toEqual([]);
  expect(decodeSelectValue(null)).toEqual([]);
  expect(decodeSelectValue(42)).toEqual([]);
});

test('resolveSelectValue skips ids of deleted options', () => {
  expect(resolveSelectValue([todo, done], ['o2', 'gone', 'o1'])).toEqual([done, todo]);
});

test('encodeSelectValue stores a single id or a list', () => {
  expect(encodeSelectValue(['o1'], false)).toBe('o1');
  expect(encodeSelectValue([], false)).toBeNull();
  expect(encodeSelectValue(['o1', 'o2'], true)).toEqual(['o1', 'o2']);
});

test('nextOptionColor rotates through the palette', () => {
  expect(nextOptionColor([])).toBe(optionColors[0]);
  expect(nextOptionColor([todo])).toBe(optionColors[1]);
  expect(nextOptionColor(Array.from(optionColors, () => todo))).toBe(optionColors[0]);
});
