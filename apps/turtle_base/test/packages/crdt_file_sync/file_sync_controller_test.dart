import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:turtle_base/packages/crdt_file_sync/file_sync_controller.dart';
import 'package:turtle_base/packages/crdt_file_sync/testing/fake_file_transport.dart';
import 'package:turtle_base/packages/file_store/file_store.dart';

void main() {
  late Directory tmp;
  late FakeFileTransport transport;
  late FileStore storeA;
  late FileStore storeB;
  late FileSyncController deviceA;
  late FileSyncController deviceB;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('file_sync_controller_test');
    transport = FakeFileTransport();
    storeA = FileStore(p.join(tmp.path, 'a'));
    storeB = FileStore(p.join(tmp.path, 'b'));
    deviceA = FileSyncController(storeA, transport);
    deviceB = FileSyncController(storeB, transport);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<String> importImage(FileStore store) async {
    final source = File(p.join(tmp.path, 'photo.png'))..writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
    return (await store.import(source)).hash;
  }

  test('push() uploads original and thumbnail, once', () async {
    final hash = await importImage(storeA);

    expect(await deviceA.push({hash}), 0);
    expect(transport.files.keys, unorderedEquals([hash, FileStore.thumbnailNameOf(hash)]));

    transport.failing.add(hash);
    expect(await deviceA.push({hash}), 0, reason: 'already uploaded, so not tried again');
  });

  test('push() skips hashes the device has no file for', () async {
    expect(
      await deviceA.push({
        fileHashOf([1]),
      }),
      0,
    );
    expect(transport.files, isEmpty);
  });

  test('pull() fetches thumbnails, originals only when asked', () async {
    final hash = await importImage(storeA);
    await deviceA.push({hash});

    await deviceB.pull({hash}, originals: false);
    expect(storeB.thumbnailIfPresent(hash), isNotNull);
    expect(storeB.originalIfPresent(hash), isNull);

    await deviceB.pull({hash}, originals: true);
    expect(storeB.originalIfPresent(hash)!.readAsBytesSync(), storeA.originalIfPresent(hash)!.readAsBytesSync());
  });

  test('failures are counted, not thrown', () async {
    final hash = await importImage(storeA);
    transport.failing.add(hash);

    expect(await deviceA.push({hash}), 1);

    transport.failing.clear();
    await deviceA.push({hash});
    transport.failing.add(hash);
    expect(await deviceB.pull({hash}, originals: true), 1);
  });

  test('fetch() downloads one file on demand', () async {
    final hash = await importImage(storeA);
    await deviceA.push({hash});

    final results = await Future.wait([deviceB.fetch(hash), deviceB.fetch(hash)]);

    expect(results, [true, true]);
    expect(storeB.originalIfPresent(hash), isNotNull);
    expect(await deviceB.fetch(fileHashOf([1])), isFalse);
  });
}
