import { matchesFully, type StorageKind } from '@turtle-base/plugin-api';

import { FileAccept } from '../../files/data/file-accept.ts';
import { parseIsoDate, parseNumber } from './field-validation.ts';
import { relationTargetCollectionIdKey, decodeRelationValue } from './relation-field.ts';
import { decodeSelectOptionsJson, encodeSelectValue, resolveSelectValue, type SelectOption } from './select-field.ts';

/** A value as stored in `pages.properties`. */
export type Json = string | number | boolean | null | readonly Json[] | { readonly [key: string]: Json };

/** A field's whole `fields.config`, including keys of other concerns (e.g. `variant`). */
export type ConfigJson = Readonly<Record<string, unknown>>;

/**
 * One of the app's closed set of field types - each with its own storage
 * form, editor and config (see FIELD_TYPES.md). Semantics on top of a base
 * type (URL, ISBN, ...) are `FieldVariant`s instead.
 *
 * `V` is a decoded value, `C` the field's typed config. Every method taking a
 * raw stored value is tolerant: values may come from a previous type of the
 * field, or from another device via sync.
 */
export interface BaseFieldType<V, C> {
  /** Stored in `fields.type`. */
  readonly id: string;
  readonly label: string;
  readonly storage: StorageKind;

  /** Shown for a stored value `decode` can't read, or typed input `fromPlain` can't parse. */
  readonly invalidMessage: string;

  decodeConfig(json: ConfigJson): C;

  /** Undefined when `raw` can't be read as this type. */
  decode(raw: unknown, config: C): V | undefined;
  encode(value: V, config: C): Json;

  /** Canonical text form, e.g. for converting to another type. */
  toPlain(value: V, config: C): string;

  /** Parses typed input. Undefined when `text` isn't a valid value. */
  fromPlain(text: string, config: C): V | undefined;

  /** Display text - differs from `toPlain` where formatting is meant for reading (e.g. a checkbox's Yes/No). */
  display(value: V, config: C): string;

  /** Config constraints (e.g. min/max). Undefined if `value` satisfies them. */
  validate(value: V, config: C): string | undefined;

  /** Where tapping the value leads - a variant's link takes precedence. */
  link(value: V, config: C): URL | undefined;
}

type Definition<V, C> = Omit<BaseFieldType<V, C>, 'invalidMessage' | 'display' | 'validate' | 'link'> &
  Partial<Pick<BaseFieldType<V, C>, 'invalidMessage' | 'display' | 'validate' | 'link'>>;

function defineFieldType<K extends string, V, C>(
  kind: K,
  definition: Definition<V, C>,
): BaseFieldType<V, C> & { readonly kind: K } {
  return {
    kind,
    invalidMessage: `Enter a valid ${definition.label.toLowerCase()}`,
    display: (value, config) => definition.toPlain(value, config),
    validate: () => undefined,
    link: () => undefined,
    ...definition,
  };
}

/** Plain text of a stored value whatever type wrote it, for reading it as another literal type. */
export function plainOfRaw(raw: unknown): string {
  if (raw === null || raw === undefined) return '';
  if (typeof raw === 'string') return raw;
  if (typeof raw === 'number') return formatPlainNumber(raw);
  if (Array.isArray(raw)) return raw.map(plainOfRaw).join(', ');
  if (typeof raw === 'object') return geoPointOf(raw)?.toString() ?? JSON.stringify(raw);
  if (typeof raw === 'boolean' || typeof raw === 'bigint') return String(raw);
  // Never JSON - nothing to show.
  return '';
}

/** 3.0 as "3" - which JavaScript does anyway, unlike Dart. */
export function formatPlainNumber(value: number): string {
  return String(value);
}

export interface TextConfig {
  /**
   * A regular expression values must fully match. Undefined when unset - or
   * when it doesn't compile, so a broken pattern never blocks input.
   */
  readonly pattern?: RegExp;
}

export const textPatternKey = 'pattern';

export function tryParsePattern(source: string): RegExp | undefined {
  try {
    return new RegExp(source);
  } catch {
    return undefined;
  }
}

export const textFieldType = defineFieldType<'text', string, TextConfig>('text', {
  id: 'text',
  label: 'Text',
  storage: 'string',
  decodeConfig: (json) => {
    const source = json[textPatternKey];
    const pattern = typeof source === 'string' && source.length > 0 ? tryParsePattern(source) : undefined;
    return pattern === undefined ? {} : { pattern };
  },
  decode: (raw) => plainOfRaw(raw),
  encode: (value) => value,
  toPlain: (value) => value,
  fromPlain: (text) => text,
  validate: (value, { pattern }) =>
    pattern === undefined || matchesFully(pattern, value) ? undefined : `Must match ${pattern.source}`,
});

