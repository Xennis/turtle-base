import 'package:drift/drift.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class CollectionsRepository {
  CollectionsRepository(this._db);

  final AppDatabase _db;

  /// Active (non-deleted) collections of a space, in creation order.
  /// Collections have no explicit position - unlike spaces, reordering
  /// them was not part of the requirements.
  Stream<List<Collection>> watchAllInSpace(String spaceId) {
    return (_db.select(_db.collections)
          ..where((c) => c.spaceId.equals(spaceId) & c.deletedAt.isNull())
          ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]))
        .watch();
  }

  Future<String> create({
    required String spaceId,
    required String name,
    String? icon,
  }) async {
    final userId = await _db.currentUserId();
    final now = DateTime.now();
    final id = _uuid.v4();

    await _db
        .into(_db.collections)
        .insert(
          CollectionsCompanion.insert(
            id: id,
            spaceId: spaceId,
            name: name,
            icon: Value(icon),
            createdAt: now,
            updatedAt: now,
            createdBy: userId,
            updatedBy: userId,
          ),
        );
    return id;
  }

  Future<void> rename(String id, String name) {
    return _update(id, CollectionsCompanion(name: Value(name)));
  }

  Future<void> setIcon(String id, String? icon) {
    return _update(id, CollectionsCompanion(icon: Value(icon)));
  }

  Future<void> move(String id, String newSpaceId) {
    return _update(id, CollectionsCompanion(spaceId: Value(newSpaceId)));
  }

  Future<void> softDelete(String id) {
    return _update(id, CollectionsCompanion(deletedAt: Value(DateTime.now())));
  }

  Future<void> restore(String id) {
    return _update(id, const CollectionsCompanion(deletedAt: Value(null)));
  }

  Future<void> _update(String id, CollectionsCompanion changes) async {
    final userId = await _db.currentUserId();
    await (_db.update(_db.collections)..where((c) => c.id.equals(id))).write(
      changes.copyWith(
        updatedAt: Value(DateTime.now()),
        updatedBy: Value(userId),
      ),
    );
  }
}
