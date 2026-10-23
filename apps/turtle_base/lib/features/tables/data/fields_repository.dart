import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:field_types/field_types.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/field_conversion.dart';
import 'package:turtle_base/features/tables/data/field_type_registry.dart';
import 'package:turtle_base/features/tables/data/resolved_field.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class FieldsRepository {
  FieldsRepository(this._db, {FieldTypeRegistry? fieldTypes}) : _fieldTypes = fieldTypes ?? FieldTypeRegistry();

  final AppDatabase _db;

  /// Resolves the field's old and new type when planning a type change.
  final FieldTypeRegistry _fieldTypes;

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
  /// [variant] and its preset are merged into it. [id] defaults to a
  /// fresh uuid - plugins derive theirs (see PluginInstancesRepository).
  Future<String> create({
    required String collectionId,
    required String name,
    required BaseFieldType<Object, Object?> type,
    FieldVariant<Object>? variant,
    String? config,
    String? id,
  }) async {
    final userId = await _db.currentUserId();
    final now = DateTime.now();
    id ??= _uuid.v4();

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

  /// Changes the type right away - see [planTypeChange] to preview the
  /// effect on the values first.
  Future<void> changeType(String id, FieldTypeChoice choice) async {
    await applyTypeChange(await planTypeChange(id, choice));
  }

  /// What changing the field's type to [choice] does to its values (see
  /// FIELD_TYPES.md), without writing anything. The config is kept, so
  /// e.g. select options survive a switch to multi-select and back; a
  /// switch to (multi-)select adds an option per distinct value.
  Future<TypeChangePlan> planTypeChange(String id, FieldTypeChoice choice) async {
    final row = await _byId(id);
    final from = _fieldTypes.resolve(row);
    final mode = conversionMode(from.base, choice.base);
    final json = _withVariantJson(decodeFieldConfig(row.config), choice.variant);
    final entries = await (_db.select(
      _db.pages,
    )..where((p) => p.collectionId.equals(row.collectionId) & p.deletedAt.isNull())).get();
    final raws = {
      for (final entry in entries)
        if (decodePageProperties(entry.properties)[id] case final raw? when !ResolvedField.isEmptyRaw(raw))
          entry.id: raw,
    };

    final to = choice.base;
    if (to is SelectFieldType && from.base is! SelectFieldType && mode == ConversionMode.lazy) {
      final options = [...decodeSelectOptionsJson(json)];
      final names = {for (final option in options) option.name.toLowerCase()};
      for (final raw in raws.values) {
        final plain = from.base.toPlain(from.valueOf(raw) ?? plainOfRaw(raw), from.config);
        for (final name in to.multiple ? plain.split(',') : [plain]) {
          final trimmed = name.trim();
          if (trimmed.isEmpty || !names.add(trimmed.toLowerCase())) continue;
          options.add(SelectOption(id: _uuid.v4(), name: trimmed, color: nextOptionColor(options)));
        }
      }
      json['options'] = [for (final option in options) option.toJson()];
    }

    final config = json.isEmpty ? null : jsonEncode(json);
    final target = _fieldTypes.resolve(row.copyWith(type: to.id, config: Value(config)));
    final titles = from.base is RelationFieldType && mode == ConversionMode.rewrite
        ? await _titlesOf(raws.values.expand((raw) => from.valueOf(raw) as List<String>? ?? const []))
        : const <String, String>{};

    final rewrites = <String, Object?>{};
    final invalidSamples = <String>[];
    var invalidCount = 0;
    if (mode != ConversionMode.none) {
      for (final MapEntry(key: pageId, value: raw) in raws.entries) {
        Object? converted = raw;
        if (mode == ConversionMode.rewrite) {
          final value = from.valueOf(raw);
          final plain = switch (value) {
            null => plainOfRaw(raw),
            final List<String> ids when from.base is RelationFieldType => ids.map((i) => titles[i] ?? '?').join(', '),
            _ => from.base.toPlain(value, from.config),
          };
          // Kept as plain text when it doesn't parse, rather than as
          // ids that mean nothing to the new type.
          converted = switch (target.parse(plain)) {
            ParsedValue(:final stored) => stored,
            ParseError() => plain,
          };
          rewrites[pageId] = converted;
        }
        if (target.errorFor(converted) != null) {
          invalidCount++;
          if (invalidSamples.length < 3) invalidSamples.add(from.display(raw));
        }
      }
    }

    return TypeChangePlan(
      fieldId: id,
      mode: mode,
      type: to.id,
      config: config,
      valueCount: raws.length,
      invalidCount: invalidCount,
      invalidSamples: invalidSamples,
      rewrites: rewrites,
    );
  }

  /// Writes a plan from [planTypeChange]. A plan of mode
  /// [ConversionMode.none] is ignored.
  Future<void> applyTypeChange(TypeChangePlan plan) async {
    if (plan.mode == ConversionMode.none) return;
    final pages = PagesRepository(_db);
    await _db.transaction(() async {
      await _update(plan.fieldId, FieldsCompanion(type: Value(plan.type), config: Value(plan.config)));
      for (final MapEntry(key: pageId, value: value) in plan.rewrites.entries) {
        await pages.setPropertyValue(pageId, plan.fieldId, value);
      }
    });
  }

  Future<Map<String, String>> _titlesOf(Iterable<String> pageIds) async {
    final ids = pageIds.toSet();
    if (ids.isEmpty) return const {};
    final pages = await (_db.select(_db.pages)..where((p) => p.id.isIn(ids))).get();
    return {for (final page in pages) page.id: page.title.isEmpty ? 'Untitled' : page.title};
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
    final json = _withVariantJson(config, variant);
    return json.isEmpty ? null : jsonEncode(json);
  }

  Map<String, Object?> _withVariantJson(Map<String, Object?> config, FieldVariant<Object>? variant) {
    final json = {...config, ...?variant?.configPreset};
    if (variant == null) {
      json.remove(fieldVariantKey);
    } else {
      json[fieldVariantKey] = variant.id;
    }
    return json;
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

  /// Gives the fields [orderedIds]' order, only touching the ones whose
  /// position changes.
  Future<void> reorderAll(List<String> orderedIds) async {
    final positions = {
      for (final field in await (_db.select(_db.fields)..where((f) => f.id.isIn(orderedIds))).get())
        field.id: field.position,
    };
    await _db.transaction(() async {
      for (final (index, id) in orderedIds.indexed) {
        if (positions[id] != index) await reorder(id, index);
      }
    });
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
