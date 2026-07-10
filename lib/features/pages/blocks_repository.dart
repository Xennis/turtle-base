import 'package:drift/drift.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class BlocksRepository {
  BlocksRepository(this._db);

  final AppDatabase _db;

  /// Active blocks of a page, in sibling order. Blocks form a tree via
  /// parentBlockId - this returns the flat list, reconstructing the
  /// hierarchy for rendering is left to the caller.
  Stream<List<Block>> watchAllInPage(String pageId) {
    return (_db.select(_db.blocks)
          ..where((b) => b.pageId.equals(pageId) & b.deletedAt.isNull())
          ..orderBy([(b) => OrderingTerm.asc(b.position)]))
        .watch();
  }

  /// [type] is a plain string (not an enum, unlike FieldType) - block
  /// types stay open-ended, since custom ones (code, YouTube embed) are
  /// planned to be added later without touching this repository.
  Future<String> create({
    required String pageId,
    String? parentBlockId,
    required String type,
    String content = '{}',
  }) async {
    final userId = await _db.currentUserId();
    final now = DateTime.now();
    final id = _uuid.v4();

    await _db
        .into(_db.blocks)
        .insert(
          BlocksCompanion.insert(
            id: id,
            pageId: pageId,
            parentBlockId: Value(parentBlockId),
            type: type,
            position: await _nextPosition(pageId, parentBlockId),
            content: content,
            createdAt: now,
            updatedAt: now,
            createdBy: userId,
            updatedBy: userId,
          ),
        );
    return id;
  }

  Future<void> updateContent(String id, String content) {
    return _update(id, BlocksCompanion(content: Value(content)));
  }

  Future<void> changeType(String id, String type) {
    return _update(id, BlocksCompanion(type: Value(type)));
  }

  Future<void> reorder(String id, int position) {
    return _update(id, BlocksCompanion(position: Value(position)));
  }

  /// Does not cascade to nested blocks - not needed by any feature yet.
  Future<void> softDelete(String id) {
    return _update(id, BlocksCompanion(deletedAt: Value(DateTime.now())));
  }

  Future<void> restore(String id) {
    return _update(id, const BlocksCompanion(deletedAt: Value(null)));
  }

  Future<void> _update(String id, BlocksCompanion changes) async {
    final userId = await _db.currentUserId();
    await (_db.update(_db.blocks)..where((b) => b.id.equals(id))).write(
      changes.copyWith(
        updatedAt: Value(DateTime.now()),
        updatedBy: Value(userId),
      ),
    );
  }

  Future<int> _nextPosition(String pageId, String? parentBlockId) async {
    final maxPosition = _db.blocks.position.max();
    final query = _db.selectOnly(_db.blocks)
      ..addColumns([maxPosition])
      ..where(_db.blocks.pageId.equals(pageId))
      ..where(
        parentBlockId == null
            ? _db.blocks.parentBlockId.isNull()
            : _db.blocks.parentBlockId.equals(parentBlockId),
      );
    final result = await query
        .map((row) => row.read(maxPosition))
        .getSingle();
    return (result ?? -1) + 1;
  }
}
