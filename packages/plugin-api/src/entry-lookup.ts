/**
 * Finds entries in an external source, e.g. books on Open Library. The app
 * shows the search dialog and turns the picked {@link EntryDraft} into an
 * entry.
 */
export interface EntryLookup {
  /** The toolbar button, e.g. `Add book`. */
  readonly actionLabel: string;

  /** Placeholder of the search field, e.g. `Title, author or ISBN`. */
  readonly searchHint: string;

  /**
   * A field key whose value identifies an entry: picking a result with the
   * same value opens the existing entry instead of adding a copy.
   */
  readonly uniqueFieldKey?: string;

  /**
   * Rejects with a {@link LookupError} when the source can't be reached or
   * answers with an error.
   */
  search(query: string, context: LookupContext): Promise<readonly EntryDraft[]>;
}

/** What the app hands a lookup for one search. */
export interface LookupContext {
  /**
   * The only way a lookup reaches the network. The app's runs outside the
   * web view (no CORS limits) and lets it decide later what a plugin may
   * reach.
   */
  readonly fetch: typeof fetch;
}

/**
 * A field value in the JSON shape of the field's base type: a string for
 * text, a number for number, an ISO-8601 string for date and an option key
 * for select.
 */
export type EntryDraftValue = string | number;

/**
 * A search result and the entry it becomes when picked. Plain data (URLs as
 * strings), so it could cross a worker boundary later.
 */
export interface EntryDraft {
  readonly title: string;

  /** Only shown in the result list, e.g. `Frank Herbert · 1965`. */
  readonly subtitle?: string;

  /** Only shown in the result list. */
  readonly thumbnail?: string;

  /**
   * By field key. The app drops values whose field is gone or doesn't accept
   * them anymore.
   */
  readonly values?: Readonly<Record<string, EntryDraftValue>>;

  /** URLs by field key - the app downloads them into a files field. */
  readonly files?: Readonly<Record<string, readonly string[]>>;
}

/** Its `message` is shown to the user, e.g. `Open Library didn't respond`. */
export class LookupError extends Error {
  override readonly name = 'LookupError';
}
