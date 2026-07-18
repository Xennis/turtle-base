/// Shared value validation for typed [FieldType]s, used by both the
/// collection grid (CollectionView) and the entry detail page
/// (PagePropertiesHeader) so the two agree on what counts as valid -
/// both for rejecting new invalid input and for flagging values that
/// no longer match a field's type (e.g. after changing it).
library;

import 'package:turtle_base/features/tables/data/field_type.dart';

bool isValidUrl(String value) {
  final withScheme = value.contains('://') ? value : 'https://$value';
  final uri = Uri.tryParse(withScheme);
  return uri != null && uri.host.isNotEmpty && uri.host.contains('.');
}

/// Accepts anything DateTime.parse understands, e.g. the grid's own
/// yyyy-MM-dd as well as a fuller ISO-8601 timestamp.
bool isValidDate(String value) => DateTime.tryParse(value) != null;

bool isValidNumber(String value) => num.tryParse(value) != null;

/// Whether [value] is acceptable for a field of type [type]. Empty is
/// always acceptable - fields are optional.
bool isValidForType(FieldType type, String value) {
  if (value.isEmpty) return true;
  return switch (type) {
    FieldType.number => isValidNumber(value),
    FieldType.date => isValidDate(value),
    FieldType.url => isValidUrl(value),
    FieldType.text || FieldType.relation => true,
  };
}

/// The message to show for an invalid value of [type]. Null for types
/// that are never invalid (text, relation).
String? invalidMessageFor(FieldType type) => switch (type) {
  FieldType.number => 'Enter a valid number',
  FieldType.date => 'Enter a valid date, e.g. 2026-07-18',
  FieldType.url => 'Enter a valid URL, e.g. example.com',
  FieldType.text || FieldType.relation => null,
};
