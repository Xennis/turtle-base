import { commonVariants, urlVariant, type FieldVariant } from '@turtle-base/plugin-api';

import type { Field } from '../../../core/database/schema.ts';
import { baseFieldTypes, textFieldType, unsupportedFieldType, type AnyFieldType } from './base-field-type.ts';
import { decodeFieldConfig, fieldVariantKey, ResolvedField } from './resolved-field.ts';

/** One entry of the type picker: a base type, optionally with a variant. */
export class FieldTypeChoice {
  readonly base: AnyFieldType;
  readonly variant: FieldVariant | undefined;

  constructor(base: AnyFieldType, variant?: FieldVariant) {
    this.base = base;
    this.variant = variant;
  }

  /** Unique across all choices, e.g. `text` or `url`. */
  get key(): string {
    return this.variant?.id ?? this.base.id;
  }

  get label(): string {
    return this.variant?.label ?? this.base.label;
  }
}

/** All base types and the variants registered by the app and packages. */
export class FieldTypeRegistry {
  readonly #variants: ReadonlyMap<string, FieldVariant>;

  constructor(variants: readonly FieldVariant[] = []) {
    this.#variants = new Map([...commonVariants, ...variants].map((variant) => [variant.id, variant]));
  }

  /** Each base type followed by its variants, so related types sit together in the picker. */
  get choices(): FieldTypeChoice[] {
    return baseFieldTypes.flatMap((base) => [
      new FieldTypeChoice(base),
      ...[...this.#variants.values()]
        .filter((variant) => variant.baseTypeId === base.id)
        .map((variant) => new FieldTypeChoice(base, variant)),
    ]);
  }

  choiceFor(field: ResolvedField): FieldTypeChoice {
    return new FieldTypeChoice(field.base, field.variant);
  }

  variantById(id: string | undefined): FieldVariant | undefined {
    return id === undefined ? undefined : this.#variants.get(id);
  }

  baseById(id: string): AnyFieldType {
    return baseFieldTypes.find((base) => base.id === id) ?? unsupportedFieldType(id);
  }

  resolve(row: Field): ResolvedField {
    const json = decodeFieldConfig(row.config);
    // A base type of its own before url became a variant - still found in data
    // from older app versions, so mapped on every read.
    const isLegacyUrl = row.type === 'url';
    const base = isLegacyUrl ? textFieldType : this.baseById(row.type);
    const storedVariant = json[fieldVariantKey];
    const variant = this.variantById(
      isLegacyUrl ? urlVariant.id : typeof storedVariant === 'string' ? storedVariant : undefined,
    );
    return new ResolvedField(
      row,
      base,
      // A variant registered for another base type than the field has (e.g. after its type changed on a
      // device without this variant) is ignored rather than misapplied.
      variant?.baseTypeId === base.id ? variant : undefined,
      base.decodeConfig(json),
    );
  }
}
