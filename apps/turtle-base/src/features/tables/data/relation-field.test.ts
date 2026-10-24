import { expect, test } from 'vite-plus/test';

import { decodeRelationTargetCollectionId, decodeRelationValue, encodeRelationConfig } from './relation-field.ts';

test('encodes and decodes the target collection id', () => {
  expect(decodeRelationTargetCollectionId(encodeRelationConfig('collection_1'))).toBe('collection_1');
});

test('decodeRelationTargetCollectionId returns nothing for null config', () => {
  expect(decodeRelationTargetCollectionId(null)).toBeUndefined();
});

test('decodeRelationValue reads a list of page ids', () => {
  expect(decodeRelationValue(['page_1', 'page_2'])).toEqual(['page_1', 'page_2']);
});

test('decodeRelationValue treats anything else as empty', () => {
  expect(decodeRelationValue(null)).toEqual([]);
  expect(decodeRelationValue('not a list')).toEqual([]);
});
