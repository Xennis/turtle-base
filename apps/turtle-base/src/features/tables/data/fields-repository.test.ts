import { numberVariant, urlVariant } from '@turtle-base/plugin-api';
import { beforeEach, describe, expect, test } from 'vite-plus/test';

import type { AppDatabase } from '../../../core/database/app-database.ts';
import { openTestDatabase } from '../../../core/database/test-database.ts';
import type { Json } from './base-field-type.ts';
import { decodePageProperties, PagesRepository } from '../../pages/data/pages-repository.ts';
import { SpacesRepository } from '../../spaces/data/spaces-repository.ts';
import {
  multiSelectFieldType,
  numberFieldType,
  relationFieldType,
  selectFieldType,
  textFieldType,
} from './base-field-type.ts';
import { CollectionsRepository } from './collections-repository.ts';
import { FieldTypeChoice, FieldTypeRegistry } from './field-type-registry.ts';
import { FieldsRepository } from './fields-repository.ts';
import { encodeRelationConfig } from './relation-field.ts';
import { decodeFieldConfig, fieldVariantKey } from './resolved-field.ts';
import { decodeSelectOptions, encodeSelectConfig } from './select-field.ts';

let database: AppDatabase;
let fields: FieldsRepository;
let pages: PagesRepository;
let spaceId: string;
let collectionId: string;

beforeEach(async () => {
  database = await openTestDatabase();
  spaceId = await new SpacesRepository(database).create({ name: 'Space' });
  collectionId = await new CollectionsRepository(database).create({ spaceId, name: 'Books' });
  fields = new FieldsRepository(database);
  pages = new PagesRepository(database);
});

async function configOf(fieldId: string) {
  return decodeFieldConfig((await fields.byId(fieldId)).config);
}

function entryWith(fieldId: string, value: Json, title = '') {
  return pages.create({ spaceId, collectionId, title, properties: { [fieldId]: value } });
}

async function valueOf(pageId: string, fieldId: string) {
  return decodePageProperties((await pages.byId(pageId))?.properties ?? '{}')[fieldId];
}

test('create stores the variant and applies its preset', async () => {
  const variant = numberVariant({ id: 'test.count', label: 'Count', configPreset: { min: 0 } });

  const id = await fields.create({ collectionId, name: 'Copies', type: numberFieldType, variant });

  expect(await configOf(id)).toEqual({ min: 0, variant: 'test.count' });
});

test('changeType keeps the config, so select options survive a round trip', async () => {
  const id = await fields.create({ collectionId, name: 'Tags', type: selectFieldType, config: encodeSelectConfig([]) });
  const option = await fields.addSelectOption(id, 'Fiction');

  await fields.changeType(id, new FieldTypeChoice(multiSelectFieldType));
  await fields.changeType(id, new FieldTypeChoice(selectFieldType));

  const field = await fields.byId(id);
  expect(field.type).toBe('select');
  expect(decodeSelectOptions(field.config).map((o) => o.id)).toEqual([option.id]);
});

test('changeType sets and removes the variant', async () => {
  const id = await fields.create({ collectionId, name: 'Link', type: textFieldType });

  await fields.changeType(id, new FieldTypeChoice(textFieldType, urlVariant));
  expect((await configOf(id))[fieldVariantKey]).toBe('url');

  await fields.changeType(id, new FieldTypeChoice(textFieldType));
  expect(await configOf(id)).not.toHaveProperty(fieldVariantKey);
});

test('config updates keep the variant', async () => {
  const id = await fields.create({ collectionId, name: 'Link', type: textFieldType, variant: urlVariant });

  await fields.updateConfig(id, '{"pattern": "x"}');
  expect(await configOf(id)).toEqual({ pattern: 'x', variant: 'url' });

  await fields.updateConfigValues(id, { pattern: null });
  expect(await configOf(id)).toEqual({ variant: 'url' });
});

