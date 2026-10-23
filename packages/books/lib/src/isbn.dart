import 'package:turtle_plugin/turtle_plugin.dart';

/// An ISBN-10 or ISBN-13, stored without separators (e.g.
/// `9783453317178`) and shown with its prefix split off.
final isbnVariant = TextVariant(
  id: 'books.isbn',
  label: 'ISBN',
  normalize: normalizeIsbn,
  validate: (value) => isValidIsbn(value) ? null : 'Enter a valid ISBN-10 or ISBN-13',
  format: formatIsbn,
  link: (value) => Uri.https('openlibrary.org', '/isbn/$value'),
);

String normalizeIsbn(String value) => value.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

/// Checks the length, characters and check digit of a normalized ISBN.
bool isValidIsbn(String value) {
  if (RegExp(r'^\d{9}[\dX]$').hasMatch(value)) {
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      final digit = value[i] == 'X' ? 10 : int.parse(value[i]);
      sum += digit * (10 - i);
    }
    return sum % 11 == 0;
  }
  if (RegExp(r'^97[89]\d{10}$').hasMatch(value)) {
    var sum = 0;
    for (var i = 0; i < 13; i++) {
      sum += int.parse(value[i]) * (i.isEven ? 1 : 3);
    }
    return sum % 10 == 0;
  }
  return false;
}

/// Splits off the 978/979 prefix of an ISBN-13. Grouping the rest
/// correctly needs the ISBN agency's range table, which isn't bundled.
String formatIsbn(String value) => value.length == 13 ? '${value.substring(0, 3)}-${value.substring(3)}' : value;
