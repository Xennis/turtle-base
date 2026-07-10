import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:turtle_base/core/database/tables/blocks_table.dart';
import 'package:turtle_base/core/database/tables/collections_table.dart';
import 'package:turtle_base/core/database/tables/fields_table.dart';
import 'package:turtle_base/core/database/tables/pages_table.dart';
import 'package:turtle_base/core/database/tables/spaces_table.dart';
import 'package:turtle_base/core/database/tables/users_table.dart';
import 'package:uuid/uuid.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Users, Spaces, Collections, Fields, Pages, Blocks])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedDefaults();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Custom, per-collection label for the built-in title column
        // (see Collections.titleFieldLabel).
        await m.addColumn(collections, collections.titleFieldLabel);
      }
    },
  );

  /// Runs once, when the database file is created for the first time.
  /// There is no login/auth - a local user profile and a default space
  /// (freely renameable afterwards) always exist from the first start.
  Future<void> _seedDefaults() async {
    const uuid = Uuid();
    final now = DateTime.now();
    final userId = uuid.v4();

    await into(users).insert(
      UsersCompanion.insert(id: userId, name: 'You', createdAt: now),
    );
    await into(spaces).insert(
      SpacesCompanion.insert(
        id: uuid.v4(),
        name: 'Default',
        position: 0,
        createdAt: now,
        updatedAt: now,
        createdBy: userId,
        updatedBy: userId,
      ),
    );
  }

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'turtle_base');
  }

  /// Single-user app: there is always exactly one user row (seeded on
  /// first start). Repositories use this to fill createdBy/updatedBy
  /// without every caller having to know or pass a user id.
  Future<String> currentUserId() async {
    final user = await select(users).getSingle();
    return user.id;
  }
}
