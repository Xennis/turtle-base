/// Finds entries in an external source, e.g. books on Open Library. The
/// app shows the search dialog and turns the picked [EntryDraft] into an
/// entry.
abstract interface class EntryLookup {
  /// The toolbar button, e.g. `Add book`.
  String get actionLabel;

  /// Placeholder of the search field, e.g. `Title, author or ISBN`.
  String get searchHint;

  /// A field key whose value identifies an entry: picking a result with
  /// the same value opens the existing entry instead of adding a copy.
  String? get uniqueFieldKey;

  /// Throws [LookupException] when the source can't be reached or
  /// answers with an error.
  Future<List<EntryDraft>> search(String query);
}

/// A search result and the entry it becomes when picked.
class EntryDraft {
  const EntryDraft({required this.title, this.subtitle, this.thumbnail, this.values = const {}, this.files = const {}});

  final String title;

  /// Only shown in the result list, e.g. `Frank Herbert · 1965`.
  final String? subtitle;

  /// Only shown in the result list.
  final Uri? thumbnail;

  /// By field key, in the JSON shape of the field's base type: a
  /// `String` for text, a `num` for number, an ISO-8601 `String` for
  /// date and an option key for select. The app drops values whose field
  /// is gone or doesn't accept them anymore.
  final Map<String, Object?> values;

  /// By field key - the app downloads them into a files field.
  final Map<String, List<Uri>> files;
}

class LookupException implements Exception {
  const LookupException(this.message);

  /// Shown to the user, e.g. `Open Library didn't respond`.
  final String message;

  @override
  String toString() => 'LookupException: $message';
}
