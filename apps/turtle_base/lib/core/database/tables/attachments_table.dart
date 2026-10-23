import 'package:drift/drift.dart';
import 'package:turtle_base/core/database/tables/audit_columns.dart';
import 'package:turtle_base/core/database/tables/fields_table.dart';
import 'package:turtle_base/core/database/tables/pages_table.dart';

/// One use of a file on a page - the value (or one of the values) of a
/// files field, or a file in the page's rich text. The bytes live apart
/// from the database, named by [fileHash], so two attachments of the
/// same file share them (see FileStore).
class Attachments extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get pageId => text().references(Pages, #id)();

  /// Null for a file in the page's rich text (an `attachment` block).
  TextColumn get fieldId => text().nullable().references(Fields, #id)();

  /// `sha256-<hex>` of the content.
  TextColumn get fileHash => text()();

  /// The original file name.
  TextColumn get name => text()();
  TextColumn get mimeType => text()();

  /// In bytes.
  IntColumn get size => integer()();

  /// Pixel size of an image, to lay it out before it's loaded.
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();

  /// Order within the page's field (or rich text). Ties - two devices
  /// adding offline - are broken by [id].
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
