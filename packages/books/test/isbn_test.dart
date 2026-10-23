import 'package:books/books.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes separators and a lowercase check digit', () {
    expect(isbnVariant.normalize('978-3-453-31717-8 '), '9783453317178');
    expect(isbnVariant.normalize('0-8044-2957-x'), '080442957X');
  });

  test('validates the check digit of ISBN-10 and ISBN-13', () {
    expect(isbnVariant.validate('9783453317178'), isNull);
    expect(isbnVariant.validate('080442957X'), isNull);
    expect(isbnVariant.validate('9783453317179'), isNotNull);
    expect(isbnVariant.validate('0804429571'), isNotNull);
    expect(isbnVariant.validate('12345'), isNotNull);
  });

  test('formats an ISBN-13 with its prefix split off', () {
    expect(isbnVariant.format('9783453317178'), '978-3453317178');
    expect(isbnVariant.format('080442957X'), '080442957X');
  });

  test('links to Open Library', () {
    expect(isbnVariant.link('9783453317178'), Uri.parse('https://openlibrary.org/isbn/9783453317178'));
  });
}
