import 'dart:convert';

import 'package:field_types/field_types.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';

/// Key of a field's variant id in `fields.config`, next to its base
/// type's own config - not a column of its own, see FIELD_TYPES.md.
const fieldVariantKey = 'variant';

Map<String, Object?> decodeFieldConfig(String? config) {
  if (config == null) return {};
  final decoded = jsonDecode(config);
  return decoded is Map ? Map<String, Object?>.from(decoded) : {};
}

/// The outcome of parsing typed input for a field: either the value to
/// store or why it's invalid.
sealed class ParsedInput {
  const ParsedInput();
}

final class ParsedValue extends ParsedInput {
  const ParsedValue(this.stored);

  /// What to put into `pages.properties` - null for empty input.
  final Object? stored;
}

final class ParseError extends ParsedInput {
  const ParseError(this.message);

  final String message;
}

/// A field row with its base type, variant and typed config resolved
/// (see FieldTypeRegistry.resolve) - the one place widgets read, write
/// and validate property values through.
class ResolvedField {
  const ResolvedField({required this.row, required this.base, required this.variant, required this.config});

  final Field row;
  final BaseFieldType<Object, Object?> base;

  /// Null when the field has none, or this device doesn't know it.
  final FieldVariant<Object>? variant;
  final Object? config;

  String get id => row.id;
  String get name => row.name;
  String get typeLabel => variant?.label ?? base.label;

  InputHint? get inputHint => variant?.inputHint ?? (base is NumberFieldType ? InputHint.number : null);

  static bool isEmptyRaw(Object? raw) => raw == null || (raw is String && raw.isEmpty) || (raw is List && raw.isEmpty);

  /// The decoded value - null when empty or unreadable as [base].
  Object? valueOf(Object? raw) => isEmptyRaw(raw) ? null : base.decode(raw, config);

  /// Why a stored value is invalid, null when it's empty or valid.
  String? errorFor(Object? raw) {
    if (isEmptyRaw(raw)) return null;
    final value = base.decode(raw, config);
    if (value == null) return base.invalidMessage;
    return validate(value);
  }

  String? validate(Object value) => base.validate(value, config) ?? variant?.validate(value);

  /// Display text. A value that can't be decoded shows as its plain
  /// text, never as empty - see errorFor to flag it.
  String display(Object? raw) {
    if (isEmptyRaw(raw)) return '';
    final value = base.decode(raw, config);
    if (value == null) return plainOfRaw(raw);
    return variant?.format(value) ?? base.display(value, config);
  }

  Uri? linkFor(Object? raw) {
    if (errorFor(raw) != null) return null;
    final value = valueOf(raw);
    return value == null ? null : variant?.link(value);
  }

  /// Parses typed input: base type parse, then the variant's normalize,
  /// then both validations.
  ParsedInput parse(String text) {
    if (text.trim().isEmpty) return const ParsedValue(null);
    final parsed = base.fromPlain(text, config);
    if (parsed == null) return ParseError(base.invalidMessage);
    final value = variant?.normalize(parsed) ?? parsed;
    final error = validate(value);
    if (error != null) return ParseError(error);
    return ParsedValue(base.encode(value, config));
  }
}
