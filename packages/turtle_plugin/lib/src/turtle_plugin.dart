import 'package:field_types/field_types.dart';
import 'package:turtle_plugin/src/collection_template.dart';

/// What a plugin contributes to turtle-base. A plugin only describes
/// data and offers pure functions - the app does all the writing, so
/// sync, validation and soft-delete work as for the user's own input.
///
/// Adding a plugin creates a space holding one collection per entry of
/// [collections]. Its rows get ids derived from [id] (see the README),
/// which is how the app finds them again.
class TurtlePlugin {
  const TurtlePlugin({
    required this.id,
    required this.name,
    required this.description,
    this.icon,
    this.variants = const [],
    this.collections = const [],
  });

  /// Short and stable, without a dot, e.g. `books`. The prefix of every
  /// id the plugin brings in, so it must never change.
  final String id;

  /// Also the name of the space the plugin creates.
  final String name;
  final String description;

  /// An emoji, also used for the space.
  final String? icon;

  /// Ids prefixed with `<id>.`, e.g. `books.isbn`.
  final List<FieldVariant<Object>> variants;
  final List<CollectionTemplate> collections;
}
