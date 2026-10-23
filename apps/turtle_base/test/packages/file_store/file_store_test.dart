import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:turtle_base/packages/file_store/file_store.dart';
import 'package:turtle_base/packages/file_store/thumbnails.dart';

void main() {
  late Directory tmp;
  late FileStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('file_store_test');
    store = FileStore(p.join(tmp.path, 'files'));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  File sourceFile(String name, List<int> bytes) => File(p.join(tmp.path, name))..writeAsBytesSync(bytes);

  test('import() names the file by its content hash', () async {
    final bytes = 'hello'.codeUnits;

    final stored = await store.import(sourceFile('a.txt', bytes));

    expect(stored.hash, fileHashOf(bytes));
    expect(stored.size, 5);
    expect(stored.mimeType, 'text/plain');
    expect(store.originalIfPresent(stored.hash)!.readAsStringSync(), 'hello');
    expect(store.thumbnailIfPresent(stored.hash), isNull);
  });

  test('import() stores the same content once', () async {
    final first = await store.import(sourceFile('a.txt', [1, 2, 3]));
    final second = await store.import(sourceFile('b.bin', [1, 2, 3]));

    expect(second.hash, first.hash);
    expect(await store.names(), {first.hash});
  });

  test('import() detects the type from the content, not the extension', () async {
    final png = img.encodePng(img.Image(width: 2, height: 2));

    final stored = await store.import(sourceFile('looks-like.xml', png));

    expect(stored.mimeType, 'image/png');
  });

  test('import() writes a thumbnail for an image, with its size', () async {
    final jpg = img.encodeJpg(img.Image(width: 1200, height: 600));

    final stored = await store.import(sourceFile('photo.jpg', jpg));

    expect((stored.width, stored.height), (1200, 600));
    final thumbnail = img.decodeJpg(store.thumbnailIfPresent(stored.hash)!.readAsBytesSync())!;
    expect((thumbnail.width, thumbnail.height), (thumbnailMaxEdge, thumbnailMaxEdge ~/ 2));
    expect(await store.names(), {stored.hash, FileStore.thumbnailNameOf(stored.hash)});
  });

  test('import() skips the thumbnail for content the image package can\'t decode', () async {
    final stored = await store.import(sourceFile('broken.png', [0x89, 0x50, 0x4E, 0x47, 0, 0]));

    expect(stored.mimeType, 'image/png');
    expect(stored.width, isNull);
    expect(store.thumbnailIfPresent(stored.hash), isNull);
  });

  test('put() stores a download that matches its hash', () async {
    final bytes = [7, 8, 9];
    final hash = fileHashOf(bytes);

    final stored = store.onStored.first;
    await store.put(hash, Stream.value(bytes));

    expect(store.originalIfPresent(hash)!.readAsBytesSync(), bytes);
    expect(await stored, hash);
  });

  test('put() rejects a download that doesn\'t match its hash', () async {
    final hash = fileHashOf([1]);

    await expectLater(store.put(hash, Stream.value([2])), throwsFormatException);
    expect(store.originalIfPresent(hash), isNull);
  });

  test('put() stores a thumbnail without a hash check', () async {
    final name = FileStore.thumbnailNameOf(fileHashOf([1]));

    await store.put(name, Stream.value([2]));

    expect(store.fileOf(name).readAsBytesSync(), [2]);
  });

  test('put() refuses names that are no store names', () async {
    expect(() => store.put('../escape', Stream.value([1])), throwsArgumentError);
  });
}
