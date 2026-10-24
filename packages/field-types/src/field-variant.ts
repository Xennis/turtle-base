/**
 * The JSON shape a field value is stored in, in `pages.properties` - or
 * `external` for a value kept elsewhere (e.g. a files field's attachments).
 */
export type StorageKind = 'string' | 'number' | 'boolean' | 'stringList' | 'object' | 'external';

/**
 * How a variant's values are typed in, so the app can pick a fitting
 * keyboard without this package depending on the UI.
 */
export type InputHint = 'text' | 'number' | 'url' | 'email' | 'phone';

interface VariantBase<V> {
  /**
   * Stored in the field's config. Namespaced for packages (e.g.
   * `books.isbn`), plain for the app's own (e.g. `url`).
   */
  readonly id: string;
  readonly label: string;
  readonly inputHint?: InputHint;

  /**
   * Merged into the base type's config when the variant is picked, e.g.
   * `{"min": 0}` for a number variant that is never negative.
   */
  readonly configPreset?: Readonly<Record<string, unknown>>;

  /** An error message, or undefined if `value` is valid. */
  validate(value: V): string | undefined;

  /** Applied before validating and storing user input. */
  normalize(value: V): V;

  /** Display text, or undefined to fall back to the base type's. */
  format(value: V): string | undefined;

  /**
   * Where tapping the value leads, e.g. a mailto: link. Undefined when it
   * isn't a link.
   */
  link(value: V): URL | undefined;
}

export interface TextVariant extends VariantBase<string> {
  /** The id of the base type this variant builds on. */
  readonly baseTypeId: 'text';
}

export interface NumberVariant extends VariantBase<number> {
  readonly baseTypeId: 'number';
}

/**
 * Semantics on top of one of the app's base field types - e.g. an ISBN is a
 * text field that validates, normalizes and formats its value. Stored like
 * its base type, so a device that doesn't know the variant still reads the
 * field as its plain base type.
 *
 * Only text and number variants exist: a variant can't bring its own
 * storage, see FIELD_TYPES.md.
 */
export type FieldVariant = TextVariant | NumberVariant;

export interface VariantOptions<V> {
  readonly id: string;
  readonly label: string;
  readonly inputHint?: InputHint;
  readonly configPreset?: Readonly<Record<string, unknown>>;
  readonly validate?: (value: V) => string | undefined;
  readonly normalize?: (value: V) => V;
  readonly format?: (value: V) => string | undefined;
  readonly link?: (value: V) => URL | undefined;
}

export function textVariant(options: VariantOptions<string>): TextVariant {
  return { baseTypeId: 'text', ...variantBase(options) };
}

/** A text variant whose values must fully match `pattern`. */
export function patternTextVariant(
  options: Omit<VariantOptions<string>, 'validate' | 'format'> & {
    readonly pattern: RegExp;
    readonly message: string;
  },
): TextVariant {
  const { pattern, message, ...rest } = options;
  return textVariant({ ...rest, validate: (value) => (matchesFully(pattern, value) ? undefined : message) });
}

export function numberVariant(options: Omit<VariantOptions<number>, 'inputHint'>): NumberVariant {
  return { baseTypeId: 'number', ...variantBase({ ...options, inputHint: 'number' }) };
}

function variantBase<V>(options: VariantOptions<V>): VariantBase<V> {
  const { validate, normalize, format, link, ...rest } = options;
  return {
    ...rest,
    validate: (value) => validate?.(value),
    normalize: (value) => (normalize === undefined ? value : normalize(value)),
    format: (value) => format?.(value),
    link: (value) => link?.(value),
  };
}

/** Whether `pattern` matches all of `value`, not just a part of it. */
export function matchesFully(pattern: RegExp, value: string): boolean {
  const flags = pattern.flags.replaceAll(/[gy]/g, '');
  return new RegExp(`^(?:${pattern.source})$`, flags).test(value);
}
