import 'dart:async';
import 'dart:convert';

import 'package:books/src/isbn.dart';
import 'package:http/http.dart' as http;
import 'package:turtle_plugin/turtle_plugin.dart';

/// A book as Open Library's search finds it: the work, plus the edition
/// that matches the query best (e.g. the German one for "Der
/// Wüstenplanet", or exactly the one with a searched ISBN).
class OpenLibraryBook {
  const OpenLibraryBook({
    required this.workKey,
    required this.title,
    this.authors = const [],
    this.firstPublishYear,
    this.pages,
    this.isbn,
    this.coverId,
  });

  /// E.g. `/works/OL893414W`.
  final String workKey;

  /// The edition's title, else the work's.
  final String title;
  final List<String> authors;
  final int? firstPublishYear;

  /// The median over all editions - Open Library's search has no page
  /// count per edition.
  final int? pages;

  /// The edition's, normalized - null if it has no valid one.
  final String? isbn;
  final int? coverId;

  Uri get workUrl => Uri.https('openlibrary.org', workKey);

  /// [size] is `S`, `M` or `L`.
  Uri? coverUrl(String size) =>
      coverId == null ? null : Uri.https('covers.openlibrary.org', '/b/id/$coverId-$size.jpg');
}

/// Searches books on Open Library by title, author or ISBN. One endpoint
/// for all of them: https://openlibrary.org/dev/docs/api/search
class OpenLibraryClient {
  OpenLibraryClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Open Library asks clients to identify themselves and throttles
  /// anonymous ones harder.
  static const userAgent = 'TurtleBase (https://github.com/Xennis/turtle-base)';
  static const _timeout = Duration(seconds: 15);
  static const _fields = [
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

  /// Throws [LookupException] when Open Library can't be reached or
  /// answers with an error.
  Future<List<OpenLibraryBook>> search(String query, {int limit = 10}) async {
    final isbn = normalizeIsbn(query.trim());
    final searchedIsbn = isValidIsbn(isbn) ? isbn : null;
    final uri = Uri.https('openlibrary.org', '/search.json', {
      'q': searchedIsbn != null ? 'isbn:$searchedIsbn' : query.trim(),
      'fields': _fields.join(','),
      'limit': '$limit',
    });

    final http.Response response;
    try {
      response = await _client.get(uri, headers: {'User-Agent': userAgent}).timeout(_timeout);
    } on TimeoutException {
      throw const LookupException("Open Library didn't respond");
    } on http.ClientException {
      throw const LookupException("Couldn't reach Open Library");
    }
    if (response.statusCode != 200) {
      throw LookupException('Open Library answered with an error (${response.statusCode})');
    }

    final json = jsonDecode(utf8.decode(response.bodyBytes));
    final docs = json is Map ? json['docs'] : null;
    if (docs is! List) throw const LookupException('Open Library answered with an unknown format');
    return [for (final doc in docs.whereType<Map<String, Object?>>()) ?_bookOf(doc, searchedIsbn: searchedIsbn)];
  }

  static OpenLibraryBook? _bookOf(Map<String, Object?> doc, {String? searchedIsbn}) {
    final key = doc['key'];
    final workTitle = doc['title'];
    if (key is! String || workTitle is! String) return null;
    final edition = _bestEdition(doc);
    final editionTitle = edition?['title'];
    final editionCover = edition?['cover_i'];
    final workCover = doc['cover_i'];
    return OpenLibraryBook(
      workKey: key,
      title: editionTitle is String && editionTitle.isNotEmpty ? editionTitle : workTitle,
      authors: [...?(doc['author_name'] as List?)?.whereType<String>()],
      firstPublishYear: _intOf(doc['first_publish_year']),
      pages: _intOf(doc['number_of_pages_median']),
      isbn: _isbnOf(edition?['isbn'], searchedIsbn: searchedIsbn),
      coverId: _intOf(editionCover) ?? _intOf(workCover),
    );
  }

  static Map<String, Object?>? _bestEdition(Map<String, Object?> doc) {
    final editions = doc['editions'];
    final docs = editions is Map ? editions['docs'] : null;
    return docs is List ? docs.whereType<Map<String, Object?>>().firstOrNull : null;
  }

  /// The searched ISBN if the edition has it, else its first valid
  /// ISBN-13, else its first valid ISBN-10.
  static String? _isbnOf(Object? raw, {String? searchedIsbn}) {
    final isbns = [
      for (final value in raw is List ? raw.whereType<String>() : const <String>[])
        if (normalizeIsbn(value) case final isbn when isValidIsbn(isbn)) isbn,
    ];
    if (searchedIsbn != null && isbns.contains(searchedIsbn)) return searchedIsbn;
    return isbns.where((isbn) => isbn.length == 13).firstOrNull ?? isbns.firstOrNull;
  }

  static int? _intOf(Object? raw) => raw is num ? raw.toInt() : null;
}
