import 'package:drift/backends.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/packages/crdt_file_sync/sync_controller.dart';
import 'package:turtle_base/packages/crdt_file_sync/sync_transport.dart';
import 'package:turtle_base/packages/crdt_file_sync/testing/fake_sync_transport.dart';
import 'package:turtle_base/packages/drift_crdt/crdt_database_delegate.dart';

/// Mirrors `test/packages/drift_crdt/crdt_database_delegate_test.dart`'s helper -
/// gives each simulated "device" its own independent, already-seeded
/// in-memory database plus direct access to its `SqliteCrdt`.
(AppDatabase, CrdtDatabaseDelegate) _openCrdtDatabase() {
  final delegate = CrdtDatabaseDelegate(path: null);
  final db = AppDatabase.withExecutor(
    DatabaseConnection(DelegatedDatabase(delegate)),
  );
  return (db, delegate);
}

void main() {
  test('syncNow() with nothing to push/pull ends idle', () async {
    final (db, delegate) = _openCrdtDatabase();
    addTearDown(db.close);
    // Force the delegate to open before reading crdt.
    await db.select(db.spaces).get();

    final controller = SyncController(delegate.crdt, FakeSyncTransport());

    await controller.syncNow();

    expect(controller.status, SyncStatus.idle);
    expect(controller.lastError, isNull);
    expect(controller.lastSyncedAt, isNotNull);
  });

  test('two devices converge through a shared transport', () async {
    final (dbA, crdtA) = _openCrdtDatabase();
    addTearDown(dbA.close);
    final (dbB, crdtB) = _openCrdtDatabase();
    addTearDown(dbB.close);

    // AppDatabase no longer seeds a default space - create one per
    // simulated device, like a user would on each of their devices.
    final spaceAId = await SpacesRepository(dbA).create(name: 'On A');
    final spaceBId = await SpacesRepository(dbB).create(name: 'On B');

    final transport = FakeSyncTransport();
    final controllerA = SyncController(crdtA.crdt, transport);
    final controllerB = SyncController(crdtB.crdt, transport);

    await (dbA.update(dbA.spaces)..where((s) => s.id.equals(spaceAId))).write(
      const SpacesCompanion(name: Value('Renamed on A')),
    );

    await controllerA.syncNow();
    await controllerB.syncNow();

    final spacesOnB = await dbB.select(dbB.spaces).get();
    expect(spacesOnB.map((s) => s.id), containsAll([spaceAId, spaceBId]));
    expect(spacesOnB.firstWhere((s) => s.id == spaceAId).name, 'Renamed on A');

    // B also has to push its own (unmodified) space back to A to converge.
    await controllerB.syncNow();
    await controllerA.syncNow();

    final spacesOnA = await dbA.select(dbA.spaces).get();
    expect(spacesOnA.map((s) => s.id), containsAll([spaceAId, spaceBId]));
  });

  test('a second sync does not re-upload an already-pushed changeset', () async {
    final (db, delegate) = _openCrdtDatabase();
    addTearDown(db.close);
    await db.select(db.spaces).get();

    final transport = FakeSyncTransport();
    final controller = SyncController(delegate.crdt, transport);

    await controller.syncNow();
    final namesAfterFirstSync = await transport.list();
    expect(namesAfterFirstSync, hasLength(1));

    // Nothing changed locally in between - a second sync must not push again.
    await controller.syncNow();
    expect(await transport.list(), namesAfterFirstSync);
  });

  test('a transport failure surfaces as an error status without throwing', () async {
    final (db, delegate) = _openCrdtDatabase();
    addTearDown(db.close);
    await db.select(db.spaces).get();

    final controller = SyncController(delegate.crdt, _ThrowingSyncTransport());

    await controller.syncNow();

    expect(controller.status, SyncStatus.error);
    expect(controller.lastError, isNotNull);
  });
}

class _ThrowingSyncTransport implements SyncTransport {
  @override
  Future<void> upload(String name, Uint8List bytes) async {
    throw StateError('upload failed');
  }

  @override
  Future<List<String>> list() async => [];

  @override
  Future<Uint8List> download(String name) async {
    throw StateError('download failed');
  }
}
