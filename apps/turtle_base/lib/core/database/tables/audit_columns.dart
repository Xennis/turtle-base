import 'package:drift/drift.dart';
import 'package:turtle_base/core/database/tables/users_table.dart';

/// Standard audit + soft-delete columns shared by every business table.
/// Soft-delete keeps deleted rows recoverable instead of removing them,
/// which also avoids data loss when sync merges a delete with a
/// concurrent edit made on another device.
mixin AuditColumns on Table {
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get createdBy => text().references(Users, #id)();
  TextColumn get updatedBy => text().references(Users, #id)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}
