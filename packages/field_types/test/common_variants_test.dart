import 'package:field_types/field_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('urlVariant', () {
    test('accepts a host with or without scheme', () {
      expect(urlVariant.validate('example.com'), isNull);
      expect(urlVariant.validate('https://example.com/path'), isNull);
      expect(urlVariant.validate('example'), isNotNull);
    });

    test('links to https when the scheme is missing', () {
      expect(urlVariant.link('example.com'), Uri.parse('https://example.com'));
      expect(urlVariant.link('http://example.com'), Uri.parse('http://example.com'));
    });
  });

  test('emailVariant links to mailto', () {
    expect(emailVariant.validate('a@example.com'), isNull);
    expect(emailVariant.validate('a@example'), isNotNull);
    expect(emailVariant.link('a@example.com'), Uri(scheme: 'mailto', path: 'a@example.com'));
  });

  test('phoneVariant links to tel without separators', () {
    expect(phoneVariant.validate('+49 30 1234567'), isNull);
    expect(phoneVariant.validate('call me'), isNotNull);
    expect(phoneVariant.link('+49 (30) 123-4567'), Uri(scheme: 'tel', path: '+49301234567'));
  });
}
