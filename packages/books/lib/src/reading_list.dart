import 'package:books/src/isbn.dart';
import 'package:books/src/open_library_client.dart';
import 'package:turtle_plugin/turtle_plugin.dart';

/// The books to read, being read, read or abandoned - Goodreads' shelves
/// as the options of one select.
final readingList = CollectionTemplate(
  key: 'reading_list',
  name: 'Reading list',
  icon: '📚',
  titleLabel: 'Title',
  fields: [
    // First, so tiles show it below the title.
    const SelectFieldTemplate(
      'status',
      'Status',
      options: [
        OptionTemplate('want', 'Want to read', OptionColor.blue),
        OptionTemplate('reading', 'Reading', OptionColor.yellow),
        OptionTemplate('read', 'Read', OptionColor.green),
        OptionTemplate('abandoned', 'Abandoned', OptionColor.gray),
      ],
    ),
    const TextFieldTemplate('author', 'Author'),
    const NumberFieldTemplate('year', 'Year'),
    TextFieldTemplate('isbn', 'ISBN', variant: isbnVariant),
    // The first files field, so tiles show it as their cover.
    const FilesFieldTemplate('cover', 'Cover', accept: ['image/*'], maxFiles: 1),
    const NumberFieldTemplate('pages', 'Pages', min: 0),
    const DateFieldTemplate('started', 'Started'),
    const DateFieldTemplate('finished', 'Finished'),
    const NumberFieldTemplate('rating', 'Rating', min: 1, max: 5),
    TextFieldTemplate('openlibrary', 'Open Library', variant: urlVariant),
  ],
  lookup: OpenLibraryLookup(OpenLibraryClient()),
);

/// Adds books found on Open Library to the [readingList].
class OpenLibraryLookup implements EntryLookup {
  OpenLibraryLookup(this._client);

  final OpenLibraryClient _client;

  @override
  String get actionLabel => 'Add book';

  @override
  String get searchHint => 'Title, author or ISBN';

  /// The work, not the ISBN: also catches books without one, and a
  /// second edition of a book already listed opens that entry.
  @override
  String get uniqueFieldKey => 'openlibrary';

  @override
  Future<List<EntryDraft>> search(String query) async {
    return [for (final book in await _client.search(query)) draftOf(book)];
  }

  static EntryDraft draftOf(OpenLibraryBook book) {
    final cover = book.coverUrl('L');
    return EntryDraft(
      title: book.title,
      subtitle: [if (book.authors.isNotEmpty) book.authors.join(', '), ?book.firstPublishYear?.toString()].join(' · '),
      thumbnail: book.coverUrl('M'),
      values: {
        'status': 'want',
        if (book.authors.isNotEmpty) 'author': book.authors.join(', '),
        'year': ?book.firstPublishYear,
        'pages': ?book.pages,
        'isbn': ?book.isbn,
        'openlibrary': book.workUrl.toString(),
      },
      files: {
        if (cover != null) 'cover': [cover],
      },
    );
  }
}
