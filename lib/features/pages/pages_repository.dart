import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Decodes a page's raw `properties` column into a map keyed by field id.
/// Only meaningful for pages that are a collection entry.
Map<String, Object?> decodePageProperties(String propertiesJson) {
  return Map<String, Object?>.from(jsonDecode(propertiesJson) as Map);
}

class PagesRepository {
  PagesRepository(this._db);

  final AppDatabase _db;

  /// Active entries of a collection, in grid row order.
  Stream<List<Page>> watchAllInCollection(String collectionId) {
    return (_db.select(_db.pages)
          ..where(
            (p) => p.collectionId.equals(collectionId) & p.deletedAt.isNull(),
          )
          ..orderBy([(p) => OrderingTerm.asc(p.position)]))
        .watch();
  }

  /// Active top-level, freestanding pages of a space (not a collection
  /// entry, no parent) - what the sidebar shows.
  Stream<List<Page>> watchTopLevelInSpace(String spaceId) {
    return (_db.select(_db.pages)..where(
          (p) =>
              p.spaceId.equals(spaceId) &
              p.collectionId.isNull() &
              p.parentPageId.isNull() &
              p.deletedAt.isNull(),
        ))
        .watch();
  }

  Stream<Page> watchById(String id) {
    return (_db.select(
      _db.pages,
    )..where((p) => p.id.equals(id))).watchSingle();
  }

  Future<String> create({
    required String spaceId,
    String? collectionId,
    String? parentPageId,
    String title = '',
    String? icon,
    Map<String, Object?>? properties,
  }) async {
    final userId = await _db.currentUserId();
    final now = DateTime.now();
    final id = _uuid.v4();
    final position = collectionId != null
        ? await _nextPositionInCollection(collectionId)
        : await _nextPositionInSpace(spaceId, parentPageId);

    await _db
        .into(_db.pages)
        .insert(
          PagesCompanion.insert(
            id: id,
            spaceId: spaceId,
            collectionId: Value(collectionId),
            parentPageId: Value(parentPageId),
            title: title,
            icon: Value(icon),
            properties: properties == null
                ? const Value.absent()
                : Value(jsonEncode(properties)),
            position: position,
            createdAt: now,
            updatedAt: now,
            createdBy: userId,
            updatedBy: userId,
          ),
        );
    return id;
  }

  Future<void> rename(String id, String title) {
    return _update(id, PagesCompanion(title: Value(title)));
  }

  Future<void> setIcon(String id, String? icon) {
    return _update(id, PagesCompanion(icon: Value(icon)));
  }

  /// Reads-modifies-writes the single field's value, leaving the rest
  /// of `properties` untouched.
  Future<void> setPropertyValue(String id, String fieldId, Object? value) async {
    final page = await (_db.select(
      _db.pages,
    )..where((p) => p.id.equals(id))).getSingle();
    final properties = decodePageProperties(page.properties);
    properties[fieldId] = value;
    await _update(id, PagesCompanion(properties: Value(jsonEncode(properties))));
  }

  Future<void> move(String id, String newSpaceId) {
    return _update(id, PagesCompanion(spaceId: Value(newSpaceId)));
  }

  Future<void> reorder(String id, int position) {
    return _update(id, PagesCompanion(position: Value(position)));
  }

  Future<void> softDelete(String id) {
    return _update(id, PagesCompanion(deletedAt: Value(DateTime.now())));
  }

  Future<void> restore(String id) {
    return _update(id, const PagesCompanion(deletedAt: Value(null)));
  }

  Future<void> _update(String id, PagesCompanion changes) async {
    final userId = await _db.currentUserId();
    await (_db.update(_db.pages)..where((p) => p.id.equals(id))).write(
      changes.copyWith(
        updatedAt: Value(DateTime.now()),
        updatedBy: Value(userId),
      ),
    );
  }

  Future<int> _nextPositionInCollection(String collectionId) async {
    final maxPosition = _db.pages.position.max();
    final query = _db.selectOnly(_db.pages)
      ..addColumns([maxPosition])
      ..where(_db.pages.collectionId.equals(collectionId));
    final result = await query
        .map((row) => row.read(maxPosition))
        .getSingle();
    return (result ?? -1) + 1;
  }

  Future<int> _nextPositionInSpace(String spaceId, String? parentPageId) async {
    final maxPosition = _db.pages.position.max();
    final query = _db.selectOnly(_db.pages)
      ..addColumns([maxPosition])
      ..where(_db.pages.spaceId.equals(spaceId) & _db.pages.collectionId.isNull())
      ..where(
        parentPageId == null
            ? _db.pages.parentPageId.isNull()
            : _db.pages.parentPageId.equals(parentPageId),
      );
    final result = await query
        .map((row) => row.read(maxPosition))
        .getSingle();
    return (result ?? -1) + 1;
  }
}
