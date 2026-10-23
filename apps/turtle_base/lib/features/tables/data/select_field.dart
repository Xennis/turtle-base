import 'dart:convert';

/// Fixed palette for select options, like Notion's - stored by name
/// rather than as a hex value, so the UI can pick fitting tones for
/// light and dark mode (see SelectOptionChip).
enum OptionColor { gray, brown, orange, yellow, green, blue, purple, pink, red }

/// One choice of a select/multi-select field. Property values reference
/// it by [id], never by [name], so renaming or recoloring an option
/// only touches `fields.config`, not every entry using it.
class SelectOption {
  const SelectOption({required this.id, required this.name, required this.color});

  final String id;
  final String name;
  final OptionColor color;

  SelectOption copyWith({String? name, OptionColor? color}) {
    return SelectOption(id: id, name: name ?? this.name, color: color ?? this.color);
  }

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'color': color.name};

  static SelectOption fromJson(Map<String, dynamic> json) {
    return SelectOption(
      id: json['id'] as String,
      name: json['name'] as String,
      color: OptionColor.values.asNameMap()[json['color']] ?? OptionColor.gray,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SelectOption && other.id == id && other.name == name && other.color == color;

  @override
  int get hashCode => Object.hash(id, name, color);
}

/// Encodes a select/multi-select field's `fields.config` - its options,
/// in display order.
String encodeSelectConfig(List<SelectOption> options) {
  return jsonEncode({
    'options': [for (final option in options) option.toJson()],
  });
}

List<SelectOption> decodeSelectOptions(String? config) {
  if (config == null) return const [];
  return decodeSelectOptionsJson(jsonDecode(config) as Map<String, dynamic>);
}

List<SelectOption> decodeSelectOptionsJson(Map<String, Object?> config) {
  final options = config['options'];
  if (options is! List) return const [];
  return [for (final option in options) SelectOption.fromJson(option as Map<String, dynamic>)];
}

/// The color a newly created option gets - rotating through the
/// palette, so consecutive options are told apart without picking.
OptionColor nextOptionColor(List<SelectOption> existing) {
  return OptionColor.values[existing.length % OptionColor.values.length];
}

/// A select property value is a single option id, a multi-select one a
/// JSON array of option ids. Accepts both forms either way, so switching
/// a field between select and multi-select keeps its values.
List<String> decodeSelectValue(Object? raw) {
  if (raw is String) return raw.isEmpty ? const [] : [raw];
  if (raw is List) return raw.whereType<String>().toList();
  return const [];
}

/// The options [raw] refers to, in the order they're stored. Ids of
/// options deleted since are skipped.
List<SelectOption> resolveSelectValue(List<SelectOption> options, Object? raw) {
  final byId = {for (final option in options) option.id: option};
  return [for (final id in decodeSelectValue(raw)) ?byId[id]];
}

/// What to store in `pages.properties` for the option ids [ids]: a
/// single id (or null) for a select field, the list for a multi-select.
Object? encodeSelectValue(List<String> ids, {required bool multiple}) {
  if (multiple) return ids;
  return ids.isEmpty ? null : ids.first;
}
