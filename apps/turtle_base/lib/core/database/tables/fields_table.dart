import 'package:drift/drift.dart';
import 'package:turtle_base/core/database/tables/audit_columns.dart';
import 'package:turtle_base/core/database/tables/collections_table.dart';

/// A column definition of a [Collections] entry. Referenced by its
/// stable id (not name) from `Pages.properties`, so renaming a field
/// never touches stored data.
class Fields extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get collectionId => text().references(Collections, #id)();
  TextColumn get name => text()();

  /// A base type id (see BaseFieldType), e.g. text or select. Older
  /// app versions also wrote `url`, now a variant of text.
  TextColumn get type => text()();
  IntColumn get position => integer()();

  /// JSON-encoded, type-specific (e.g. targetCollectionId for relation,
  /// the options list for select/multiSelect), plus the optional
  /// `variant` id (see FieldTypeRegistry.resolve).
  TextColumn get config => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
