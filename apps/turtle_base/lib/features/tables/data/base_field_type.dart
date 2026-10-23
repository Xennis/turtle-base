import 'package:field_types/field_types.dart';
import 'package:turtle_base/features/tables/data/field_validation.dart';
import 'package:turtle_base/features/tables/data/relation_field.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';

/// The app's closed set of field types - each with its own storage
/// form, editor and config (see FIELD_TYPES.md). Semantics on top of a
/// base type (URL, ISBN, ...) are [FieldVariant]s instead.
///
/// [V] is a decoded value, [C] the field's typed config. Every method
/// taking a raw stored value is tolerant: values may come from a
/// previous type of the field, or from another device via sync.
sealed class BaseFieldType<V extends Object, C> {
  const BaseFieldType();

  static const text = TextFieldType();
  static const number = NumberFieldType();
  static const date = DateFieldType();
  static const select = SelectFieldType(multiple: false);
  static const multiSelect = SelectFieldType(multiple: true);
  static const relation = RelationFieldType();

  /// In the order the type picker offers them.
  static const values = <BaseFieldType<Object, Object?>>[text, number, date, select, multiSelect, relation];

  /// Stored in `fields.type`.
  String get id;
  String get label;
  StorageKind get storage;

  /// Shown for a stored value [decode] can't read, or typed input
  /// [fromPlain] can't parse.
  String get invalidMessage => 'Enter a valid ${label.toLowerCase()}';

  /// [json] is the field's whole config, including keys of other
  /// concerns (e.g. `variant`) to ignore.
  C decodeConfig(Map<String, Object?> json);

  /// Null when [raw] can't be read as this type.
  V? decode(Object? raw, C config);
  Object? encode(V value, C config);

  /// Canonical text form, e.g. for converting to another type.
  String toPlain(V value, C config);

  /// Parses typed input. Null when [text] isn't a valid value.
  V? fromPlain(String text, C config);

  /// Display text - differs from [toPlain] where formatting is
  /// configurable (e.g. a number's decimals).
  String display(V value, C config) => toPlain(value, config);

  /// Config constraints (e.g. min/max). Null if [value] satisfies them.
  String? validate(V value, C config) => null;
}

/// Plain text of a stored value whatever type wrote it, for reading it
/// as another literal type (see FIELD_TYPES.md's conversion).
String plainOfRaw(Object? raw) => switch (raw) {
  null => '',
  String() => raw,
  num() => formatPlainNumber(raw),
  List() => raw.map(plainOfRaw).join(', '),
  _ => raw.toString(),
};

