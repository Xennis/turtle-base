import { beforeEach, expect, test } from 'vite-plus/test';

import type { AppDatabase } from '../../../core/database/app-database.ts';
import { openTestDatabase } from '../../../core/database/test-database.ts';
import { FileAccept } from '../../files/data/file-accept.ts';
import { SpacesRepository } from '../../spaces/data/spaces-repository.ts';
import { CollectionsRepository } from '../../tables/data/collections-repository.ts';
import { FieldTypeRegistry } from '../../tables/data/field-type-registry.ts';
import { FieldsRepository } from '../../tables/data/fields-repository.ts';
import { demoCodeVariant, demoPlugin } from './demo-plugin.test-support.ts';
import { PluginInstancesRepository } from './plugin-instances-repository.ts';
import { isPluginSpaceId, pluginCollectionId, pluginFieldId, PluginRegistry } from './plugin-registry.ts';

const fieldTypes = new FieldTypeRegistry(new PluginRegistry([demoPlugin]).variants);
let database: AppDatabase;
let instances: PluginInstancesRepository;

beforeEach(async () => {
  database = await openTestDatabase();
  instances = new PluginInstancesRepository(database);
});

test('adds a space with the collections and fields of the templates', async () => {
  const spaceId = await instances.add(demoPlugin);

  expect(isPluginSpaceId(spaceId, 'demo')).toBe(true);
  expect(await new SpacesRepository(database).listActive()).toMatchObject([{ id: spaceId, name: 'Demo', icon: '🧪' }]);

  const collectionId = pluginCollectionId(spaceId, 'items');
  expect(await new CollectionsRepository(database).byId(collectionId)).toMatchObject({
    space_id: spaceId,
    name: 'Items',
    icon: '📦',
    title_field_label: 'Item',
  });

  const fields = (await new FieldsRepository(database).listActiveInCollection(collectionId)).map((row) =>
    fieldTypes.resolve(row),
  );
  expect(fields.map((f) => f.id)).toEqual(
    ['status', 'code', 'rating', 'due', 'cover'].map((key) => pluginFieldId(collectionId, key)),
  );
  expect(fields.map((f) => f.name)).toEqual(['Status', 'Code', 'Rating', 'Due', 'Cover']);
  expect(fields.map((f) => f.typed.kind)).toEqual(['select', 'text', 'number', 'date', 'files']);
  const [status, code, rating, , cover] = fields;
  expect(status?.typed.config).toEqual({
    options: [
      { id: 'open', name: 'Open', color: 'gray' },
      { id: 'done', name: 'Done', color: 'green' },
    ],
  });
  expect(code?.variant).toBe(demoCodeVariant);
  expect(rating?.typed.config).toEqual({ min: 1, max: 5 });
  const coverConfig = cover?.typed.kind === 'files' ? cover.typed.config : undefined;
  expect(coverConfig?.accept.equals(FileAccept.images)).toBe(true);
  expect(coverConfig?.maxFiles).toBe(1);
});

test('adding twice creates a second instance', async () => {
  const first = await instances.add(demoPlugin);
  const second = await instances.add(demoPlugin);
  await new SpacesRepository(database).create({ name: 'Own space' });

  expect(first).not.toBe(second);
  expect((await instances.listInstances('demo')).map((space) => space.id)).toEqual([first, second]);
  expect(await instances.listInstances('other')).toEqual([]);
});
