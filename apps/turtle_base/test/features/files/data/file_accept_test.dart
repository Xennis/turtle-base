import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/features/files/data/file_accept.dart';

void main() {
  bool accepts(FileAccept accept, String mimeType, String fileName) =>
      accept.accepts(mimeType: mimeType, fileName: fileName);

  test('any accepts everything', () {
    expect(accepts(FileAccept.any, 'application/zip', 'a.zip'), isTrue);
  });

  test('a wildcard matches the whole MIME family', () {
    expect(accepts(FileAccept.images, 'image/jpeg', 'a.jpg'), isTrue);
    expect(accepts(FileAccept.images, 'application/pdf', 'a.jpg'), isFalse);
  });

  test('an exact MIME type and an extension each match', () {
    final xml = FileAccept.parse('application/xml, .XML');
    expect(accepts(xml, 'application/xml', 'a.txt'), isTrue);
    expect(accepts(xml, 'text/plain', 'feed.xml'), isTrue);
    expect(accepts(xml, 'text/plain', 'feed.txt'), isFalse);
  });

  test('parse() trims, lowercases and drops empty parts', () {
    expect(FileAccept.parse(' Image/* ,, .PDF ').patterns, ['image/*', '.pdf']);
  });

  test('dialogExtensions lists extensions, or null when it can\'t', () {
    expect(FileAccept.any.dialogExtensions, isNull);
    expect(FileAccept.pdf.dialogExtensions, ['pdf']);
    expect(FileAccept.images.dialogExtensions, contains('png'));
    expect(FileAccept.parse('text/*').dialogExtensions, isNull);
  });

  test('isImagesOnly', () {
    expect(FileAccept.images.isImagesOnly, isTrue);
    expect(FileAccept.parse('image/*, .pdf').isImagesOnly, isFalse);
    expect(FileAccept.any.isImagesOnly, isFalse);
  });
}
