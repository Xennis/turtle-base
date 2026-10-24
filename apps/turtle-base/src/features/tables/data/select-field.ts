import { optionColors, type OptionColor } from '@turtle-base/plugin-api';
import * as v from 'valibot';

/**
 * One choice of a select/multi-select field. Property values reference it by
 * `id`, never by `name`, so renaming or recoloring an option only touches
 * `fields.config`, not every entry using it.
 */
export interface SelectOption {
  readonly id: string;
  readonly name: string;
  readonly color: OptionColor;
}

const optionSchema = v.object({
  id: v.string(),
  name: v.string(),
  // An unknown color (e.g. from a newer app version) falls back to gray.
  color: v.fallback(v.picklist(optionColors), 'gray'),
});

/** Encodes a select/multi-select field's `fields.config` - its options, in display order. */
export function encodeSelectConfig(options: readonly SelectOption[]): string {
  return JSON.stringify({ options: options.map(({ id, name, color }) => ({ id, name, color })) });
}

export function decodeSelectOptions(config: string | null): SelectOption[] {
  if (config === null) return [];
  return decodeSelectOptionsJson(JSON.parse(config));
}

/** Options that don't parse are skipped rather than failing the whole field. */
export function decodeSelectOptionsJson(config: unknown): SelectOption[] {
  const options = v.safeParse(v.object({ options: v.array(v.unknown()) }), config);
  if (!options.success) return [];
  return options.output.options.flatMap((option) => {
    const parsed = v.safeParse(optionSchema, option);
    return parsed.success ? [parsed.output] : [];
  });
}

/**
 * The color a newly created option gets - rotating through the palette, so
 * consecutive options are told apart without picking.
 */
export function nextOptionColor(existing: readonly SelectOption[]): OptionColor {
  return optionColors[existing.length % optionColors.length] ?? 'gray';
}

/**
 * A select property value is a single option id, a multi-select one a JSON
 * array of option ids. Accepts both forms either way, so switching a field
 * between select and multi-select keeps its values.
 */
export function decodeSelectValue(raw: unknown): string[] {
  if (typeof raw === 'string') return raw.length === 0 ? [] : [raw];
  if (Array.isArray(raw)) return raw.filter((item) => typeof item === 'string');
  return [];
}

/** The options `raw` refers to, in the order they're stored. Ids of options deleted since are skipped. */
export function resolveSelectValue(options: readonly SelectOption[], raw: unknown): SelectOption[] {
  const byId = new Map(options.map((option) => [option.id, option]));
  return decodeSelectValue(raw).flatMap((id) => {
    const option = byId.get(id);
    return option === undefined ? [] : [option];
  });
}

/**
 * What to store in `pages.properties` for the option ids `ids`: a single id
 * (or null) for a select field, the list for a multi-select.
 */
export function encodeSelectValue(ids: readonly string[], multiple: boolean): string | readonly string[] | null {
  if (multiple) return ids;
  return ids[0] ?? null;
}
