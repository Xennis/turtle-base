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
  ///
  /// [id] can be supplied explicitly so it matches an id already
  /// assigned elsewhere (e.g. appflowy_editor's Node.id when syncing a
  /// new node back to storage, see block_sync.dart) - generated if
  /// omitted, like every other repository's create().
  Future<String> create({
    String? id,
    required String pageId,
    String? parentBlockId,
    required String type,
    String content = '{}',
  }) async {
    final userId = await _db.currentUserId();
    final now = DateTime.now();
    final resolvedId = id ?? _uuid.v4();

    await _db
        .into(_db.blocks)
        .insert(
          BlocksCompanion.insert(
            id: resolvedId,
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
    return resolvedId;
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

  /// Changes both parent and position together (e.g. indenting a block
  /// into a list, or the editor otherwise restructuring the tree).
  Future<void> move(String id, {String? parentBlockId, required int position}) {
    return _update(
      id,
      BlocksCompanion(
        parentBlockId: Value(parentBlockId),
        position: Value(position),
      ),
    );
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
