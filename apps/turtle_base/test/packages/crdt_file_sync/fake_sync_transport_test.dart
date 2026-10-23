import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/packages/crdt_file_sync/testing/fake_sync_transport.dart';

void main() {
  test('list() is empty for a fresh transport', () async {
    final transport = FakeSyncTransport();
    expect(await transport.list(), isEmpty);
  });

  test('uploaded files show up in list() and round-trip through download()', () async {
    final transport = FakeSyncTransport();
    final bytes = Uint8List.fromList(utf8.encode('hello'));

    await transport.upload('node-a/1.json', bytes);

    expect(await transport.list(), ['node-a/1.json']);
    expect(await transport.download('node-a/1.json'), bytes);
  });

  test('uploading the same name again overwrites the previous content', () async {
    final transport = FakeSyncTransport();
    await transport.upload('node-a/1.json', Uint8List.fromList([1]));
    await transport.upload('node-a/1.json', Uint8List.fromList([2]));

    expect(await transport.list(), ['node-a/1.json']);
    expect(await transport.download('node-a/1.json'), Uint8List.fromList([2]));
  });

  test('download() throws for an unknown name', () async {
    final transport = FakeSyncTransport();
    expect(() => transport.download('missing.json'), throwsStateError);
  });
}
