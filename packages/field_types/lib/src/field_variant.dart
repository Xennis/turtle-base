/// The JSON shape a field value is stored in, in `pages.properties`.
enum StorageKind { string, number, boolean, stringList, object }

/// How a variant's values are typed in, so the app can pick a fitting
/// keyboard without this package depending on Flutter.
enum InputHint { text, number, url, email, phone }

/// Semantics on top of one of the app's base field types - e.g. an ISBN
/// is a text field that validates, normalizes and formats its value.
/// Stored like its base type, so a device that doesn't know the variant
/// still reads the field as its plain base type.
///
/// Only [TextVariant] and [NumberVariant] exist: a variant can't bring
/// its own storage, see FIELD_TYPES.md.
sealed class FieldVariant<V extends Object> {
  const FieldVariant({
    required this.id,
    required this.label,
    this.inputHint,
    this.configPreset,
    this._validate,
    this._normalize,
    this._format,
    this._link,
  });

  /// Stored in the field's config. Namespaced for packages (e.g.
  /// `books.isbn`), plain for the app's own (e.g. `url`).
  final String id;
  final String label;
  final InputHint? inputHint;

  /// Merged into the base type's config when the variant is picked, e.g.
  /// `{"min": 1, "max": 5}` for a rating.
  final Map<String, Object?>? configPreset;

  // Kept private behind methods: a function-typed field read through a
  // FieldVariant<Object> fails Dart's covariance check at runtime.
  final String? Function(V value)? _validate;
  final V Function(V value)? _normalize;
  final String Function(V value)? _format;
  final Uri? Function(V value)? _link;

  /// The id of the base type this variant builds on.
  String get baseTypeId;

  /// An error message, or null if [value] is valid.
  String? validate(V value) => _validate?.call(value);

  /// Applied before validating and storing user input.
  V normalize(V value) => _normalize?.call(value) ?? value;

  /// Display text, or null to fall back to the base type's.
  String? format(V value) => _format?.call(value);

  /// Where tapping the value leads, e.g. a mailto: link. Null when it
  /// isn't a link.
  Uri? link(V value) => _link?.call(value);
}

final class TextVariant extends FieldVariant<String> {
  const TextVariant({
    required super.id,
    required super.label,
    super.inputHint,
    super.configPreset,
    super.validate,
    super.normalize,
    super.format,
    super.link,
  });

  /// A variant whose values must fully match [pattern].
  factory TextVariant.pattern({
    required String id,
    required String label,
    required RegExp pattern,
    required String message,
    InputHint? inputHint,
    String Function(String value)? normalize,
    Uri? Function(String value)? link,
  }) {
    return TextVariant(
      id: id,
      label: label,
      inputHint: inputHint,
      normalize: normalize,
      link: link,
      validate: (value) => matchesFully(pattern, value) ? null : message,
    );
  }

  @override
  String get baseTypeId => 'text';
}

final class NumberVariant extends FieldVariant<num> {
  const NumberVariant({
    required super.id,
    required super.label,
    super.configPreset,
    super.validate,
    super.normalize,
    super.format,
    super.link,
  }) : super(inputHint: InputHint.number);

  @override
  String get baseTypeId => 'number';
}

/// Whether [pattern] matches all of [value], not just a part of it.
bool matchesFully(RegExp pattern, String value) {
  final match = pattern.matchAsPrefix(value);
  return match != null && match.end == value.length;
}
