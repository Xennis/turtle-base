import 'package:field_types/field_types.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/field_variants.dart';
import 'package:turtle_base/features/tables/data/resolved_field.dart';

/// One entry of the type picker: a base type, optionally with a variant.
class FieldTypeChoice {
  const FieldTypeChoice(this.base, [this.variant]);

  final BaseFieldType<Object, Object?> base;
  final FieldVariant<Object>? variant;

  /// Unique across all choices, e.g. `text` or `url`.
  String get key => variant?.id ?? base.id;
  String get label => variant?.label ?? base.label;

  @override
  bool operator ==(Object other) => other is FieldTypeChoice && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// All base types and the variants registered by the app and packages.
class FieldTypeRegistry {
  FieldTypeRegistry({List<FieldVariant<Object>> variants = const []})
    : _variants = {
        for (final variant in [...appFieldVariants, ...variants]) variant.id: variant,
      };

  final Map<String, FieldVariant<Object>> _variants;

  /// Each base type followed by its variants, so related types sit
  /// together in the picker.
  List<FieldTypeChoice> get choices => [
    for (final base in BaseFieldType.values) ...[
      FieldTypeChoice(base),
      for (final variant in _variants.values)
        if (variant.baseTypeId == base.id) FieldTypeChoice(base, variant),
    ],
  ];

  FieldTypeChoice choiceFor(ResolvedField field) => FieldTypeChoice(field.base, field.variant);

  FieldVariant<Object>? variantById(String? id) => id == null ? null : _variants[id];

  BaseFieldType<Object, Object?> baseById(String id) {
    return BaseFieldType.values.where((b) => b.id == id).firstOrNull ?? UnsupportedFieldType(id);
  }

  ResolvedField resolve(Field row) {
    final json = decodeFieldConfig(row.config);
    // A base type of its own before url became a variant - still
    // written by older app versions via sync, so mapped on every read.
    final isLegacyUrl = row.type == 'url';
    final base = isLegacyUrl ? BaseFieldType.text : baseById(row.type);
    final variantId = isLegacyUrl ? urlVariant.id : json[fieldVariantKey] as String?;
    final variant = variantById(variantId);
    return ResolvedField(
      row: row,
      base: base,
      // A variant registered for another base type than the field has
      // (e.g. after its type changed on a device without this variant)
      // is ignored rather than misapplied.
      variant: variant?.baseTypeId == base.id ? variant : null,
      config: base.decodeConfig(json),
    );
  }
}
