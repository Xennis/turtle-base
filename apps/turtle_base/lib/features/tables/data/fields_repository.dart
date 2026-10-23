import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:field_types/field_types.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/field_type_registry.dart';
import 'package:turtle_base/features/tables/data/resolved_field.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';
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

  Stream<Field> watchById(String id) {
    return (_db.select(_db.fields)..where((f) => f.id.equals(id))).watchSingle();
  }

  /// [config] is the base type's own config (e.g. encodeSelectConfig);
  /// [variant] and its preset are merged into it.
  Future<String> create({
    required String collectionId,
    required String name,
    required BaseFieldType<Object, Object?> type,
    FieldVariant<Object>? variant,
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
            type: type.id,
            position: await _nextPosition(collectionId),
            config: Value(_withVariant(decodeFieldConfig(config), variant)),
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
  /// left as-is and read tolerantly by the new type (see FIELD_TYPES.md).
  /// The config is kept, so e.g. select options survive a switch to
  /// multi-select and back.
  Future<void> changeType(String id, FieldTypeChoice choice) async {
    final field = await _byId(id);
    return _update(
      id,
      FieldsCompanion(
        type: Value(choice.base.id),
        config: Value(_withVariant(decodeFieldConfig(field.config), choice.variant)),
      ),
    );
  }

  /// [config] is the base type's own config - the field's variant is
  /// kept.
  Future<void> updateConfig(String id, String? config) async {
    final variantId = decodeFieldConfig((await _byId(id)).config)[fieldVariantKey];
    final json = decodeFieldConfig(config);
    if (variantId != null) json[fieldVariantKey] = variantId;
    return _update(id, FieldsCompanion(config: Value(json.isEmpty ? null : jsonEncode(json))));
  }

  /// Sets single config keys, keeping all others - a null value
  /// removes its key.
  Future<void> updateConfigValues(String id, Map<String, Object?> values) async {
    final json = {...decodeFieldConfig((await _byId(id)).config), ...values}..removeWhere((_, value) => value == null);
    return _update(id, FieldsCompanion(config: Value(json.isEmpty ? null : jsonEncode(json))));
  }

  String? _withVariant(Map<String, Object?> config, FieldVariant<Object>? variant) {
    final json = {...config, ...?variant?.configPreset};
    if (variant == null) {
      json.remove(fieldVariantKey);
    } else {
      json[fieldVariantKey] = variant.id;
    }
    return json.isEmpty ? null : jsonEncode(json);
  }

  Future<Field> _byId(String id) => (_db.select(_db.fields)..where((f) => f.id.equals(id))).getSingle();

  /// Appends a new option to a select/multi-select field, with the next
  /// palette color (see [nextOptionColor]). Like the other option
  /// methods, it reads the field's current config fresh rather than
  /// trusting a caller's possibly stale copy.
  Future<SelectOption> addSelectOption(String fieldId, String name) async {
    final options = await _selectOptionsOf(fieldId);
    final option = SelectOption(id: _uuid.v4(), name: name, color: nextOptionColor(options));
    await updateConfig(fieldId, encodeSelectConfig([...options, option]));
    return option;
  }

  /// Renames and/or recolors an option, matched by its id. Property
  /// values reference options by id, so no entry needs touching.
  Future<void> updateSelectOption(String fieldId, SelectOption option) async {
    final options = await _selectOptionsOf(fieldId);
    await updateConfig(fieldId, encodeSelectConfig([for (final o in options) o.id == option.id ? option : o]));
  }

  /// Entries still referencing the option keep its id - it's skipped
  /// when reading (see resolveSelectValue) instead of rewriting every
  /// entry.
  Future<void> removeSelectOption(String fieldId, String optionId) async {
    final options = await _selectOptionsOf(fieldId);
    await updateConfig(fieldId, encodeSelectConfig(options.where((o) => o.id != optionId).toList()));
  }

  Future<List<SelectOption>> _selectOptionsOf(String fieldId) async {
    return decodeSelectOptions((await _byId(fieldId)).config);
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
      changes.copyWith(updatedAt: Value(DateTime.now()), updatedBy: Value(userId)),
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
