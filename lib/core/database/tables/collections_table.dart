import 'package:drift/drift.dart';
import 'package:turtle_base/core/database/tables/audit_columns.dart';
import 'package:turtle_base/core/database/tables/spaces_table.dart';

/// A user-defined table with user-defined columns. Its columns are
/// defined by [Fields], its rows are [Pages] with collectionId set.
class Collections extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get spaceId => text().references(Spaces, #id)();
  TextColumn get name => text()();
  TextColumn get icon => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