export interface NumberConfig {
  readonly min?: number;
  readonly max?: number;
}

export const numberMinKey = 'min';
export const numberMaxKey = 'max';

export const numberFieldType = defineFieldType<'number', number, NumberConfig>('number', {
  id: 'number',
  label: 'Number',
  storage: 'number',
  decodeConfig: (json) => {
    const min = json[numberMinKey];
    const max = json[numberMaxKey];
    return { ...(typeof min === 'number' ? { min } : {}), ...(typeof max === 'number' ? { max } : {}) };
  },
  // Also reads numeric strings - how numbers were stored before FIELD_TYPES.md, and still are until edited.
  decode: (raw) => {
    if (typeof raw === 'number') return raw;
    if (typeof raw === 'string') return parseNumber(raw);
    if (typeof raw === 'boolean') return raw ? 1 : 0;
    return undefined;
  },
  encode: (value) => value,
  toPlain: (value) => formatPlainNumber(value),
  fromPlain: (text) => parseNumber(text),
  validate: (value, { min, max }) => {
    if (min !== undefined && max !== undefined && (value < min || value > max)) {
      return `Enter a number from ${formatPlainNumber(min)} to ${formatPlainNumber(max)}`;
    }
    if (min !== undefined && value < min) return `Enter a number of at least ${formatPlainNumber(min)}`;
    if (max !== undefined && value > max) return `Enter a number of at most ${formatPlainNumber(max)}`;
    return undefined;
  },
});

/**
 * Stored as ISO-8601: `yyyy-MM-dd` for a plain date, the full timestamp when
 * it has a time. The decoded value is that canonical string, see
 * {@link parseIsoDate}.
 */
export const dateFieldType = defineFieldType<'date', string, null>('date', {
  id: 'date',
  label: 'Date',
  storage: 'string',
  invalidMessage: 'Enter a valid date, e.g. 2026-07-18',
  decodeConfig: () => null,
  decode: (raw) => (typeof raw === 'string' ? parseIsoDate(raw) : undefined),
  encode: (value) => value,
  toPlain: (value) => value,
  fromPlain: (text) => parseIsoDate(text),
});

const truthy = new Set(['true', 'yes', 'y', 'x', '1', 'on', 'checked']);
const falsy = new Set(['false', 'no', 'n', '0', 'off', 'unchecked']);

function parseCheckbox(text: string): boolean | undefined {
  const lower = text.trim().toLowerCase();
  if (truthy.has(lower)) return true;
  if (falsy.has(lower)) return false;
  return undefined;
}

export const checkboxFieldType = defineFieldType<'checkbox', boolean, null>('checkbox', {
  id: 'checkbox',
  label: 'Checkbox',
  storage: 'boolean',
  decodeConfig: () => null,
  decode: (raw) => {
    if (typeof raw === 'boolean') return raw;
    if (typeof raw === 'number') return raw !== 0;
    if (typeof raw === 'string') return parseCheckbox(raw);
    return undefined;
  },
  encode: (value) => value,
  toPlain: (value) => String(value),
  fromPlain: (text) => parseCheckbox(text),
  display: (value) => (value ? 'Yes' : 'No'),
});

export interface SelectConfig {
  readonly options: readonly SelectOption[];
}

function optionFor(idOrName: string, { options }: SelectConfig): SelectOption | undefined {
  const trimmed = idOrName.trim();
  const lower = trimmed.toLowerCase();
  return (
    options.find((option) => option.id === trimmed) ?? options.find((option) => option.name.toLowerCase() === lower)
  );
}

