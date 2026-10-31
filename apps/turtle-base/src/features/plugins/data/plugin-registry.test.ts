import { textVariant, type CollectionTemplate, type TurtlePlugin } from '@turtle-base/plugin-api';
import { describe, expect, test } from 'vite-plus/test';

import {
  isPluginCollectionId,
  isPluginSpaceId,
  pluginCollectionId,
  pluginIdOf,
  PluginRegistry,
  pluginSpaceId,
} from './plugin-registry.ts';

const list: CollectionTemplate = { key: 'list', name: 'List', fields: [] };

function plugin(id: string, rest: Partial<TurtlePlugin> = {}): TurtlePlugin {
  return { id, name: id.toUpperCase(), description: '', ...rest };
}

test('collects the variants of all plugins', () => {
  const variant = textVariant({ id: 'a.code', label: 'Code' });
  const registry = new PluginRegistry([plugin('a', { variants: [variant] }), plugin('b', { collections: [list] })]);

  expect(registry.variants).toEqual([variant]);
  expect(registry.addable.map((p) => p.id)).toEqual(['b']);
});

test('finds the template a collection was created from', () => {
  const registry = new PluginRegistry([plugin('b', { collections: [list] })]);
  const spaceId = pluginSpaceId('b', '6f1c-uuid');

  expect(registry.templateOf(pluginCollectionId(spaceId, 'list'))).toBe(list);
  expect(registry.templateOf(pluginCollectionId(spaceId, 'other'))).toBeUndefined();
  expect(registry.templateOf(pluginCollectionId(pluginSpaceId('c', '6f1c-uuid'), 'list'))).toBeUndefined();
  expect(registry.templateOf('6f1c-uuid')).toBeUndefined();
});

test('recognizes a plugin collection and its plugin', () => {
  const collectionId = pluginCollectionId(pluginSpaceId('b', '6f1c-uuid'), 'list');

  expect(isPluginCollectionId(collectionId)).toBe(true);
  expect(isPluginCollectionId('6f1c-uuid')).toBe(false);
  expect(pluginIdOf(collectionId)).toBe('b');
});

test('recognizes a plugin space', () => {
  expect(isPluginSpaceId(pluginSpaceId('b', '6f1c-uuid'), 'b')).toBe(true);
  expect(isPluginSpaceId(pluginSpaceId('b', '6f1c-uuid'), 'c')).toBe(false);
  expect(isPluginSpaceId('6f1c-uuid', 'b')).toBe(false);
});

describe('rejects', () => {
  test('a plugin id with a dot', () => {
    expect(() => new PluginRegistry([plugin('a.b')])).toThrow(/contains a dot/);
  });

  test('a duplicate plugin id', () => {
    expect(() => new PluginRegistry([plugin('a'), plugin('a')])).toThrow(/Duplicate plugin id/);
  });

  test('a variant without the plugin prefix', () => {
    expect(() => new PluginRegistry([plugin('a', { variants: [textVariant({ id: 'code', label: 'Code' })] })])).toThrow(
      /must start with/,
    );
  });

  test('duplicate field keys', () => {
    const collection: CollectionTemplate = {
      key: 'list',
      name: 'List',
      fields: [
        { kind: 'date', key: 'd', name: 'D' },
        { kind: 'date', key: 'd', name: 'E' },
      ],
    };
    expect(() => new PluginRegistry([plugin('a', { collections: [collection] })])).toThrow(/Duplicate field key/);
  });

  test('an option key with a dot', () => {
    const collection: CollectionTemplate = {
      key: 'list',
      name: 'List',
      fields: [{ kind: 'select', key: 's', name: 'S', options: [{ key: 'o.1', name: 'O', color: 'gray' }] }],
    };
    expect(() => new PluginRegistry([plugin('a', { collections: [collection] })])).toThrow(/option key/);
  });
});
