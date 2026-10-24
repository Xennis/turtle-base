import type { AnyFieldType, Json } from './base-field-type.ts';

/** How a field's stored values follow a change of its base type, see FIELD_TYPES.md. */
export type ConversionMode =
  /** Values stay as they are and the new type reads them tolerantly. */
  | 'lazy'
  /**
   * Values are rewritten - for types storing ids (select options, related
   * pages), which another type can't tell apart from text.
   */
  | 'rewrite'
  /** Not offered. */
  | 'none';

export function conversionMode(from: AnyFieldType, to: AnyFieldType): ConversionMode {
  if (from.id === to.id) return 'lazy';
  if (from.kind === 'unsupported' || to.kind === 'unsupported') return 'none';
  // Its values are attachments, not properties another type could read.
  if (from.kind === 'files' || to.kind === 'files') return 'none';
  const fromSelect = from.kind === 'select' || from.kind === 'multiSelect';
  const toSelect = to.kind === 'select' || to.kind === 'multiSelect';
  if (fromSelect && toSelect) return 'lazy';
  if (to.kind === 'relation') return 'none';
  if (from.kind === 'relation') return to.kind === 'text' ? 'rewrite' : 'none';
  if (fromSelect) return 'rewrite';
  return 'lazy';
}

/**
 * A planned type change of a field (see FieldsRepository.planTypeChange) -
 * what it does to the values, before anything is written.
 */
export interface TypeChangePlan {
  readonly fieldId: string;
  readonly mode: ConversionMode;

  /** The field's new `type` and `config` columns. */
  readonly type: string;
  readonly config: string | null;

  /** Entries with a value for the field. */
  readonly valueCount: number;

  /** Values that won't fit the new type, flagged as invalid afterwards. */
  readonly invalidCount: number;

  /** The first few of those, as currently displayed. */
  readonly invalidSamples: readonly string[];

  /** New values by page id, for the `rewrite` mode. */
  readonly rewrites: ReadonlyMap<string, Json>;
}
