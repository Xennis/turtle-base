import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:turtle_base/core/database/tables/blocks_table.dart';
import 'package:turtle_base/core/database/tables/collections_table.dart';
import 'package:turtle_base/core/database/tables/fields_table.dart';
import 'package:turtle_base/core/database/tables/pages_table.dart';
import 'package:turtle_base/core/database/tables/spaces_table.dart';
import 'package:turtle_base/core/database/tables/users_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Users, Spaces, Collections, Fields, Pages, Blocks])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'turtle_base');
  }
}
