import 'package:drift/drift.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/tables/field_type.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class FieldsRepository {
  FieldsRepository(this._db);

  final AppDatabase _db;

  /// Active (non-deleted) fields of a collection, in column order.
  Stream<List<Field>> watchAllInCollection(String collectionId) {
    return (_db.select(_db.fields)
          ..where((f) => f.collectionId.equals(collectionId) & f.deletedAt.isNull())
          ..orderBy([(f) => OrderingTerm.asc(f.position)]))
        .watch();
  }

  Future<String> create({
    required String collectionId,
    required String name,
    required FieldType type,
    String? config,
  }) async {
    final userId = await _db.currentUserId();
    final now = DateTime.now();
    final id = _uuid.v4();

    await _db
        .into(_db.fields)
        .insert(
          FieldsCompanion.insert(
            id: id,
            collectionId: collectionId,
            name: name,
            type: type.name,
            position: await _nextPosition(collectionId),
            config: Value(config),
            createdAt: now,
            updatedAt: now,
            createdBy: userId,
            updatedBy: userId,
          ),
        );
    return id;
  }

  Future<void> rename(String id, String name) {
    return _update(id, FieldsCompanion(name: Value(name)));
  }

  /// Only updates the type. Existing values in `pages.properties` are
  /// left as-is (see ARCHITECTURE.md) - converting them is a separate,
  /// not-yet-built concern.
  Future<void> changeType(String id, FieldType type) {
    return _update(id, FieldsCompanion(type: Value(type.name)));
  }

  Future<void> updateConfig(String id, String? config) {
    return _update(id, FieldsCompanion(config: Value(config)));
  }

  Future<void> reorder(String id, int position) {
    return _update(id, FieldsCompanion(position: Value(position)));
  }

  Future<void> softDelete(String id) {
    return _update(id, FieldsCompanion(deletedAt: Value(DateTime.now())));
  }

  Future<void> restore(String id) {
    return _update(id, const FieldsCompanion(deletedAt: Value(null)));
  }

  Future<void> _update(String id, FieldsCompanion changes) async {
    final userId = await _db.currentUserId();
    await (_db.update(_db.fields)..where((f) => f.id.equals(id))).write(
      changes.copyWith(
        updatedAt: Value(DateTime.now()),
        updatedBy: Value(userId),
      ),
    );
  }

  Future<int> _nextPosition(String collectionId) async {
    final maxPosition = _db.fields.position.max();
    final query = _db.selectOnly(_db.fields)
      ..addColumns([maxPosition])
      ..where(_db.fields.collectionId.equals(collectionId));
    final result = await query.map((row) => row.read(maxPosition)).getSingle();
    return (result ?? -1) + 1;
  }
}
