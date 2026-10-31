import { pluginApiVersion, textVariant, type PluginManifest, type TurtlePlugin } from '@turtle-base/plugin-api';
import { describe, expect, test } from 'vite-plus/test';

import { pluginOfModule, validatePlugin } from './plugin-rules.ts';

const code = textVariant({ id: 'demo.code', label: 'Code' });

const demo: TurtlePlugin = {
  id: 'demo',
  name: 'Demo',
  description: '',
  variants: [code],
  collections: [
    {
      key: 'items',
      name: 'Items',
      fields: [
        { kind: 'text', key: 'code', name: 'Code', variant: code },
        { kind: 'select', key: 'status', name: 'Status', options: [{ key: 'open', name: 'Open', color: 'gray' }] },
        { kind: 'files', key: 'cover', name: 'Cover', accept: ['image/*'], maxFiles: 1 },
      ],
      lookup: { actionLabel: 'Add', searchHint: '', search: () => Promise.resolve([]) },
    },
  ],
};

const someManifest: PluginManifest = {
  id: 'demo',
  name: 'Demo',
  version: '1.0.0',
  apiVersion: pluginApiVersion,
  author: '',
  description: '',
  main: 'demo.js',
  sha256: '0'.repeat(64),
  permissions: {},
};

test('returns a valid plugin itself', () => {
  expect(validatePlugin(demo)).toBe(demo);
});

describe('rejects', () => {
  test('something that is not a plugin', () => {
    expect(() => validatePlugin(undefined)).toThrow(/Not a plugin/);
    expect(() => validatePlugin({ id: 'a', name: 'A' })).toThrow(/description/);
  });

  test('a variant without its functions', () => {
    const variant = { id: 'demo.x', label: 'X', baseTypeId: 'text' };
    expect(() => validatePlugin({ ...demo, variants: [variant] })).toThrow(/variants\.0\.validate/);
  });

  test('an unknown option color', () => {
    const collection = {
      key: 'items',
      name: 'Items',
      fields: [{ kind: 'select', key: 's', name: 'S', options: [{ key: 'o', name: 'O', color: 'teal' }] }],
    };
    expect(() => validatePlugin({ ...demo, collections: [collection] })).toThrow(/color/);
  });

  test('a plugin id with a dot', () => {
    expect(() => validatePlugin({ ...demo, id: 'de.mo', variants: [] })).toThrow(/contains a dot/);
  });

  test('a variant without the plugin prefix', () => {
    expect(() => validatePlugin({ ...demo, variants: [textVariant({ id: 'code', label: 'Code' })] })).toThrow(
      /must start with/,
    );
  });

  test('duplicate field keys', () => {
    const collection = {
      key: 'items',
      name: 'Items',
      fields: [
        { kind: 'date', key: 'd', name: 'D' },
        { kind: 'date', key: 'd', name: 'E' },
      ],
    };
    expect(() => validatePlugin({ ...demo, collections: [collection] })).toThrow(/Duplicate field key/);
  });
});

test('takes the plugin of a module matching its manifest', () => {
  expect(pluginOfModule({ default: demo }, someManifest)).toBe(demo);
  expect(() => pluginOfModule({ default: demo }, { ...someManifest, id: 'other' })).toThrow(/manifest names other/);
  expect(() => pluginOfModule({}, someManifest)).toThrow(/Not a plugin/);
});
