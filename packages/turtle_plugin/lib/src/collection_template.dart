import 'package:field_types/field_types.dart';
import 'package:turtle_plugin/src/entry_lookup.dart';

/// A collection the app creates when the plugin is added. The user may
/// change it freely afterwards - rename, reorder, add or delete fields.
class CollectionTemplate {
  const CollectionTemplate({
    required this.key,
    required this.name,
    required this.fields,
    this.icon,
    this.titleLabel,
    this.lookup,
  });

  /// Unique within the plugin, without a dot, e.g. `reading_list`.
  final String key;
  final String name;

  /// In display order.
  final List<FieldTemplate> fields;
  final String? icon;

  /// Label of the built-in title column, e.g. `Title` instead of `Name`.
  final String? titleLabel;

  /// Offered as an action in the collection's toolbar.
  final EntryLookup? lookup;
}

/// A field of a [CollectionTemplate]. Only the base types plugins need
/// so far - more are added once a plugin needs them.
sealed class FieldTemplate {
  const FieldTemplate(this.key, this.name);

  /// Unique within the collection, without a dot, e.g. `author`. Plugins
  /// address the field by it, e.g. in [EntryDraft.values].
  final String key;
  final String name;
}

final class TextFieldTemplate extends FieldTemplate {
  const TextFieldTemplate(super.key, super.name, {this.variant});

  final TextVariant? variant;
}

final class NumberFieldTemplate extends FieldTemplate {
  const NumberFieldTemplate(super.key, super.name, {this.min, this.max});

  final num? min;
  final num? max;
}

final class DateFieldTemplate extends FieldTemplate {
  const DateFieldTemplate(super.key, super.name);
}

final class SelectFieldTemplate extends FieldTemplate {
  const SelectFieldTemplate(super.key, super.name, {required this.options});

  final List<OptionTemplate> options;
}

final class FilesFieldTemplate extends FieldTemplate {
  const FilesFieldTemplate(super.key, super.name, {this.accept = const [], this.maxFiles});

  /// MIME types, MIME wildcards (`image/*`) and file extensions (`.xml`),
  /// like HTML's `accept` attribute. Empty allows any file.
  final List<String> accept;
  final int? maxFiles;
}

/// One choice of a [SelectFieldTemplate].
class OptionTemplate {
  const OptionTemplate(this.key, this.name, this.color);

  /// Unique within the field, e.g. `read`. Stored as the option's id,
  /// so [EntryDraft.values] refers to the option by it.
  final String key;
  final String name;
  final OptionColor color;
}

/// Fixed palette for select options, like Notion's - stored by name
/// rather than as a hex value, so the app can pick fitting tones for
/// light and dark mode.
enum OptionColor { gray, brown, orange, yellow, green, blue, purple, pink, red }
