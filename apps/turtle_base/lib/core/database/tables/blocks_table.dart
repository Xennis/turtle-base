import 'package:drift/drift.dart';
import 'package:turtle_base/core/database/tables/audit_columns.dart';
import 'package:turtle_base/core/database/tables/pages_table.dart';

/// A single rich-text block of a page (or collection entry). One block
/// per row - rather than one JSON blob per page - so sync can merge at
/// block granularity instead of overwriting a whole page.
class Blocks extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get pageId => text().references(Pages, #id)();

  /// Nested blocks, e.g. a list inside a list.
  TextColumn get parentBlockId => text().nullable().references(Blocks, #id)();

  /// E.g. paragraph, heading, bulleted_list, image, table_ref.
  TextColumn get type => text()();
  IntColumn get position => integer()();

  /// JSON-encoded, native appflowy_editor node/delta format.
  TextColumn get content => text()();

  @override
  Set<Column> get primaryKey => {id};
}
