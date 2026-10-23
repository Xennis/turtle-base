import 'package:drift/drift.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// What an attachment records about its file, see Attachments.
class AttachmentFile {
  const AttachmentFile({
    required this.fileHash,
    required this.name,
    required this.mimeType,
    required this.size,
    this.width,
    this.height,
  });

  final String fileHash;
  final String name;
  final String mimeType;
  final int size;
  final int? width;
  final int? height;
}

extension AttachmentKind on Attachment {
  bool get isImage => mimeType.startsWith('image/');
}

class AttachmentsRepository {
  AttachmentsRepository(this._db);

  final AppDatabase _db;

  /// The value of a files field on a page, in order.
  Stream<List<Attachment>> watchInField(String pageId, String fieldId) {
    return (_db.select(_db.attachments)
          ..where((a) => a.pageId.equals(pageId) & a.fieldId.equals(fieldId) & a.deletedAt.isNull())
          ..orderBy([(a) => OrderingTerm.asc(a.position), (a) => OrderingTerm.asc(a.id)]))
        .watch();
  }

  /// Every active attachment of a files field across a collection's
  /// entries, grouped by page id - e.g. for tile covers.
  Stream<Map<String, List<Attachment>>> watchInFieldOfCollection(String collectionId, String fieldId) {
    final query =
        _db.select(_db.attachments).join([innerJoin(_db.pages, _db.pages.id.equalsExp(_db.attachments.pageId))])
          ..where(
            _db.pages.collectionId.equals(collectionId) &
                _db.attachments.fieldId.equals(fieldId) &
                _db.attachments.deletedAt.isNull(),
          )
          ..orderBy([OrderingTerm.asc(_db.attachments.position), OrderingTerm.asc(_db.attachments.id)]);
    return query.watch().map((rows) {
      final byPage = <String, List<Attachment>>{};
      for (final row in rows) {
        final attachment = row.readTable(_db.attachments);
        byPage.putIfAbsent(attachment.pageId, () => []).add(attachment);
      }
      return byPage;
    });
  }

  /// Also finds deleted ones - a block can still reference one, e.g.
  /// right after undoing its removal.
  Stream<Attachment?> watchById(String id) {
    return (_db.select(_db.attachments)..where((a) => a.id.equals(id))).watchSingleOrNull();
  }

  Future<Attachment?> byId(String id) {
    return (_db.select(_db.attachments)..where((a) => a.id.equals(id))).getSingleOrNull();
  }

  /// Attachments in a page's rich text (no field), deleted ones
  /// included, see block_sync.dart.
  Future<List<Attachment>> allInPageContent(String pageId) {
    return (_db.select(_db.attachments)..where((a) => a.pageId.equals(pageId) & a.fieldId.isNull())).get();
  }

  /// The hashes of all attachments' files - with [activeOnly] false
  /// including deleted ones, which can still be restored.
  Future<Set<String>> fileHashes({required bool activeOnly}) async {
    final query = _db.selectOnly(_db.attachments, distinct: true)..addColumns([_db.attachments.fileHash]);
    if (activeOnly) query.where(_db.attachments.deletedAt.isNull());
    return {for (final row in await query.get()) row.read(_db.attachments.fileHash)!};
  }

  /// Appends [file] to the page's field ([fieldId]) or, with no field,
  /// to its rich text.
  Future<String> create({required String pageId, String? fieldId, required AttachmentFile file}) async {
    final userId = await _db.currentUserId();
    final now = DateTime.now();
    final id = _uuid.v4();
    await _db
        .into(_db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: id,
            pageId: pageId,
            fieldId: Value(fieldId),
            fileHash: file.fileHash,
            name: file.name,
            mimeType: file.mimeType,
            size: file.size,
            width: Value(file.width),
            height: Value(file.height),
            position: await _nextPosition(pageId, fieldId),
            createdAt: now,
            updatedAt: now,
            createdBy: userId,
            updatedBy: userId,
          ),
        );
    return id;
  }

  /// A new attachment of [source]'s file on [pageId], e.g. for a block
  /// pasted from another page.
  Future<String> copyTo(Attachment source, {required String pageId, String? fieldId}) {
    return create(
      pageId: pageId,
      fieldId: fieldId,
      file: AttachmentFile(
        fileHash: source.fileHash,
        name: source.name,
        mimeType: source.mimeType,
        size: source.size,
        width: source.width,
        height: source.height,
      ),
    );
  }

  /// Gives the attachments [orderedIds]' order, only touching the ones
  /// whose position changes.
  Future<void> reorderAll(List<String> orderedIds) async {
    final positions = {
      for (final attachment in await (_db.select(_db.attachments)..where((a) => a.id.isIn(orderedIds))).get())
        attachment.id: attachment.position,
    };
    await _db.transaction(() async {
      for (final (index, id) in orderedIds.indexed) {
        if (positions[id] != index) await _update(id, AttachmentsCompanion(position: Value(index)));
      }
    });
  }

  /// The file itself stays - other attachments may share it, and this
  /// one can be restored.
  Future<void> softDelete(String id) {
    return _update(id, AttachmentsCompanion(deletedAt: Value(DateTime.now())));
  }

  Future<void> restore(String id) {
    return _update(id, const AttachmentsCompanion(deletedAt: Value(null)));
  }

  Future<void> _update(String id, AttachmentsCompanion changes) async {
    final userId = await _db.currentUserId();
    await (_db.update(_db.attachments)..where((a) => a.id.equals(id))).write(
      changes.copyWith(updatedAt: Value(DateTime.now()), updatedBy: Value(userId)),
    );
  }

  Future<int> _nextPosition(String pageId, String? fieldId) async {
    final maxPosition = _db.attachments.position.max();
    final query = _db.selectOnly(_db.attachments)
      ..addColumns([maxPosition])
      ..where(
        _db.attachments.pageId.equals(pageId) &
            (fieldId == null ? _db.attachments.fieldId.isNull() : _db.attachments.fieldId.equals(fieldId)),
      );
    final result = await query.map((row) => row.read(maxPosition)).getSingle();
    return (result ?? -1) + 1;
  }
}
