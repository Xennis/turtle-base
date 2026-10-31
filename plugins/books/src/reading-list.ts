import {
  urlVariant,
  type CollectionTemplate,
  type EntryDraft,
  type EntryDraftValue,
  type EntryLookup,
} from '@turtle-base/plugin-api';

import { isbnVariant } from './isbn.ts';
import { coverUrlOf, OpenLibraryClient, workUrlOf, type OpenLibraryBook } from './open-library-client.ts';

/** Adds books found on Open Library to the {@link readingList}. */
export const openLibraryLookup: EntryLookup = {
  actionLabel: 'Add book',
  searchHint: 'Title, author or ISBN',

  /**
   * The work, not the ISBN: also catches books without one, and a second
   * edition of a book already listed opens that entry.
   */
  uniqueFieldKey: 'openlibrary',

  async search(query, { fetch }) {
    const books = await new OpenLibraryClient(fetch).search(query);
    return books.map(draftOf);
  },
};

export function draftOf(book: OpenLibraryBook): EntryDraft {
  const authors = book.authors.join(', ');
  const thumbnail = coverUrlOf(book, 'M');
  const cover = coverUrlOf(book, 'L');
  const values: Record<string, EntryDraftValue> = { status: 'want' };
  if (authors.length > 0) values['author'] = authors;
  if (book.firstPublishYear !== undefined) values['year'] = book.firstPublishYear;
  if (book.pages !== undefined) values['pages'] = book.pages;
  if (book.isbn !== undefined) values['isbn'] = book.isbn;
  values['openlibrary'] = workUrlOf(book);
  return {
    title: book.title,
    subtitle: [authors, book.firstPublishYear?.toString() ?? ''].filter((part) => part.length > 0).join(' · '),
    ...(thumbnail === undefined ? {} : { thumbnail }),
    values,
    files: cover === undefined ? {} : { cover: [cover] },
  };
}

/**
 * The books to read, being read, read or abandoned - Goodreads' shelves as
 * the options of one select.
 */
export const readingList: CollectionTemplate = {
  key: 'reading_list',
  name: 'Reading list',
  icon: '📚',
  titleLabel: 'Title',
  fields: [
    // First, so tiles show it below the title.
    {
      kind: 'select',
      key: 'status',
      name: 'Status',
      options: [
        { key: 'want', name: 'Want to read', color: 'blue' },
        { key: 'reading', name: 'Reading', color: 'yellow' },
        { key: 'read', name: 'Read', color: 'green' },
        { key: 'abandoned', name: 'Abandoned', color: 'gray' },
      ],
    },
    { kind: 'text', key: 'author', name: 'Author' },
    { kind: 'number', key: 'year', name: 'Year' },
    { kind: 'text', key: 'isbn', name: 'ISBN', variant: isbnVariant },
    // The first files field, so tiles show it as their cover.
    { kind: 'files', key: 'cover', name: 'Cover', accept: ['image/*'], maxFiles: 1 },
    { kind: 'number', key: 'pages', name: 'Pages', min: 0 },
    { kind: 'date', key: 'started', name: 'Started' },
    { kind: 'date', key: 'finished', name: 'Finished' },
    { kind: 'number', key: 'rating', name: 'Rating', min: 1, max: 5 },
    { kind: 'text', key: 'openlibrary', name: 'Open Library', variant: urlVariant },
  ],
  lookup: openLibraryLookup,
};
