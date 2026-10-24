import type { TextVariant } from '@turtle-base/field-types';

import type { EntryLookup } from './entry-lookup.ts';

/**
 * A collection the app creates when the plugin is added. The user may change
 * it freely afterwards - rename, reorder, add or delete fields.
 */
export interface CollectionTemplate {
  /** Unique within the plugin, without a dot, e.g. `reading_list`. */
  readonly key: string;
  readonly name: string;

  /** In display order. */
  readonly fields: readonly FieldTemplate[];
  readonly icon?: string;

  /** Label of the built-in title column, e.g. `Title` instead of `Name`. */
  readonly titleLabel?: string;

  /** Offered as an action in the collection's toolbar. */
  readonly lookup?: EntryLookup;
}

/**
 * A field of a {@link CollectionTemplate}. Only the base types plugins need so
 * far - more are added once a plugin needs them.
 */
export type FieldTemplate =
  | TextFieldTemplate
  | NumberFieldTemplate
  | DateFieldTemplate
  | SelectFieldTemplate
  | FilesFieldTemplate;

interface FieldTemplateBase {
  /**
   * Unique within the collection, without a dot, e.g. `author`. Plugins
   * address the field by it, e.g. in {@link EntryDraft.values}.
   */
  readonly key: string;
  readonly name: string;
}

export interface TextFieldTemplate extends FieldTemplateBase {
  readonly kind: 'text';
  readonly variant?: TextVariant;
}

export interface NumberFieldTemplate extends FieldTemplateBase {
  readonly kind: 'number';
  readonly min?: number;
  readonly max?: number;
}

export interface DateFieldTemplate extends FieldTemplateBase {
  readonly kind: 'date';
}

export interface SelectFieldTemplate extends FieldTemplateBase {
  readonly kind: 'select';
  readonly options: readonly OptionTemplate[];
}

export interface FilesFieldTemplate extends FieldTemplateBase {
  readonly kind: 'files';

  /**
   * MIME types, MIME wildcards (`image/*`) and file extensions (`.xml`), like
   * HTML's `accept` attribute. Empty or missing allows any file.
   */
  readonly accept?: readonly string[];
  readonly maxFiles?: number;
}

/** One choice of a {@link SelectFieldTemplate}. */
export interface OptionTemplate {
  /**
   * Unique within the field, e.g. `read`. Stored as the option's id, so
   * {@link EntryDraft.values} refers to the option by it.
   */
  readonly key: string;
  readonly name: string;
  readonly color: OptionColor;
}

/**
 * Fixed palette for select options, like Notion's - stored by name rather
 * than as a hex value, so the app can pick fitting tones for light and dark
 * mode.
 */
export const optionColors = ['gray', 'brown', 'orange', 'yellow', 'green', 'blue', 'purple', 'pink', 'red'] as const;

export type OptionColor = (typeof optionColors)[number];