test('adds, updates and removes select options', async () => {
  const id = await fields.create({
    collectionId,
    name: 'Status',
    type: selectFieldType,
    config: encodeSelectConfig([]),
  });

  const first = await fields.addSelectOption(id, 'To do');
  const second = await fields.addSelectOption(id, 'Done');
  expect([first.color, second.color]).toEqual(['gray', 'brown']);

  await fields.updateSelectOption(id, { ...first, name: 'Open', color: 'red' });
  await fields.removeSelectOption(id, second.id);

  expect(decodeSelectOptions((await fields.byId(id)).config)).toEqual([{ id: first.id, name: 'Open', color: 'red' }]);
});

describe('type conversion', () => {
  test("text to number keeps the values and previews the ones that don't fit", async () => {
    const id = await fields.create({ collectionId, name: 'Pages', type: textFieldType });
    const fits = await entryWith(id, '320');
    await entryWith(id, 'about 300');
    await entryWith(id, '');

    const plan = await fields.planTypeChange(id, new FieldTypeChoice(numberFieldType));
    expect(plan).toMatchObject({ mode: 'lazy', valueCount: 2, invalidCount: 1, invalidSamples: ['about 300'] });

    await fields.applyTypeChange(plan);
    expect((await fields.byId(id)).type).toBe('number');
    expect(await valueOf(fits, id)).toBe('320');
  });

  test('text to multi-select creates an option per distinct name', async () => {
    const id = await fields.create({ collectionId, name: 'Genres', type: textFieldType });
    const entry = await entryWith(id, 'Fantasy, Sci-Fi');
    await entryWith(id, 'fantasy');

    await fields.changeType(id, new FieldTypeChoice(multiSelectFieldType));

    const field = new FieldTypeRegistry().resolve(await fields.byId(id));
    const options = field.typed.kind === 'multiSelect' ? field.typed.config.options : [];
    expect(options.map((o) => o.name)).toEqual(['Fantasy', 'Sci-Fi']);
    expect(field.display(await valueOf(entry, id))).toBe('Fantasy, Sci-Fi');
  });

  test('select to text rewrites option ids as names', async () => {
    const id = await fields.create({
      collectionId,
      name: 'Status',
      type: selectFieldType,
      config: encodeSelectConfig([]),
    });
    const option = await fields.addSelectOption(id, 'Reading');
    const entry = await entryWith(id, option.id);

    const plan = await fields.planTypeChange(id, new FieldTypeChoice(textFieldType));
    expect(plan.mode).toBe('rewrite');

    await fields.applyTypeChange(plan);
    expect(await valueOf(entry, id)).toBe('Reading');
  });

  test('relation to text rewrites page ids as titles', async () => {
    const authors = await new CollectionsRepository(database).create({ spaceId, name: 'Authors' });
    const author = await pages.create({ spaceId, collectionId: authors, title: 'Ursula K. Le Guin' });
    const id = await fields.create({
      collectionId,
      name: 'Author',
      type: relationFieldType,
      config: encodeRelationConfig(authors),
    });
    const entry = await entryWith(id, [author]);

    await fields.changeType(id, new FieldTypeChoice(textFieldType));

    expect(await valueOf(entry, id)).toBe('Ursula K. Le Guin');
  });

  test('a conversion that is not offered changes nothing', async () => {
    const id = await fields.create({ collectionId, name: 'Pages', type: numberFieldType });

    await fields.changeType(id, new FieldTypeChoice(relationFieldType));

    expect((await fields.byId(id)).type).toBe('number');
  });
});

test('reorderAll gives the fields the given order', async () => {
  const a = await fields.create({ collectionId, name: 'A', type: textFieldType });
  const b = await fields.create({ collectionId, name: 'B', type: textFieldType });
  const c = await fields.create({ collectionId, name: 'C', type: textFieldType });

  await fields.reorderAll([c, a, b]);

  expect((await fields.listActiveInCollection(collectionId)).map((f) => f.name)).toEqual(['C', 'A', 'B']);
});
