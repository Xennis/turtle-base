import type { FieldVariant } from '@turtle-base/field-types';

import type { CollectionTemplate } from './collection-template.ts';

/**
 * What a plugin contributes to turtle-base. A plugin only describes data and
 * offers pure functions - the app does all the writing, so sync, validation
 * and soft-delete work as for the user's own input.
 *
 * Adding a plugin creates a space holding one collection per entry of
 * `collections`. Its rows get ids derived from `id` (see the README), which
 * is how the app finds them again.
 */
export interface TurtlePlugin {
  /**
   * Short and stable, without a dot, e.g. `books`. The prefix of every id the
   * plugin brings in, so it must never change.
   */
  readonly id: string;

  /** Also the name of the space the plugin creates. */
  readonly name: string;
  readonly description: string;

  /** An emoji, also used for the space. */
  readonly icon?: string;

  /** Ids prefixed with `<id>.`, e.g. `books.isbn`. */
  readonly variants?: readonly FieldVariant[];
  readonly collections?: readonly CollectionTemplate[];
}
