import 'package:turtle_base/features/tables/data/base_field_type.dart';

/// How a field's stored values follow a change of its base type, see
/// FIELD_TYPES.md.
enum ConversionMode {
  /// Values stay as they are and the new type reads them tolerantly.
  lazy,

  /// Values are rewritten - for types storing ids (select options,
  /// related pages), which another type can't tell apart from text.
  rewrite,

  /// Not offered.
  none,
}

ConversionMode conversionMode(BaseFieldType<Object, Object?> from, BaseFieldType<Object, Object?> to) {
  if (from.id == to.id) return ConversionMode.lazy;
  if (from is UnsupportedFieldType || to is UnsupportedFieldType) return ConversionMode.none;
  // Its values are attachments, not properties another type could read.
  if (from is FilesFieldType || to is FilesFieldType) return ConversionMode.none;
  if (from is SelectFieldType && to is SelectFieldType) return ConversionMode.lazy;
  if (to is RelationFieldType) return ConversionMode.none;
  if (from is RelationFieldType) return to is TextFieldType ? ConversionMode.rewrite : ConversionMode.none;
  if (from is SelectFieldType) return ConversionMode.rewrite;
  return ConversionMode.lazy;
}

/// A planned type change of a field (see FieldsRepository.planTypeChange)
/// - what it does to the values, before anything is written.
class TypeChangePlan {
  const TypeChangePlan({
    required this.fieldId,
    required this.mode,
    required this.type,
    required this.config,
    required this.valueCount,
    required this.invalidSamples,
    required this.invalidCount,
    required this.rewrites,
  });

  final String fieldId;
  final ConversionMode mode;

  /// The field's new `type` and `config` columns.
  final String type;
  final String? config;

  /// Entries with a value for the field.
  final int valueCount;

  /// Values that won't fit the new type, flagged as invalid afterwards.
  final int invalidCount;

  /// The first few of those, as currently displayed.
  final List<String> invalidSamples;

  /// New values by page id, for [ConversionMode.rewrite].
  final Map<String, Object?> rewrites;
}
