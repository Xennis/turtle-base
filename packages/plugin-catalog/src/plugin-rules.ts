import {
  optionColors,
  type EntryLookup,
  type NumberVariant,
  type PluginManifest,
  type TextVariant,
  type TurtlePlugin,
} from '@turtle-base/plugin-api';
import * as v from 'valibot';

/**
 * Separates the parts of the ids a plugin's rows get, e.g.
 * `books.<uuid>.reading_list` - see plugin-api's README.
 */
export const idSeparator = '.';

/**
 * `value` as a {@link TurtlePlugin}, after checking its shape (a bundle's
 * default export can be anything) and the id rules of plugin-api's README.
 * Throws an error naming what's wrong. Returns `value` itself, so the
 * plugin's objects keep their identity.
 */
export function validatePlugin(value: unknown): TurtlePlugin {
  if (!hasPluginShape(value)) {
    const issue = v.safeParse(pluginSchema, value).issues?.[0];
    throw new Error(
      `Not a plugin: ${issue === undefined ? '' : `${v.getDotPath(issue) ?? 'value'}: ${issue.message}`}`,
    );
  }
  const plugin = value;
  checkKey(plugin.id, 'plugin id');
  for (const variant of plugin.variants ?? []) {
    if (!variant.id.startsWith(`${plugin.id}${idSeparator}`)) {
      throw new Error(`Variant ${variant.id} of plugin ${plugin.id} must start with "${plugin.id}."`);
    }
  }
  const collections = plugin.collections ?? [];
  checkUnique(
    collections.map((collection) => collection.key),
    `collection key in ${plugin.id}`,
  );
  for (const collection of collections) {
    checkUnique(
      collection.fields.map((field) => field.key),
      `field key in ${plugin.id}.${collection.key}`,
    );
    for (const field of collection.fields) {
      if (field.kind === 'select') {
        checkUnique(
          field.options.map((option) => option.key),
          `option key in ${collection.key}.${field.key}`,
        );
      }
    }
  }
  return plugin;
}

/**
 * The plugin a bundle's module exports as default, checked by
 * {@link validatePlugin} and against the id of its manifest.
 */
export function pluginOfModule(module: unknown, manifest: PluginManifest): TurtlePlugin {
  const exported: unknown = typeof module === 'object' && module !== null ? Reflect.get(module, 'default') : undefined;
  const plugin = validatePlugin(exported);
  if (plugin.id !== manifest.id)
    throw new Error(`The bundle holds plugin ${plugin.id}, the manifest names ${manifest.id}`);
  return plugin;
}

function hasPluginShape(value: unknown): value is TurtlePlugin {
  return v.is(pluginSchema, value);
}

function checkUnique(keys: readonly string[], what: string): void {
  const seen = new Set<string>();
  for (const key of keys) {
    checkKey(key, what);
    if (seen.has(key)) throw new Error(`Duplicate ${what}: ${key}`);
    seen.add(key);
  }
}

function checkKey(key: string, what: string): void {
  if (key.length === 0 || key.includes(idSeparator))
    throw new Error(`Invalid ${what} "${key}": empty or contains a dot`);
}

function fn<T>() {
  return v.custom<T>((input) => typeof input === 'function', 'Expected a function');
}

const variantBase = {
  id: v.string(),
  label: v.string(),
  inputHint: v.optional(v.picklist(['text', 'number', 'url', 'email', 'phone'])),
  configPreset: v.optional(v.record(v.string(), v.unknown())),
};

const variantSchema = v.variant('baseTypeId', [
  v.object({
    ...variantBase,
    baseTypeId: v.literal('text'),
    validate: fn<TextVariant['validate']>(),
    normalize: fn<TextVariant['normalize']>(),
    format: fn<TextVariant['format']>(),
    link: fn<TextVariant['link']>(),
  }),
  v.object({
    ...variantBase,
    baseTypeId: v.literal('number'),
    validate: fn<NumberVariant['validate']>(),
    normalize: fn<NumberVariant['normalize']>(),
    format: fn<NumberVariant['format']>(),
    link: fn<NumberVariant['link']>(),
  }),
]);

const fieldBase = { key: v.string(), name: v.string() };

const fieldSchema = v.variant('kind', [
  v.object({ ...fieldBase, kind: v.literal('text'), variant: v.optional(variantSchema) }),
  v.object({ ...fieldBase, kind: v.literal('number'), min: v.optional(v.number()), max: v.optional(v.number()) }),
  v.object({ ...fieldBase, kind: v.literal('date') }),
  v.object({
    ...fieldBase,
    kind: v.literal('select'),
    options: v.array(v.object({ key: v.string(), name: v.string(), color: v.picklist(optionColors) })),
  }),
  v.object({
    ...fieldBase,
    kind: v.literal('files'),
    accept: v.optional(v.array(v.string())),
    maxFiles: v.optional(v.pipe(v.number(), v.integer(), v.minValue(1))),
  }),
]);

const lookupSchema = v.object({
  actionLabel: v.string(),
  searchHint: v.string(),
  uniqueFieldKey: v.optional(v.string()),
  search: fn<EntryLookup['search']>(),
});

const pluginSchema = v.object({
  id: v.string(),
  name: v.string(),
  description: v.string(),
  icon: v.optional(v.string()),
  variants: v.optional(v.array(variantSchema)),
  collections: v.optional(
    v.array(
      v.object({
        key: v.string(),
        name: v.string(),
        fields: v.array(fieldSchema),
        icon: v.optional(v.string()),
        titleLabel: v.optional(v.string()),
        lookup: v.optional(lookupSchema),
      }),
    ),
  ),
});