/** Values are option ids - a single one for a select, a list for a multi-select (see select-field.ts). */
function defineSelectFieldType<K extends 'select' | 'multiSelect'>(kind: K, multiple: boolean) {
  return {
    ...defineFieldType<K, readonly string[], SelectConfig>(kind, {
      id: kind,
      label: multiple ? 'Multi-select' : 'Select',
      storage: multiple ? 'stringList' : 'string',
      invalidMessage: 'Pick one of the options',
      decodeConfig: (json) => ({ options: decodeSelectOptionsJson(json) }),
      // Besides option ids, reads option names - how a field converted from text stores its values until
      // they're edited. Ids of options deleted since are skipped, like in resolveSelectValue.
      decode: (raw, config) => {
        let items: string[];
        if (typeof raw === 'string') items = multiple ? raw.split(',') : [raw];
        else if (Array.isArray(raw)) items = raw.map(plainOfRaw);
        else items = [plainOfRaw(raw)];
        return items.flatMap((item) => {
          const option = optionFor(item, config);
          return option === undefined ? [] : [option.id];
        });
      },
      encode: (value) => encodeSelectValue(value, multiple),
      toPlain: (value, config) =>
        resolveSelectValue(config.options, value)
          .map((option) => option.name)
          .join(', '),
      fromPlain: (text, config) => {
        const ids: string[] = [];
        for (const name of multiple ? text.split(',') : [text]) {
          if (name.trim().length === 0) continue;
          const option = optionFor(name, config);
          if (option === undefined) return undefined;
          ids.push(option.id);
        }
        return ids;
      },
    }),
    multiple,
  };
}

export const selectFieldType = defineSelectFieldType('select', false);
export const multiSelectFieldType = defineSelectFieldType('multiSelect', true);

export interface RelationConfig {
  readonly targetCollectionId?: string;
}

/**
 * Values are page ids of the target collection. Their titles live in other
 * rows, so plain text conversion goes through FieldsRepository.
 */
export const relationFieldType = defineFieldType<'relation', readonly string[], RelationConfig>('relation', {
  id: 'relation',
  label: 'Relation',
  storage: 'stringList',
  decodeConfig: (json) => {
    const target = json[relationTargetCollectionIdKey];
    return typeof target === 'string' ? { targetCollectionId: target } : {};
  },
  decode: (raw) => (Array.isArray(raw) ? decodeRelationValue(raw) : undefined),
  encode: (value) => value,
  toPlain: (value) => value.join(', '),
  fromPlain: () => undefined,
});

/** A position in WGS 84 degrees, e.g. from GPS. */
export class GeoPoint {
  readonly lat: number;
  readonly lng: number;

  private constructor(lat: number, lng: number) {
    this.lat = lat;
    this.lng = lng;
  }

  /** Undefined when `lat`/`lng` are out of range. */
  static tryCreate(lat: number, lng: number): GeoPoint | undefined {
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return undefined;
    return new GeoPoint(lat, lng);
  }

  toJson(): { lat: number; lng: number } {
    return { lat: this.lat, lng: this.lng };
  }

  toString(): string {
    return `${formatPlainNumber(this.lat)}, ${formatPlainNumber(this.lng)}`;
  }
}

function geoPointOf(json: object): GeoPoint | undefined {
  const lat: unknown = Reflect.get(json, 'lat');
  const lng: unknown = Reflect.get(json, 'lng');
  return typeof lat === 'number' && typeof lng === 'number' ? GeoPoint.tryCreate(lat, lng) : undefined;
}

const latLng = /^(?:geo:)?\s*(-?\d+(?:\.\d+)?)\s*[,;\s]\s*(-?\d+(?:\.\d+)?)\s*$/;

function parseGeoPoint(text: string): GeoPoint | undefined {
  const match = latLng.exec(text.trim());
  if (match === null) return undefined;
  return GeoPoint.tryCreate(Number(match[1]), Number(match[2]));
}

/** Stored as `{"lat": 52.52, "lng": 13.405}`, typed in as "lat, lng". */
export const locationFieldType = defineFieldType<'location', GeoPoint, null>('location', {
  id: 'location',
  label: 'Location',
  storage: 'object',
  invalidMessage: 'Enter a position as "latitude, longitude", e.g. 52.52, 13.405',
  decodeConfig: () => null,
  decode: (raw) => {
    if (typeof raw === 'string') return parseGeoPoint(raw);
    if (typeof raw === 'object' && raw !== null && !Array.isArray(raw)) return geoPointOf(raw);
    return undefined;
  },
  encode: (value) => value.toJson(),
  toPlain: (value) => value.toString(),
  fromPlain: (text) => parseGeoPoint(text),
  link: ({ lat, lng }) => {
    const url = new URL('https://www.openstreetmap.org/');
    url.search = new URLSearchParams({ mlat: String(lat), mlon: String(lng) }).toString();
    url.hash = `map=15/${lat}/${lng}`;
    return url;
  },
});

export interface FilesConfig {
  readonly accept: FileAccept;

  /** Undefined for no limit, 1 for a single-file field. */
  readonly maxFiles?: number;
}

