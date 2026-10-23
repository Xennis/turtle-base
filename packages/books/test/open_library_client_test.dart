import 'dart:convert';

import 'package:books/books.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:turtle_plugin/turtle_plugin.dart';

/// Shaped like real answers of https://openlibrary.org/search.json.
const _duneWork = {
  'key': '/works/OL893414W',
  'title': 'Dune',
  'author_name': ['Frank Herbert'],
  'first_publish_year': 1965,
  'number_of_pages_median': 608,
  'cover_i': 11481354,
  'editions': {
    'numFound': 1,
    'docs': [
      {
        'title': 'Der Wüstenplanet',
        'cover_i': 15247677,
        'isbn': ['3453317173', '9783453317178'],
      },
    ],
  },
};

void main() {
  late Uri requested;

  OpenLibraryClient clientAnswering(Object? body, {int status = 200}) {
    return OpenLibraryClient(
      client: MockClient((request) async {
        requested = request.url;
        expect(request.headers['User-Agent'], OpenLibraryClient.userAgent);
        return http.Response.bytes(utf8.encode(jsonEncode(body)), status);
      }),
    );
  }

  test('searches an ISBN by its normalized form', () async {
    final client = clientAnswering({
      'docs': [_duneWork],
    });

    final books = await client.search('978-3-453-31717-8');

    expect(requested.queryParameters['q'], 'isbn:9783453317178');
    final book = books.single;
    expect(book.title, 'Der Wüstenplanet');
    expect(book.authors, ['Frank Herbert']);
    expect(book.firstPublishYear, 1965);
    expect(book.pages, 608);
    expect(book.isbn, '9783453317178');
    expect(book.workUrl, Uri.parse('https://openlibrary.org/works/OL893414W'));
    expect(book.coverUrl('L'), Uri.parse('https://covers.openlibrary.org/b/id/15247677-L.jpg'));
  });

  test('searches anything else as free text', () async {
    final client = clientAnswering({'docs': <Object>[]});

    expect(await client.search(' dune herbert '), isEmpty);
    expect(requested.queryParameters['q'], 'dune herbert');
    expect(requested.queryParameters['fields'], contains('editions.isbn'));
  });

  test('falls back to the work without a matching edition', () async {
    final client = clientAnswering({
      'docs': [
        {'key': '/works/OL1W', 'title': 'Untitled work', 'cover_i': 7},
        {'title': 'No key - skipped'},
      ],
    });

    final book = (await client.search('untitled')).single;

    expect(book.title, 'Untitled work');
    expect(book.authors, isEmpty);
    expect(book.isbn, isNull);
    expect(book.coverUrl('M'), Uri.parse('https://covers.openlibrary.org/b/id/7-M.jpg'));
  });

  test('prefers a valid ISBN-13 of the edition', () async {
    final client = clientAnswering({
      'docs': [
        {
          'key': '/works/OL1W',
          'title': 'Book',
          'editions': {
            'docs': [
              {
                'isbn': ['0804429571', '080442957X', '9783453317178'],
              },
            ],
          },
        },
      ],
    });

    expect((await client.search('book')).single.isbn, '9783453317178');
  });

  test('throws a LookupException on an error response', () async {
    final client = clientAnswering('Service unavailable', status: 503);

    await expectLater(client.search('dune'), throwsA(isA<LookupException>()));
  });

  test('throws a LookupException when unreachable', () async {
    final client = OpenLibraryClient(client: MockClient((_) async => throw http.ClientException('offline')));

    await expectLater(client.search('dune'), throwsA(isA<LookupException>()));
  });
}
