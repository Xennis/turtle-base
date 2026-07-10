import 'package:drift/drift.dart';
import 'package:turtle_base/core/database/tables/audit_columns.dart';

/// Container above collections and pages (e.g. "Default", "Fitness").
class Spaces extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text().nullable()();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
