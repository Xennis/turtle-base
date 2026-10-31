import { LookupError, type PluginFetch, type PluginResponse } from '@turtle-base/plugin-api';
import * as v from 'valibot';

import { isValidIsbn, normalizeIsbn } from './isbn.ts';

/**
 * A book as Open Library's search finds it: the work, plus the edition that
 * matches the query best (e.g. the German one for "Der Wüstenplanet", or
 * exactly the one with a searched ISBN).
 */
export interface OpenLibraryBook {
  /** E.g. `/works/OL893414W`. */
  readonly workKey: string;

  /** The edition's title, else the work's. */
  readonly title: string;
  readonly authors: readonly string[];
  readonly firstPublishYear?: number | undefined;

  /**
   * The median over all editions - Open Library's search has no page count
   * per edition.
   */
  readonly pages?: number | undefined;

  /** The edition's, normalized - missing if it has no valid one. */
  readonly isbn?: string | undefined;
  readonly coverId?: number | undefined;
}

export function workUrlOf(book: OpenLibraryBook): string {
  return new URL(book.workKey, 'https://openlibrary.org').href;
}

/** `size` is `S`, `M` or `L`. */
export function coverUrlOf(book: OpenLibraryBook, size: 'S' | 'M' | 'L'): string | undefined {
  return book.coverId === undefined ? undefined : `https://covers.openlibrary.org/b/id/${book.coverId}-${size}.jpg`;
}

/**
 * Open Library asks clients to identify themselves and throttles anonymous
 * ones harder.
 */
export const openLibraryUserAgent = 'TurtleBase (https://github.com/Xennis/turtle-base)';

const timeoutMs = 15_000;
const fields = [
  'key',
  'title',
  'author_name',
  'first_publish_year',
  'number_of_pages_median',
  'cover_i',
  'editions',
  'editions.title',
  'editions.isbn',
  'editions.cover_i',
];

/**
 * Searches books on Open Library by title, author or ISBN. One endpoint for
 * all of them: https://openlibrary.org/dev/docs/api/search
 */
export class OpenLibraryClient {
  readonly #fetch: PluginFetch;

  constructor(fetchFn: PluginFetch) {
    this.#fetch = fetchFn;
  }

  /**
   * Rejects with a {@link LookupError} when Open Library can't be reached or
   * answers with an error.
   */
  async search(query: string, limit = 10): Promise<OpenLibraryBook[]> {
    const isbn = normalizeIsbn(query.trim());
    const searchedIsbn = isValidIsbn(isbn) ? isbn : undefined;
    const url = new URL('https://openlibrary.org/search.json');
    url.search = new URLSearchParams({
      q: searchedIsbn === undefined ? query.trim() : `isbn:${searchedIsbn}`,
      fields: fields.join(','),
      limit: String(limit),
    }).toString();

    let response: PluginResponse;
    try {
      response = await this.#fetch(url.href, {
        headers: { 'User-Agent': openLibraryUserAgent },
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (error) {
      if (error instanceof Error && error.name === 'TimeoutError') {
        throw new LookupError("Open Library didn't respond", { cause: error });
      }
      throw new LookupError("Couldn't reach Open Library", { cause: error });
    }
    if (response.status !== 200) {
      throw new LookupError(`Open Library answered with an error (${response.status})`);
    }

    const answer = v.safeParse(answerSchema, await response.json().catch(() => undefined));
    if (!answer.success) throw new LookupError('Open Library answered with an unknown format');
    return answer.output.docs.flatMap((doc) => {
      const parsed = v.safeParse(docSchema, doc);
      return parsed.success ? [bookOf(parsed.output, searchedIsbn)] : [];
    });
  }
}

const answerSchema = v.object({ docs: v.array(v.unknown()) });

/** Only the strings of `items` - other items are dropped, not fatal. */
const strings = v.fallback(
  v.pipe(
    v.array(v.unknown()),
    v.transform((items) => items.filter((item) => typeof item === 'string')),
  ),
  [],
);
const optionalInt = v.fallback(v.optional(v.pipe(v.number(), v.transform(Math.trunc))), undefined);
const editionSchema = v.object({
  title: v.fallback(v.optional(v.string()), undefined),
  cover_i: optionalInt,
  isbn: strings,
});
const docSchema = v.object({
  key: v.string(),
  title: v.string(),
  author_name: strings,
  first_publish_year: optionalInt,
  number_of_pages_median: optionalInt,
  cover_i: optionalInt,
  editions: v.fallback(v.optional(v.object({ docs: v.array(v.unknown()) })), undefined),
});

function bookOf(doc: v.InferOutput<typeof docSchema>, searchedIsbn: string | undefined): OpenLibraryBook {
  const edition = bestEdition(doc);
  const title = edition?.title;
  return {
    workKey: doc.key,
    title: title !== undefined && title.length > 0 ? title : doc.title,
    authors: doc.author_name,
    firstPublishYear: doc.first_publish_year,
    pages: doc.number_of_pages_median,
    isbn: isbnOf(edition?.isbn ?? [], searchedIsbn),
    coverId: edition?.cover_i ?? doc.cover_i,
  };
}

function bestEdition(doc: v.InferOutput<typeof docSchema>): v.InferOutput<typeof editionSchema> | undefined {
  const first = doc.editions?.docs[0];
  const parsed = v.safeParse(editionSchema, first);
  return parsed.success ? parsed.output : undefined;
}

/**
 * The searched ISBN if the edition has it, else its first valid ISBN-13,
 * else its first valid ISBN-10.
 */
function isbnOf(raw: readonly string[], searchedIsbn: string | undefined): string | undefined {
  const isbns = raw.map(normalizeIsbn).filter(isValidIsbn);
  if (searchedIsbn !== undefined && isbns.includes(searchedIsbn)) return searchedIsbn;
  return isbns.find((isbn) => isbn.length === 13) ?? isbns[0];
}