export const filesAcceptKey = 'accept';
export const filesMaxFilesKey = 'maxFiles';

/**
 * Files attached to the entry. Unlike every other type, the value isn't in
 * `pages.properties` but in the attachments table (see AttachmentsRepository),
 * so the property-based methods find nothing - views read and write it
 * through the repository instead.
 */
export const filesFieldType = defineFieldType<'files', readonly string[], FilesConfig>('files', {
  id: 'files',
  label: 'Files',
  storage: 'external',
  decodeConfig: (json) => {
    const accept = json[filesAcceptKey];
    const maxFiles = json[filesMaxFilesKey];
    return {
      accept: Array.isArray(accept)
        ? new FileAccept(accept.filter((item) => typeof item === 'string'))
        : FileAccept.any,
      ...(typeof maxFiles === 'number' && Number.isInteger(maxFiles) && maxFiles > 0 ? { maxFiles } : {}),
    };
  },
  decode: () => undefined,
  encode: () => null,
  toPlain: () => '',
  fromPlain: () => undefined,
});

/**
 * A type this app version doesn't know, e.g. one a newer version synced in.
 * Shown read-only as plain text rather than failing.
 */
export function unsupportedFieldType(id: string) {
  return defineFieldType<'unsupported', unknown, null>('unsupported', {
    id,
    label: `Unsupported (${id})`,
    storage: 'object',
    decodeConfig: () => null,
    decode: (raw) => raw,
    // Written back as it came - it was JSON when it was read.
    // oxlint-disable-next-line typescript/no-unsafe-type-assertion
    encode: (value) => value as Json,
    toPlain: (value) => plainOfRaw(value),
    fromPlain: () => undefined,
  });
}

export type TextFieldType = typeof textFieldType;
export type NumberFieldType = typeof numberFieldType;
export type DateFieldType = typeof dateFieldType;
export type CheckboxFieldType = typeof checkboxFieldType;
export type SelectFieldType = typeof selectFieldType | typeof multiSelectFieldType;
export type RelationFieldType = typeof relationFieldType;
export type LocationFieldType = typeof locationFieldType;
export type FilesFieldType = typeof filesFieldType;
export type UnsupportedFieldType = ReturnType<typeof unsupportedFieldType>;

/** Any base type, told apart by `kind`. */
export type AnyFieldType =
  | TextFieldType
  | NumberFieldType
  | DateFieldType
  | CheckboxFieldType
  | SelectFieldType
  | RelationFieldType
  | LocationFieldType
  | FilesFieldType
  | UnsupportedFieldType;

/** A field's config together with its type's kind - narrowing `kind` types `config`. */
export type TypedConfig =
  | { readonly kind: 'text'; readonly config: TextConfig }
  | { readonly kind: 'number'; readonly config: NumberConfig }
  | { readonly kind: 'select' | 'multiSelect'; readonly config: SelectConfig }
  | { readonly kind: 'relation'; readonly config: RelationConfig }
  | { readonly kind: 'files'; readonly config: FilesConfig }
  | { readonly kind: 'date' | 'checkbox' | 'location' | 'unsupported'; readonly config: null };

export function decodeTypedConfig(base: AnyFieldType, json: ConfigJson): TypedConfig {
  switch (base.kind) {
    case 'text':
      return { kind: base.kind, config: base.decodeConfig(json) };
    case 'number':
      return { kind: base.kind, config: base.decodeConfig(json) };
    case 'select':
    case 'multiSelect':
      return { kind: base.kind, config: base.decodeConfig(json) };
    case 'relation':
      return { kind: base.kind, config: base.decodeConfig(json) };
    case 'files':
      return { kind: base.kind, config: base.decodeConfig(json) };
    // Only kinds without a config get here - a new kind with one fails to type check against TypedConfig.
    default:
      return { kind: base.kind, config: null };
  }
}

/** In the order the type picker offers them. */
export const baseFieldTypes: readonly AnyFieldType[] = [
  textFieldType,
  numberFieldType,
  dateFieldType,
  checkboxFieldType,
  selectFieldType,
  multiSelectFieldType,
  relationFieldType,
  locationFieldType,
  filesFieldType,
];

/**
 * The type with its value and config types erased, so it can be called with
 * whatever a field resolved to. Sound as long as `config` came from this
 * type's own `decodeConfig` and values from its own `decode`/`fromPlain`,
 * which `ResolvedField` guarantees.
 */
export function erased(type: AnyFieldType): BaseFieldType<unknown, unknown> {
  return type;
}
