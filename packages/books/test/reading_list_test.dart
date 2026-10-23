import 'package:books/books.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_plugin/turtle_plugin.dart';

void main() {
  test('maps a book to a draft for the reading list', () {
    const book = OpenLibraryBook(
      workKey: '/works/OL893414W',
      title: 'Der Wüstenplanet',
      authors: ['Frank Herbert'],
      firstPublishYear: 1965,
      pages: 608,
      isbn: '9783453317178',
      coverId: 15247677,
    );

    final draft = OpenLibraryLookup.draftOf(book);

    expect(draft.title, 'Der Wüstenplanet');
    expect(draft.subtitle, 'Frank Herbert · 1965');
    expect(draft.thumbnail, Uri.parse('https://covers.openlibrary.org/b/id/15247677-M.jpg'));
    expect(draft.values, {
      'status': 'want',
      'author': 'Frank Herbert',
      'year': 1965,
      'pages': 608,
      'isbn': '9783453317178',
      'openlibrary': 'https://openlibrary.org/works/OL893414W',
    });
    expect(draft.files, {
      'cover': [Uri.parse('https://covers.openlibrary.org/b/id/15247677-L.jpg')],
    });
  });

  test('leaves out what Open Library doesn\'t know', () {
    final draft = OpenLibraryLookup.draftOf(const OpenLibraryBook(workKey: '/works/OL1W', title: 'Unknown'));

    expect(draft.subtitle, '');
    expect(draft.thumbnail, isNull);
    expect(draft.values, {'status': 'want', 'openlibrary': 'https://openlibrary.org/works/OL1W'});
    expect(draft.files, isEmpty);
  });

  test('every draft value has a field in the reading list', () {
    final keys = {for (final field in readingList.fields) field.key};
    final draft = OpenLibraryLookup.draftOf(
      const OpenLibraryBook(
        workKey: '/works/OL1W',
        title: 'T',
        authors: ['A'],
        firstPublishYear: 1,
        pages: 1,
        isbn: '9783453317178',
        coverId: 1,
      ),
    );

    expect(keys, containsAll({...draft.values.keys, ...draft.files.keys, readingList.lookup!.uniqueFieldKey}));
    final status = readingList.fields.whereType<SelectFieldTemplate>().single;
    expect(status.options.map((o) => o.key), contains(draft.values['status']));
  });
}
