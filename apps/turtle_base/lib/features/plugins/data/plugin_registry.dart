import 'package:turtle_plugin/turtle_plugin.dart';

/// The plugins the app ships with - registered at compile time, there's
/// no loading at runtime.
class PluginRegistry {
  /// Throws an [ArgumentError] for a plugin breaking the id rules of
  /// turtle_plugin's README - a programming error, caught by any test
  /// that builds the registry.
  PluginRegistry([List<TurtlePlugin> plugins = const []]) : plugins = List.unmodifiable(plugins) {
    final ids = <String>{};
    for (final plugin in plugins) {
      _checkKey(plugin.id, 'plugin id');
      if (!ids.add(plugin.id)) throw ArgumentError('Duplicate plugin id ${plugin.id}');
      _checkPlugin(plugin);
    }
  }

  final List<TurtlePlugin> plugins;

  List<FieldVariant<Object>> get variants => [for (final plugin in plugins) ...plugin.variants];

  /// Plugins that create a space when added - one with only variants
  /// has nothing to add.
  List<TurtlePlugin> get addable => [
    for (final plugin in plugins)
      if (plugin.collections.isNotEmpty) plugin,
  ];

  TurtlePlugin? byId(String id) => plugins.where((p) => p.id == id).firstOrNull;

  /// The template [collectionId] was created from, null for a collection
  /// the user created or one of a plugin this device doesn't have.
  CollectionTemplate? templateOf(String collectionId) {
    final parts = collectionId.split(idSeparator);
    if (parts.length != 3) return null;
    return byId(parts.first)?.collections.where((c) => c.key == parts.last).firstOrNull;
  }

  void _checkPlugin(TurtlePlugin plugin) {
    for (final variant in plugin.variants) {
      if (!variant.id.startsWith('${plugin.id}$idSeparator')) {
        throw ArgumentError('Variant ${variant.id} of plugin ${plugin.id} must start with "${plugin.id}."');
      }
    }
    _checkUnique(plugin.collections.map((c) => c.key), 'collection key in ${plugin.id}');
    for (final collection in plugin.collections) {
      _checkUnique(collection.fields.map((f) => f.key), 'field key in ${plugin.id}.${collection.key}');
      for (final field in collection.fields) {
        if (field is SelectFieldTemplate) {
          _checkUnique(field.options.map((o) => o.key), 'option key in ${collection.key}.${field.key}');
        }
      }
    }
  }

  static void _checkUnique(Iterable<String> keys, String what) {
    final seen = <String>{};
    for (final key in keys) {
      _checkKey(key, what);
      if (!seen.add(key)) throw ArgumentError('Duplicate $what: $key');
    }
  }

  static void _checkKey(String key, String what) {
    if (key.isEmpty || key.contains(idSeparator)) throw ArgumentError('Invalid $what "$key": empty or contains a dot');
  }
}

/// Separates the parts of the ids a plugin's rows get, e.g.
/// `books.<uuid>.reading_list` - see turtle_plugin's README.
const idSeparator = '.';

String pluginSpaceId(String pluginId, String instanceId) => '$pluginId$idSeparator$instanceId';

String pluginCollectionId(String spaceId, String templateKey) => '$spaceId$idSeparator$templateKey';

String pluginFieldId(String collectionId, String fieldKey) => '$collectionId$idSeparator$fieldKey';

/// Whether [spaceId] is a space created by adding the plugin [pluginId].
bool isPluginSpaceId(String spaceId, String pluginId) {
  final parts = spaceId.split(idSeparator);
  return parts.length == 2 && parts.first == pluginId;
}
