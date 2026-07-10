import 'package:drift/drift.dart';
import 'package:turtle_base/core/database/tables/audit_columns.dart';
import 'package:turtle_base/core/database/tables/collections_table.dart';
import 'package:turtle_base/core/database/tables/spaces_table.dart';

/// A page is either freestanding (collectionId == null) or a collection
/// entry (collectionId set), unifying the "page" and "database row"
/// concept into one. Rich text content lives in [Blocks].
class Pages extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get spaceId => text().references(Spaces, #id)();
  TextColumn get collectionId =>
      text().nullable().references(Collections, #id)();

  /// Nested pages are supported by the schema but not yet by the UI.
  TextColumn get parentPageId => text().nullable().references(Pages, #id)();
  TextColumn get title => text()();
  TextColumn get icon => text().nullable()();

  /// JSON-encoded `{"fieldId": value, ...}`, only meaningful when
  /// collectionId is set.
  TextColumn get properties => text().withDefault(const Constant('{}'))();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