/// 3.0 as "3", unlike num.toString().
String formatPlainNumber(num value) {
  if (value is double && value == value.truncateToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return value.toString();
}

final class NoConfig {
  const NoConfig();
}

final class TextConfig {
  const TextConfig({this.pattern});

  static const patternKey = 'pattern';

  /// A regular expression values must fully match. Null when unset - or
  /// when it doesn't compile, so a broken pattern never blocks input.
  final RegExp? pattern;

  static TextConfig fromJson(Map<String, Object?> json) {
    final source = json[patternKey];
    return TextConfig(pattern: source is String && source.isNotEmpty ? tryParsePattern(source) : null);
  }
}

RegExp? tryParsePattern(String source) {
  try {
    return RegExp(source);
  } on FormatException {
    return null;
  }
}

final class TextFieldType extends BaseFieldType<String, TextConfig> {
  const TextFieldType();

  @override
  String get id => 'text';
  @override
  String get label => 'Text';
  @override
  StorageKind get storage => StorageKind.string;

  @override
  TextConfig decodeConfig(Map<String, Object?> json) => TextConfig.fromJson(json);

  @override
  String? decode(Object? raw, TextConfig config) => plainOfRaw(raw);
  @override
  Object? encode(String value, TextConfig config) => value;
  @override
  String toPlain(String value, TextConfig config) => value;
  @override
  String? fromPlain(String text, TextConfig config) => text;

  @override
  String? validate(String value, TextConfig config) {
    final pattern = config.pattern;
    if (pattern == null || matchesFully(pattern, value)) return null;
    return 'Must match ${pattern.pattern}';
  }
}

final class NumberConfig {
  const NumberConfig({this.min, this.max, this.decimals});

  static const minKey = 'min';
  static const maxKey = 'max';
  static const decimalsKey = 'decimals';

  final num? min;
  final num? max;

  /// Decimal places to display - values are stored unrounded.
  final int? decimals;

  static NumberConfig fromJson(Map<String, Object?> json) {
    final decimals = json[decimalsKey];
    return NumberConfig(
      min: json[minKey] as num?,
      max: json[maxKey] as num?,
      decimals: decimals is num ? decimals.toInt().clamp(0, 20) : null,
    );
  }
}

final class NumberFieldType extends BaseFieldType<num, NumberConfig> {
  const NumberFieldType();

  @override
  String get id => 'number';
  @override
  String get label => 'Number';
  @override
  StorageKind get storage => StorageKind.number;

  @override
  NumberConfig decodeConfig(Map<String, Object?> json) => NumberConfig.fromJson(json);

  /// Also reads numeric strings - how numbers were stored before
  /// FIELD_TYPES.md, and still are until edited.
  @override
  num? decode(Object? raw, NumberConfig config) => switch (raw) {
    num() => raw,
    String() => num.tryParse(raw.trim()),
    _ => null,
  };
  @override
  Object? encode(num value, NumberConfig config) => value;
  @override
  String toPlain(num value, NumberConfig config) => formatPlainNumber(value);
  @override
  num? fromPlain(String text, NumberConfig config) => isValidNumber(text.trim()) ? num.parse(text.trim()) : null;

  @override
  String display(num value, NumberConfig config) {
    final decimals = config.decimals;
    return decimals == null ? toPlain(value, config) : value.toStringAsFixed(decimals);
  }

  @override
  String? validate(num value, NumberConfig config) {
    final min = config.min;
    final max = config.max;
    if (min != null && max != null && (value < min || value > max)) {
      return 'Enter a number from ${formatPlainNumber(min)} to ${formatPlainNumber(max)}';
    }
    if (min != null && value < min) return 'Enter a number of at least ${formatPlainNumber(min)}';
    if (max != null && value > max) return 'Enter a number of at most ${formatPlainNumber(max)}';
    return null;
  }
}

/// Stored as ISO-8601: `yyyy-MM-dd` for a plain date, the full
/// timestamp when it has a time.
final class DateFieldType extends BaseFieldType<DateTime, NoConfig> {
  const DateFieldType();

  @override
  String get id => 'date';
  @override
  String get label => 'Date';
  @override
  StorageKind get storage => StorageKind.string;
  @override
  String get invalidMessage => 'Enter a valid date, e.g. 2026-07-18';

  @override
  NoConfig decodeConfig(Map<String, Object?> json) => const NoConfig();

  @override
  DateTime? decode(Object? raw, NoConfig config) => raw is String ? DateTime.tryParse(raw.trim()) : null;
  @override
  Object? encode(DateTime value, NoConfig config) => toPlain(value, config);
  @override
  String toPlain(DateTime value, NoConfig config) {
    final hasTime = value.hour != 0 || value.minute != 0 || value.second != 0 || value.millisecond != 0;
    if (hasTime) return value.toIso8601String();
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-$month-$day';
  }

  @override
  DateTime? fromPlain(String text, NoConfig config) => DateTime.tryParse(text.trim());
}

final class SelectConfig {
  const SelectConfig(this.options);

  final List<SelectOption> options;
}

/// Values are option ids - a single one for a select, a list for a
/// multi-select (see select_field.dart).
final class SelectFieldType extends BaseFieldType<List<String>, SelectConfig> {
  const SelectFieldType({required this.multiple});

  final bool multiple;

  @override
  String get id => multiple ? 'multiSelect' : 'select';
  @override
  String get label => multiple ? 'Multi-select' : 'Select';
  @override
  StorageKind get storage => multiple ? StorageKind.stringList : StorageKind.string;
  @override
  String get invalidMessage => 'Pick one of the options';

  @override
  SelectConfig decodeConfig(Map<String, Object?> json) => SelectConfig(decodeSelectOptionsJson(json));

  /// Besides option ids, reads option names - how a field converted from
  /// text stores its values until they're edited. Ids of options deleted
  /// since are skipped, like in resolveSelectValue.
  @override
  List<String>? decode(Object? raw, SelectConfig config) {
    final items = switch (raw) {
      String() when multiple => raw.split(','),
      String() => [raw],
      List() => raw.map(plainOfRaw).toList(),
      _ => [plainOfRaw(raw)],
    };
    return [for (final item in items) ?_optionFor(item, config)?.id];
  }

  @override
  Object? encode(List<String> value, SelectConfig config) => encodeSelectValue(value, multiple: multiple);

  @override
  String toPlain(List<String> value, SelectConfig config) =>
      resolveSelectValue(config.options, value).map((o) => o.name).join(', ');

  @override
  List<String>? fromPlain(String text, SelectConfig config) {
    final names = multiple ? text.split(',') : [text];
    final ids = <String>[];
    for (final name in names) {
      if (name.trim().isEmpty) continue;
      final option = _optionFor(name, config);
      if (option == null) return null;
      ids.add(option.id);
    }
    return ids;
  }

  SelectOption? _optionFor(String idOrName, SelectConfig config) {
    final trimmed = idOrName.trim();
    final lower = trimmed.toLowerCase();
    return config.options.where((o) => o.id == trimmed).firstOrNull ??
        config.options.where((o) => o.name.toLowerCase() == lower).firstOrNull;
  }
}

final class RelationConfig {
  const RelationConfig(this.targetCollectionId);

  final String? targetCollectionId;
}

/// Values are page ids of the target collection. Their titles live in
/// other rows, so plain text conversion goes through FieldsRepository.
final class RelationFieldType extends BaseFieldType<List<String>, RelationConfig> {
  const RelationFieldType();

  @override
  String get id => 'relation';
  @override
  String get label => 'Relation';
  @override
  StorageKind get storage => StorageKind.stringList;

  @override
  RelationConfig decodeConfig(Map<String, Object?> json) =>
      RelationConfig(json[relationTargetCollectionIdKey] as String?);

  @override
  List<String>? decode(Object? raw, RelationConfig config) => raw is List ? decodeRelationValue(raw) : null;
  @override
  Object? encode(List<String> value, RelationConfig config) => value;
  @override
  String toPlain(List<String> value, RelationConfig config) => value.join(', ');
  @override
  List<String>? fromPlain(String text, RelationConfig config) => null;
}

/// A type this app version doesn't know, e.g. one a newer version
/// synced in. Shown read-only as plain text rather than failing.
final class UnsupportedFieldType extends BaseFieldType<Object, NoConfig> {
  const UnsupportedFieldType(this.id);

  @override
  final String id;
  @override
  String get label => 'Unsupported ($id)';
  @override
  StorageKind get storage => StorageKind.object;

  @override
  NoConfig decodeConfig(Map<String, Object?> json) => const NoConfig();

  @override
  Object? decode(Object? raw, NoConfig config) => raw;
  @override
  Object? encode(Object value, NoConfig config) => value;
  @override
  String toPlain(Object value, NoConfig config) => plainOfRaw(value);
  @override
  Object? fromPlain(String text, NoConfig config) => null;
}
