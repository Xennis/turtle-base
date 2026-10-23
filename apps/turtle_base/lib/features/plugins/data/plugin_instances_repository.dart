import 'dart:convert';

import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/plugins/data/plugin_registry.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';
import 'package:turtle_plugin/turtle_plugin.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// An instance of a plugin is the space created by adding it, holding
/// one collection per template - from then on ordinary rows the user
/// may change freely. Their ids are derived from the plugin's (see
/// plugin_registry.dart), so the app recognizes them again.
class PluginInstancesRepository {
  PluginInstancesRepository(this._db)
    : _spaces = SpacesRepository(_db),
      _collections = CollectionsRepository(_db),
      _fields = FieldsRepository(_db);

  final AppDatabase _db;
  final SpacesRepository _spaces;
  final CollectionsRepository _collections;
  final FieldsRepository _fields;

  /// Active spaces created by adding [pluginId], ordered as in the
  /// sidebar.
  Stream<List<Space>> watchInstances(String pluginId) {
    return _spaces.watchAll().map(
      (spaces) => [
        for (final space in spaces)
          if (isPluginSpaceId(space.id, pluginId)) space,
      ],
    );
  }

  /// Creates a new space with the plugin's collections and their
  /// fields, all in one transaction. Returns the space's id.
  Future<String> add(TurtlePlugin plugin) {
    return _db.transaction(() async {
      final spaceId = await _spaces.create(
        id: pluginSpaceId(plugin.id, _uuid.v4()),
        name: plugin.name,
        icon: plugin.icon,
      );
      for (final template in plugin.collections) {
        final collectionId = await _collections.create(
          id: pluginCollectionId(spaceId, template.key),
          spaceId: spaceId,
          name: template.name,
          icon: template.icon,
          titleFieldLabel: template.titleLabel,
        );
        for (final field in template.fields) {
          final (type, variant, config) = _fieldTypeOf(field);
          await _fields.create(
            id: pluginFieldId(collectionId, field.key),
            collectionId: collectionId,
            name: field.name,
            type: type,
            variant: variant,
            config: config,
          );
        }
      }
      return spaceId;
    });
  }

  /// The base type, variant and base type config a template stands for -
  /// what the field editor would write for the same choices.
  static (BaseFieldType<Object, Object?>, FieldVariant<Object>?, String?) _fieldTypeOf(FieldTemplate field) {
    return switch (field) {
      TextFieldTemplate(:final variant) => (BaseFieldType.text, variant, null),
      NumberFieldTemplate(:final min, :final max) => (
        BaseFieldType.number,
        null,
        min == null && max == null ? null : jsonEncode({NumberConfig.minKey: ?min, NumberConfig.maxKey: ?max}),
      ),
      DateFieldTemplate() => (BaseFieldType.date, null, null),
      SelectFieldTemplate(:final options) => (
        BaseFieldType.select,
        null,
        encodeSelectConfig([
          for (final option in options) SelectOption(id: option.key, name: option.name, color: option.color),
        ]),
      ),
      FilesFieldTemplate(:final accept, :final maxFiles) => (
        BaseFieldType.files,
        null,
        accept.isEmpty && maxFiles == null
            ? null
            : jsonEncode({
                FilesConfig.acceptKey: ?(accept.isEmpty ? null : accept),
                FilesConfig.maxFilesKey: ?maxFiles,
              }),
      ),
    };
  }
}
