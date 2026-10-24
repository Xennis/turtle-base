import type { FieldVariant, InputHint } from '@turtle-base/plugin-api';

import type { Field } from '../../../core/database/schema.ts';
import { erased, plainOfRaw, type AnyFieldType, type BaseFieldType, type Json } from './base-field-type.ts';

/** Key of a field's variant id in `fields.config`, next to its base type's own config - see FIELD_TYPES.md. */
export const fieldVariantKey = 'variant';

/** A field's `fields.config` as JSON - empty when there is none, or it doesn't parse as an object. */
export function decodeFieldConfig(config: string | null): Readonly<Record<string, unknown>> {
  if (config === null) return {};
  try {
    const decoded: unknown = JSON.parse(config);
    return typeof decoded === 'object' && decoded !== null && !Array.isArray(decoded) ? { ...decoded } : {};
  } catch {
    return {};
  }
}

/** The outcome of parsing typed input for a field: either the value to store or why it's invalid. */
export type ParsedInput =
  | {
      readonly kind: 'value';
      /** What to put into `pages.properties` - null for empty input. */
      readonly stored: Json;
    }
  | { readonly kind: 'error'; readonly message: string };

/**
 * A field row with its base type, variant and typed config resolved (see
 * FieldTypeRegistry.resolve) - the one place views read, write and validate
 * property values through.
 */
export class ResolvedField {
  readonly row: Field;
  readonly base: AnyFieldType;

  /** Undefined when the field has none, or this device doesn't know it. */
  readonly variant: FieldVariant | undefined;

  /** What `base.decodeConfig` made of the field's config. */
  readonly config: unknown;
  readonly #type: BaseFieldType<unknown, unknown>;

  constructor(row: Field, base: AnyFieldType, variant: FieldVariant | undefined, config: unknown) {
    this.row = row;
    this.base = base;
    this.variant = variant;
    this.config = config;
    this.#type = erased(base);
  }

  get id(): string {
    return this.row.id;
  }

  get name(): string {
    return this.row.name;
  }

  get typeLabel(): string {
    return this.variant?.label ?? this.base.label;
  }

  get inputHint(): InputHint | undefined {
    return this.variant?.inputHint ?? (this.base.kind === 'number' ? 'number' : undefined);
  }

  static isEmptyRaw(raw: unknown): boolean {
    return raw === null || raw === undefined || raw === '' || (Array.isArray(raw) && raw.length === 0);
  }

  /** The decoded value - undefined when empty or unreadable as {@link base}. */
  valueOf(raw: unknown): unknown {
    return ResolvedField.isEmptyRaw(raw) ? undefined : this.#type.decode(raw, this.config);
  }

  /** Why a stored value is invalid, undefined when it's empty or valid. */
  errorFor(raw: unknown): string | undefined {
    if (ResolvedField.isEmptyRaw(raw)) return undefined;
    const value = this.#type.decode(raw, this.config);
    if (value === undefined) return this.base.invalidMessage;
    return this.validate(value);
  }

  validate(value: unknown): string | undefined {
    return this.#type.validate(value, this.config) ?? this.#variantValidate(value);
  }

  /**
   * Display text. A value that can't be decoded shows as its plain text,
   * never as empty - see {@link errorFor} to flag it.
   */
  display(raw: unknown): string {
    if (ResolvedField.isEmptyRaw(raw)) return '';
    const value = this.#type.decode(raw, this.config);
    if (value === undefined) return plainOfRaw(raw);
    return this.#variantFormat(value) ?? this.#type.display(value, this.config);
  }

  linkFor(raw: unknown): URL | undefined {
    if (this.errorFor(raw) !== undefined) return undefined;
    const value = this.valueOf(raw);
    if (value === undefined) return undefined;
    return this.#variantLink(value) ?? this.#type.link(value, this.config);
  }

  /**
   * What to store for a value from elsewhere (e.g. a plugin's entry draft) in
   * the JSON shape of {@link base}: decoded, normalized and validated like
   * typed input. Undefined when it's empty or doesn't fit.
   */
  storedFor(raw: unknown): Json | undefined {
    const decoded = this.valueOf(raw);
    if (decoded === undefined) return undefined;
    const value = this.#variantNormalize(decoded);
    if (this.validate(value) !== undefined) return undefined;
    const stored = this.#type.encode(value, this.config);
    return ResolvedField.isEmptyRaw(stored) ? undefined : stored;
  }

  /** Parses typed input: base type parse, then the variant's normalize, then both validations. */
  parse(text: string): ParsedInput {
    if (text.trim().length === 0) return { kind: 'value', stored: null };
    const parsed = this.#type.fromPlain(text, this.config);
    if (parsed === undefined) return { kind: 'error', message: this.base.invalidMessage };
    const value = this.#variantNormalize(parsed);
    const message = this.validate(value);
    if (message !== undefined) return { kind: 'error', message };
    return { kind: 'value', stored: this.#type.encode(value, this.config) };
  }

  // A variant only ever sits on its own base type (see FieldTypeRegistry.resolve),
  // so a value of the wrong JavaScript type means "not this variant's business".

  #variantValidate(value: unknown): string | undefined {
    const variant = this.variant;
    if (variant?.baseTypeId === 'text' && typeof value === 'string') return variant.validate(value);
    if (variant?.baseTypeId === 'number' && typeof value === 'number') return variant.validate(value);
    return undefined;
  }

  #variantNormalize(value: unknown): unknown {
    const variant = this.variant;
    if (variant?.baseTypeId === 'text' && typeof value === 'string') return variant.normalize(value);
    if (variant?.baseTypeId === 'number' && typeof value === 'number') return variant.normalize(value);
    return value;
  }

  #variantFormat(value: unknown): string | undefined {
    const variant = this.variant;
    if (variant?.baseTypeId === 'text' && typeof value === 'string') return variant.format(value);
    if (variant?.baseTypeId === 'number' && typeof value === 'number') return variant.format(value);
    return undefined;
  }

  #variantLink(value: unknown): URL | undefined {
    const variant = this.variant;
    if (variant?.baseTypeId === 'text' && typeof value === 'string') return variant.link(value);
    if (variant?.baseTypeId === 'number' && typeof value === 'number') return variant.link(value);
    return undefined;
  }
}
