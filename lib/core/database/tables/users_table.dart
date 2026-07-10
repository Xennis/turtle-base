import 'package:drift/drift.dart';

/// Not an auth system - no passwords, no login. A row is created
/// automatically on first app start and referenced by other tables'
/// audit columns (who created/updated a record).
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
