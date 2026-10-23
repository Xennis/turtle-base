import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/sync/sync_format.dart';

void main() {
  Future<List<int>> writesFor(int? found) async {
    final written = <int>[];
    await ensureSyncFormat(read: () async => found, write: (version) async => written.add(version));
    return written;
  }

  test('writes the version when there is none yet', () async {
    expect(await writesFor(null), [syncFormatVersion]);
  });

  test('upgrades an older version', () async {
    expect(await writesFor(syncFormatVersion - 1), [syncFormatVersion]);
  });

  test('leaves the same version alone', () async {
    expect(await writesFor(syncFormatVersion), isEmpty);
  });

  test('refuses a newer version', () async {
    expect(writesFor(syncFormatVersion + 1), throwsA(isA<SyncFormatTooNewException>()));
  });
}
