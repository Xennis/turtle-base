import 'dart:convert';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/packages/drift_crdt/crdt_database_delegate.dart';

/// Pairs the database with its delegate so tests can reach
/// getChangeset()/merge() directly, alongside typed Drift queries.
(AppDatabase, CrdtDatabaseDelegate) _openCrdtDatabase() {
  final delegate = CrdtDatabaseDelegate(path: null);
  final db = AppDatabase.withExecutor(
    DatabaseConnection(DelegatedDatabase(delegate)),
  );
  return (db, delegate);
}

/// AppDatabase no longer seeds a default space (see its
/// _seedDefaults doc comment) - tests that need one create it directly.
Future<Space> _createSpace(AppDatabase db, {required String id, required String name}) async {
  final userId = await db.currentUserId();
  final now = DateTime.now();
  await db
      .into(db.spaces)
      .insert(
        SpacesCompanion.insert(
          id: id,
          name: name,
          position: 0,
          createdAt: now,
          updatedAt: now,
          createdBy: userId,
          updatedBy: userId,
        ),
      );
  return (db.select(db.spaces)..where((s) => s.id.equals(id))).getSingle();
}

void main() {
  test('runs migrations/seeding through the CRDT delegate like any other executor', () async {
    final (db, _) = _openCrdtDatabase();
    addTearDown(db.close);

    // Only the single-user profile is seeded - no default space (see
    // AppDatabase._seedDefaults's doc comment).
    final users = await db.select(db.users).get();
    expect(users, hasLength(1));
    final spaces = await db.select(db.spaces).get();
    expect(spaces, isEmpty);
  });

  test('typed repository-style writes and reads work through the delegate', () async {
    final (db, _) = _openCrdtDatabase();
    addTearDown(db.close);

    final userId = await db.currentUserId();
    final now = DateTime.now();
    const spaceId = 'space_1';
    await db
        .into(db.spaces)
        .insert(
          SpacesCompanion.insert(
            id: spaceId,
            name: 'Space',
            position: 0,
            createdAt: now,
            updatedAt: now,
            createdBy: userId,
            updatedBy: userId,
          ),
        );

    await db
        .into(db.pages)
        .insert(
          PagesCompanion.insert(
            id: 'page_1',
            spaceId: spaceId,
            title: 'Hello',
            position: 0,
            createdAt: now,
            updatedAt: now,
            createdBy: userId,
            updatedBy: userId,
          ),
        );

    final page = await (db.select(
      db.pages,
    )..where((p) => p.id.equals('page_1'))).getSingle();
    expect(page.title, 'Hello');

    await (db.update(db.pages)..where((p) => p.id.equals('page_1'))).write(
      const PagesCompanion(title: Value('Renamed')),
    );

    final renamed = await (db.select(
      db.pages,
    )..where((p) => p.id.equals('page_1'))).getSingle();
    expect(renamed.title, 'Renamed');
  });

  test(
    'two databases diverge and converge via getChangeset()/merge()',
    () async {
      final (dbA, crdtA) = _openCrdtDatabase();
      addTearDown(dbA.close);
      final (dbB, crdtB) = _openCrdtDatabase();
      addTearDown(dbB.close);

      // Each database creates its own independent space - simulating two
      // devices that have never synced.
      final spaceA = await _createSpace(dbA, id: 'space_a', name: 'On A');
      final spaceB = await _createSpace(dbB, id: 'space_b', name: 'On B');
      expect(spaceA.id, isNot(spaceB.id));

      // A renames its own space, B never sees this until synced.
      await (dbA.update(dbA.spaces)..where((s) => s.id.equals(spaceA.id))).write(
        const SpacesCompanion(name: Value('Renamed on A')),
      );

      // Extract A's changeset and merge it into B, round-tripping through
      // JSON like a real transport (Drive, in a later step) would -
      // getChangeset() returns hlc as a plain string ready for that, and
      // parseCrdtChangeset() is the documented way back to Hlc objects.
      final changeset = await crdtA.crdt.getChangeset();
      final wireFormat = jsonDecode(jsonEncode(changeset)) as Map<String, dynamic>;
      await crdtB.crdt.merge(parseCrdtChangeset(wireFormat));

      final spacesOnB = await dbB.select(dbB.spaces).get();
      // B now knows about both spaces: its own, and A's (renamed).
      expect(spacesOnB.map((s) => s.id), containsAll([spaceA.id, spaceB.id]));
      expect(
        spacesOnB.firstWhere((s) => s.id == spaceA.id).name,
        'Renamed on A',
      );
    },
  );

  test(
    "currentUserId() stays stable after sync merges in another device's user row",
    () async {
      final (dbA, crdtA) = _openCrdtDatabase();
      addTearDown(dbA.close);
      final (dbB, crdtB) = _openCrdtDatabase();
      addTearDown(dbB.close);

      // Each device resolves (and caches) its own identity first, exactly
      // as main.dart does before restoreConnection() can pull in a merge.
      final userIdA = await dbA.currentUserId();
      final userIdB = await dbB.currentUserId();
      expect(userIdA, isNot(userIdB));

      // A's changeset includes its onCreate-seeded user row - merging it
      // into B simulates two devices connecting Drive sync to the same
      // account, which leaves B with two rows in `users`.
      final changeset = await crdtA.crdt.getChangeset();
      final wireFormat = jsonDecode(jsonEncode(changeset)) as Map<String, dynamic>;
      await crdtB.crdt.merge(parseCrdtChangeset(wireFormat));

      final usersOnB = await dbB.select(dbB.users).get();
      expect(usersOnB, hasLength(2));
      // B still resolves to its own (cached) id, not A's - and doesn't
      // throw "Bad state: Too many elements" the way a plain
      // `select(users).getSingle()` would.
      expect(await dbB.currentUserId(), userIdB);
    },
  );

  test('AppDatabase.crdt resolves to the SqliteCrdt behind its CrdtDatabaseDelegate', () async {
    final delegate = CrdtDatabaseDelegate(path: null);
    final db = AppDatabase.withExecutor(
      DatabaseConnection(DelegatedDatabase(delegate)),
      Future.value(delegate),
    );
    addTearDown(db.close);

    // Trigger the connection to actually open before reading crdt.
    await db.select(db.spaces).get();

    expect(await db.crdt, same(delegate.crdt));
  });

  test('AppDatabase.crdt throws when constructed without a delegate', () async {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.crdt, throwsStateError);
  });
}
