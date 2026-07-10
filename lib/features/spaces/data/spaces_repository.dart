import 'package:drift/drift.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class SpacesRepository {
  SpacesRepository(this._db);

  final AppDatabase _db;

  /// Active (non-deleted) spaces, ordered as shown in the sidebar.
  Stream<List<Space>> watchAll() {
    return (_db.select(_db.spaces)
          ..where((s) => s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.position)]))
        .watch();
  }

  Future<String> create({required String name, String? icon}) async {
    final userId = await _db.currentUserId();
    final now = DateTime.now();
    final id = _uuid.v4();

    await _db
        .into(_db.spaces)
        .insert(
          SpacesCompanion.insert(
            id: id,
            name: name,
            icon: Value(icon),
            position: await _nextPosition(),
            createdAt: now,
            updatedAt: now,
            createdBy: userId,
            updatedBy: userId,
          ),
        );
    return id;
  }

  Future<void> rename(String id, String name) {
    return _update(id, SpacesCompanion(name: Value(name)));
  }

  Future<void> setIcon(String id, String? icon) {
    return _update(id, SpacesCompanion(icon: Value(icon)));
  }

  Future<void> reorder(String id, int position) {
    return _update(id, SpacesCompanion(position: Value(position)));
  }

  Future<void> softDelete(String id) {
    return _update(id, SpacesCompanion(deletedAt: Value(DateTime.now())));
  }

  Future<void> restore(String id) {
    return _update(id, const SpacesCompanion(deletedAt: Value(null)));
  }

  Future<void> _update(String id, SpacesCompanion changes) async {
    final userId = await _db.currentUserId();
    await (_db.update(_db.spaces)..where((s) => s.id.equals(id))).write(
      changes.copyWith(
        updatedAt: Value(DateTime.now()),
        updatedBy: Value(userId),
      ),
    );
  }

  Future<int> _nextPosition() async {
    final maxPosition = _db.spaces.position.max();
    final query = _db.selectOnly(_db.spaces)..addColumns([maxPosition]);
    final result = await query.map((row) => row.read(maxPosition)).getSingle();
    return (result ?? -1) + 1;
  }
}
