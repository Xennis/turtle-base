import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/files/data/attachments_repository.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/plugins/data/plugin_registry.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/field_type_registry.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';
import 'package:turtle_base/features/tables/data/resolved_field.dart';
import 'package:turtle_base/packages/file_store/file_store.dart';
import 'package:turtle_plugin/turtle_plugin.dart';

/// Turns an [EntryDraft] a plugin's lookup found into an entry of the
/// plugin's collection - through the same checks as the user's input,
/// so a field the user deleted or changed since only drops its value.
class EntryDraftWriter {
  EntryDraftWriter(AppDatabase db, {required this._fieldTypes, required this._files, http.Client? client})
    : _client = client ?? http.Client(),
      _collections = CollectionsRepository(db),
      _fields = FieldsRepository(db),
      _pages = PagesRepository(db),
      _attachments = AttachmentsRepository(db);

  final FieldTypeRegistry _fieldTypes;
  final FileStore _files;
  final http.Client _client;
  final CollectionsRepository _collections;
  final FieldsRepository _fields;
  final PagesRepository _pages;
  final AttachmentsRepository _attachments;

  /// An active entry with the same value of [uniqueFieldKey] as
  /// [draft], so picking a result twice opens it instead of adding a
  /// copy. Null when there's none, or no such field (anymore).
  Future<String?> findExisting(String collectionId, EntryDraft draft, {required String? uniqueFieldKey}) async {
    if (uniqueFieldKey == null) return null;
    final field = (await _fieldsByKey(collectionId))[uniqueFieldKey];
    final value = field?.storedFor(draft.values[uniqueFieldKey]);
    if (field == null || value == null) return null;
    final entries = await _pages.watchAllInCollection(collectionId).first;
    return entries.where((e) => decodePageProperties(e.properties)[field.id] == value).firstOrNull?.id;
  }

  /// Creates the entry with the draft's title and values, without its
  /// files - see [attachFiles].
  Future<String> create(String collectionId, EntryDraft draft) async {
    final fields = await _fieldsByKey(collectionId);
    final properties = <String, Object?>{
      for (final MapEntry(:key, :value) in draft.values.entries)
        if (fields[key] case final field?) field.id: ?field.storedFor(value),
    };
    final collection = await _collections.watchById(collectionId).first;
    return _pages.create(
      spaceId: collection.spaceId,
      collectionId: collectionId,
      title: draft.title,
      properties: properties,
    );
  }

  /// Downloads the draft's files into their files fields, checked
  /// against the field's `accept` and `maxFiles` like picked files. A
  /// file that fails is skipped - the entry stays without it.
  Future<void> attachFiles(String collectionId, String pageId, EntryDraft draft) async {
    final fields = await _fieldsByKey(collectionId);
    for (final MapEntry(key: fieldKey, value: uris) in draft.files.entries) {
      final field = fields[fieldKey];
      final config = field?.config;
      if (field == null || config is! FilesConfig) continue;
      var count = (await _attachments.watchInField(pageId, field.id).first).length;
      for (final uri in uris) {
        if (config.maxFiles case final max? when count >= max) break;
        try {
          if (await _download(uri, pageId: pageId, fieldId: field.id, config: config)) count++;
        } catch (e) {
          debugPrint('[plugins] no file from $uri: $e');
        }
      }
    }
  }

  /// Whether the file was attached - false when the field doesn't take
  /// its type.
  Future<bool> _download(
    Uri uri, {
    required String pageId,
    required String fieldId,
    required FilesConfig config,
  }) async {
    final response = await _client.get(uri);
    if (response.statusCode != 200) throw http.ClientException('HTTP ${response.statusCode}', uri);
    final name = uri.pathSegments.lastOrNull ?? 'download';
    final dir = await Directory.systemTemp.createTemp('turtle_base_download');
    try {
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(response.bodyBytes);
      final stored = await _files.import(file);
      if (!config.accept.accepts(mimeType: stored.mimeType, fileName: name)) return false;
      await _attachments.create(
        pageId: pageId,
        fieldId: fieldId,
        file: AttachmentFile(
          fileHash: stored.hash,
          name: name,
          mimeType: stored.mimeType,
          size: stored.size,
          width: stored.width,
          height: stored.height,
        ),
      );
      return true;
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// The collection's active fields created from the template, by their
  /// key - fields the user added have no key.
  Future<Map<String, ResolvedField>> _fieldsByKey(String collectionId) async {
    final prefix = pluginFieldId(collectionId, '');
    return {
      for (final row in await _fields.watchAllInCollection(collectionId).first)
        if (row.id.startsWith(prefix)) row.id.substring(prefix.length): _fieldTypes.resolve(row),
    };
  }
}
