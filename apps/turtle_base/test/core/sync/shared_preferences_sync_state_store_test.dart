import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';
import 'package:turtle_base/core/sync/shared_preferences_sync_state_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the push state survives a new store instance, per node id', () async {
    final hlc = Hlc(DateTime.utc(2026, 10, 23, 12), 3, 'node-a');
    await SharedPreferencesSyncStateStore(await SharedPreferences.getInstance()).setLastPushedAt('node-a', hlc);

    final reloaded = SharedPreferencesSyncStateStore(await SharedPreferences.getInstance());

    expect(reloaded.lastPushedAt('node-a'), hlc);
    expect(reloaded.lastPushedAt('node-b'), isNull);
  });

  test('the merged files survive a new store instance, per node id', () async {
    await SharedPreferencesSyncStateStore(await SharedPreferences.getInstance())
        .setMergedFiles('node-a', {'node-b/1-0.json', 'node-c/2-0.json'});

    final reloaded = SharedPreferencesSyncStateStore(await SharedPreferences.getInstance());

    expect(reloaded.mergedFiles('node-a'), {'node-b/1-0.json', 'node-c/2-0.json'});
    expect(reloaded.mergedFiles('node-b'), isEmpty);
  });
}
